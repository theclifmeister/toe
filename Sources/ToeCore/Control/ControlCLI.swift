import Foundation

/// What toe should do about the words after its own name.
///
/// The same binary is the agent and the thing you type at it, which is not a trick: `main.swift`
/// has always decided by argv — `--version` and `--print-default-config` predate any of this —
/// and a second executable would need a second code signature, a second Accessibility grant it
/// does not want, and somewhere to be installed. One binary, two jobs, told apart by the first
/// word.
///
/// So this is the doorman, and it is in ToeCore because argument parsing is arithmetic and
/// belongs where `make test` can reach it. Nothing here opens a socket or touches a file.
public struct CLIInvocation: Equatable {

    public enum Skill: String, Equatable, Sendable {
        case install
        case remove
        case status
        /// Print the document to stdout without writing it anywhere — the way to read what a
        /// row in the menu is about to put on your disk before you let it.
        case print
    }

    public enum Kind: Equatable {
        /// No verb: this invocation is the window manager, exactly as it has always been.
        case agent
        case help(String)
        /// Nothing was run and something was wrong with the way it was asked. Exit 2, so a
        /// script can tell a mistyped command from a command that reached toe and failed.
        case error(String)
        /// Done here, with no running toe involved: writing a file needs a file, not an agent.
        case skill(Skill)
        case request(ControlRequest)
    }

    public var kind: Kind
    /// A `-` stood where command lines were expected. The client fills them from stdin — which
    /// ToeCore cannot do and should not know how to.
    public var readsStdin: Bool

    public init(_ kind: Kind, readsStdin: Bool = false) {
        self.kind = kind
        self.readsStdin = readsStdin
    }
}

public enum ControlCLI {

    /// The verbs that mean "talk to the running toe" rather than "be the running toe", plus the
    /// one that means the opposite and is here for the reason below.
    public static let verbs = ["query", "dispatch", "focus", "layout", "skill", "help", "agent"]

    /// - Parameters:
    ///   - arguments: everything after the executable's own name.
    ///   - isInteractive: whether this came from a shell — `isatty` on either standard input or
    ///     standard output, decided by the caller because ToeCore has neither.
    public static func parse(_ arguments: [String], isInteractive: Bool = false) -> CLIInvocation {
        guard let verb = arguments.first else {
            // A bare `toe` from a shell prints the usage rather than starting the window
            // manager, and this matters exactly as much as `toe` being on a PATH does.
            //
            // Started from a shell, the agent is a child of that shell: it inherits the terminal's
            // process group, so closing the window or pressing ^C sends it a signal and
            // `installSignalHandlers` shuts it down — after `AppIdentity.takeOver` has already
            // stopped the copy that was running properly. Somebody typing `toe` to see what it
            // does would therefore replace a working window manager with one that dies when they
            // close the tab, and nothing on screen would explain either half of that. This is not
            // hypothetical: it is what happened the first time this was tested, and the test was
            // `toe | head`.
            //
            // Which is why the question is asked of standard input *and* standard output rather
            // than one of them. Either alone is a rule with a hole in it that a pipe or a
            // redirect walks straight through — `toe | head` has no terminal on stdout, and
            // `toe > log` has none either, and both were typed by somebody at a prompt. Together
            // they say something simple enough to rely on: from a shell, `toe` never becomes the
            // window manager. launchd and `open Toe.app` have neither, which is every way toe is
            // meant to start, and `toe agent` is how you ask for it from a shell on purpose.
            return CLIInvocation(isInteractive ? .help(usage) : .agent)
        }

        // A leading flag is not a verb. `open Toe.app` passes `-psn_0_1234` on some launches and
        // the release workflow passes `--version`, and neither is somebody trying to drive toe
        // from a shell — so anything beginning with a dash falls through to the agent and to the
        // flag handling that has always been there.
        guard !verb.hasPrefix("-") else { return CLIInvocation(.agent) }

        // A first word that is not a flag and not a verb is a typo, and the one thing it must not
        // do is start a second window manager. `toe quer windows` says so and stops.
        guard verbs.contains(verb) else {
            return CLIInvocation(.error("unknown command '\(verb)' — try `toe help`"))
        }

        let rest = Array(arguments.dropFirst())

        switch verb {
        case "help":
            return CLIInvocation(.help(usage))

        // The window manager, asked for in as many words. The only reason to type it is that a
        // shell is where you are and the agent is what you want — a debug build, or a run you
        // intend to watch with TOE_VERBOSE — and the bare `toe` above deliberately no longer
        // means that from a shell, however its output is redirected.
        case "agent":
            return CLIInvocation(.agent)

        case "query":
            guard let what = rest.first else {
                return CLIInvocation(.error("query needs one of: "
                                            + ControlQuery.allCases.map(\.rawValue).joined(separator: ", ")))
            }
            guard ControlQuery(rawValue: what) != nil else {
                return CLIInvocation(.error("no such query '\(what)' — try one of: "
                                            + ControlQuery.allCases.map(\.rawValue).joined(separator: ", ")))
            }
            return CLIInvocation(.request(ControlRequest(op: .query, what: what)))

        case "dispatch":
            var window: String?
            var lines: [String] = []
            var stdin = false
            var index = 0
            while index < rest.count {
                let argument = rest[index]
                if argument == "--window" || argument == "-w" {
                    guard index + 1 < rest.count else {
                        return CLIInvocation(.error("--window needs a selector, such as app:Ghostty"))
                    }
                    window = rest[index + 1]
                    index += 2
                    continue
                }
                // `--window=app:Ghostty` as well as the two-word form: both are typed, and a
                // caller that guesses wrong should not have to guess twice.
                if let value = argument.dropPrefixed("--window=") {
                    window = value
                    index += 1
                    continue
                }
                if argument == "-" { stdin = true } else { lines.append(argument) }
                index += 1
            }
            guard !lines.isEmpty || stdin else {
                return CLIInvocation(.error("dispatch needs a command line, such as "
                                            + "`toe dispatch \"workspace 3\"` — `toe query commands` lists them"))
            }
            return CLIInvocation(.request(ControlRequest(op: .dispatch, commands: lines, window: window)),
                                 readsStdin: stdin)

        case "focus":
            guard let selector = rest.first, !selector.isEmpty else {
                return CLIInvocation(.error("focus needs a selector, such as app:Ghostty"))
            }
            return CLIInvocation(.request(ControlRequest(op: .focus, window: selector)))

        case "layout":
            return layout(rest)

        case "skill":
            let what = rest.first ?? "status"
            guard let action = CLIInvocation.Skill(rawValue: what) else {
                return CLIInvocation(.error("no such skill action '\(what)' — "
                                            + "install, remove, status or print"))
            }
            return CLIInvocation(.skill(action))

        default:
            return CLIInvocation(.error("unknown command '\(verb)' — try `toe help`"))
        }
    }

