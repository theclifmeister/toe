import Foundation

/// The line formats of the journals under `~/.local/state/toe`.
///
/// Each journal is a note of what a macOS setting was before toe changed it, written *before*
/// the change so that a crash between the two leaves a record that says too much rather than one
/// that says too little — see `SymbolicHotkeys` and its siblings in the app layer, which own the
/// files. What is here is only the text: how a record becomes lines and how lines become a record
/// again, kept apart from the file so the selftest can reach it.
///
/// Every parser here has the same rule: a line it cannot read is *dropped*, never guessed at. A
/// journal is replayed straight into the window server or `cfprefsd` at startup, so a truncated
/// write or a hand-edit must be at worst a setting toe forgets to give back, and never a value
/// the user did not have. The formats are frozen — an upgrade replays the journal the previous
/// version left, so what a line looks like on disk is part of the interface.
public enum JournalFormat {

    // MARK: - One number per line

    /// `SymbolicHotkeys`: the key codes toe switched off, one per line.
    public static func serialise(codes: [Int32]) -> String {
        codes.map(String.init).joined(separator: "\n")
    }

    /// Anything that is not a whole number is dropped.
    public static func parseCodes(_ text: String) -> [Int32] {
        text.split(whereSeparator: \.isNewline).compactMap { Int32($0) }
    }

    // MARK: - One bare word

    /// `WallpaperClick` and `DockAutoHide`: a single state, written bare. The whole file has to
    /// be one of the caller's words, whitespace aside, or it means nothing.
    public static func serialise<State: RawRepresentable>(word: State) -> String
    where State.RawValue == String {
        word.rawValue
    }

    public static func parseWord<State: RawRepresentable>(_ text: String, as _: State.Type = State.self) -> State?
    where State.RawValue == String {
        State(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - key=state per line

    /// `EdgeTiling`: one `key=state` per line, in the order `keys` lists them — so a file left
    /// behind by a crash reads the way System Settings does. Naming the keys is what lets the
    /// file survive one of the pair being added or dropped later: `parseKeyed` ignores a line
    /// it does not recognise.
    public static func serialise<State: RawRepresentable>(keyed states: [String: State],
                                                          order keys: [String]) -> String
    where State.RawValue == String {
        keys.compactMap { key in states[key].map { "\(key)=\($0.rawValue)" } }
            .joined(separator: "\n")
    }

    /// A line without an `=`, naming a key not in `keys`, or carrying a state that is not one
    /// of `State`'s words is dropped. Whitespace around either half is forgiven, because a
    /// hand-edit is the likeliest way a stray space gets in.
    public static func parseKeyed<State: RawRepresentable>(_ text: String, keys: [String],
                                                            as _: State.Type = State.self) -> [String: State]
    where State.RawValue == String {
        var states: [String: State] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            guard keys.contains(key),
                  let state = State(rawValue: String(parts[1]).trimmingCharacters(in: .whitespaces))
            else { continue }
            states[key] = state
        }
        return states
    }

    // MARK: - key<TAB>value per line

    /// `Wallpaper`: one display per line, the key and the picture's path tab-separated, sorted
    /// by key so the file is the same whatever order the displays were seen in. A path can hold
    /// anything but a tab and a newline, and this file is read by the same code that wrote it.
    public static func serialise(tabbed entries: [String: String]) -> String {
        entries.sorted { $0.key < $1.key }
            .map { "\($0.key)\t\($0.value)" }
            .joined(separator: "\n")
    }

    /// A line with more or fewer than one tab, or an empty half, is dropped — a path is never
    /// trimmed, because a path may legitimately end in a space.
    public static func parseTabbed(_ text: String) -> [String: String] {
        var entries: [String: String] = [:]
        for line in text.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "\t")
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { continue }
            entries[parts[0]] = parts[1]
        }
        return entries
    }
}