    private static func layout(_ rest: [String]) -> CLIInvocation {
        guard let action = rest.first else {
            return CLIInvocation(.error("layout needs one of: save, apply, list, show, delete"))
        }
        let name = rest.count > 1 ? rest[1] : nil

        func named(_ op: ControlRequest.Op) -> CLIInvocation {
            guard let name, !name.isEmpty else {
                return CLIInvocation(.error("layout \(action) needs a name, such as `toe layout \(action) work`"))
            }
            return CLIInvocation(.request(ControlRequest(op: op, what: name)))
        }

        switch action {
        case "save":   return named(.layoutSave)
        case "apply":  return named(.layoutApply)
        case "show":   return named(.layoutShow)
        case "delete", "remove": return named(.layoutDelete)
        case "list":   return CLIInvocation(.request(ControlRequest(op: .layoutList)))
        default:
            return CLIInvocation(.error("no such layout action '\(action)' — "
                                        + "save, apply, list, show or delete"))
        }
    }

    /// Written for a person at a terminal. The machine-readable half is `toe query commands`,
    /// which is a table rather than prose and is what the skill document is generated from —
    /// so this can stay short without leaving anything undocumented.
    public static let usage = """
    toe — a tiling window manager, and the command line that steers it.

    With one of the verbs below it talks to the copy already running, over a socket in
    ~/.local/state/toe.

      toe query state             everything at once: monitors, workspaces, windows, focus
      toe query windows           every managed window, with its workspace and frame
      toe query workspaces        what is on each of the ten, and which are showing
      toe query monitors          the displays and their tiling areas
      toe query binds             the live keybindings
      toe query commands          every verb dispatch accepts — the vocabulary
      toe query layouts           the saved layout profiles
      toe query skill             where the agent skill file is, and whether it is current

      toe dispatch "workspace 3"                run a command
      toe dispatch "workspace 3" "movefocus l"  run several, rendering once at the end
      toe dispatch -                            read command lines from stdin
      toe dispatch --window app:Safari "movetoworkspace 3"
                                                act on a window other than the focused one
      toe focus app:Ghostty                     bring a window forward, revealing its workspace

      toe layout save work        remember where everything is, under a name
      toe layout apply work       put the windows that are open back into that arrangement
      toe layout list             the profiles in ~/.config/toe/layouts
      toe layout show work        one profile, as JSON
      toe layout delete work      forget it

      toe skill install           write the Claude Code skill into ~/.claude/skills/toe
      toe skill remove            take it away again
      toe skill status            where it is and whether it matches this copy of toe
      toe skill print             the document, to stdout, without writing anything

      toe agent                   run the window manager here, in this shell

    With no arguments and no terminal — from launchd, or `open Toe.app` — toe *is* the window
    manager. Run from a shell with no arguments it prints this instead, because a window manager
    started from a shell dies with that shell. `toe agent` does it anyway.

    Window selectors:  id:4213  app:Ghostty  bundle:com.apple.Safari  title:release  workspace:3
    A bare word tries the application first, then the title.

    Replies are JSON on stdout: {"ok":true,"result":…}. A refusal exits 1 with a sentence on
    stderr; a mistyped command exits 2 without reaching toe at all.

    exec and quit are refused over the socket unless [cli] allow_exec / allow_quit say otherwise.
    """
}

private extension String {
    /// `--window=app:Ghostty` → `app:Ghostty`, or nil when the prefix is not there.
    func dropPrefixed(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        let value = String(dropFirst(prefix.count))
        return value.isEmpty ? nil : value
    }
}
