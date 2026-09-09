import Foundation

/// The Claude Code skill file, generated rather than kept.
///
/// A skill is one Markdown file with a little YAML on top, dropped in `~/.claude/skills/toe/`,
/// which an agent reads when a request looks like it is about windows. The obvious way to ship
/// one is to commit it and copy it out of the bundle — and that is exactly how the file and the
/// program drift apart: the day a verb is added, the skill still lists the old set, and a model
/// reading it calls something that does not exist with complete confidence.
///
/// So the half that can go stale is not written by hand. The verb table below is
/// `CommandCatalogue.entries`, which is the same table `toe query commands` answers with and
/// whose every sample the selftest parses. The rest is prose about things a model cannot
/// discover by asking — that a workspace is not a Space, that a fullscreen window suspends half
/// the verbs, that a window somebody is dragging is not toe's to write to. Those are the notes
/// that took a version each to learn, and they are the reason this file is worth having at all.
public enum SkillDocument {

    public static let directoryName = "toe"
    public static let fileName = "SKILL.md"

    /// - Parameter binary: the absolute path to the toe that wrote this. Baked in rather than
    ///   left as a bare `toe`, because nothing puts toe on a PATH: it lives inside an
    ///   application bundle, and an agent that has to guess where is an agent that gives up.
    ///   It also makes the document honest about *which* copy wrote it — the development build
    ///   names itself, so a skill written by `make run` does not quietly point at
    ///   /Applications.
    public static func text(binary: String, version: String? = nil) -> String {
        let stamp = version.map { " \($0)" } ?? ""
        return frontmatter + "\n" + body(binary: binary, stamp: stamp) + "\n" + verbs + "\n" + closing(binary: binary)
    }

    private static let frontmatter = #"""
    ---
    name: toe
    description: >-
      Inspect and rearrange the windows on this Mac through toe, the tiling window manager —
      list windows, workspaces and displays; move windows between workspaces; focus, close,
      float and resize them; and save or restore named layouts. Use whenever the user asks to
      arrange, tidy, move, focus, split or set up windows, workspaces or their screen layout on
      macOS, or asks what is open.
    ---
    """#

    private static func body(binary: String, stamp: String) -> String {
        #"""

        # Driving toe\#(stamp)

        toe is a tiling window manager running as a background agent. It is a port of Hyprland's
        dwindle layout, so its verbs are Hyprland's verbs and a config copied from Omarchy mostly
        works. You talk to the running copy through its own binary:

            \#(binary) query state

        Every reply is JSON on stdout — `{"ok":true,"result":…}` — or exit 1 with a sentence on
        stderr. Exit 2 means the command line itself was wrong and nothing reached toe.

        If that path does not exist, toe has been moved or is not installed; do not guess at
        another one. If a call reports that toe is not running, say so rather than starting it —
        starting a window manager rearranges the user's screen and is theirs to ask for.

        ## Read before you write

        Start with `query state`. It returns the displays, the ten workspaces, every managed
        window with its id, application, title, workspace and frame, and what currently holds the
        focus. Almost every mistake in this domain is acting on a stale idea of what is open, and
        one query costs nothing.

        Windows are identified by `id`, a `CGWindowID` the window server keeps stable for the life
        of the window. Do not remember one across a restart of the application that owns it.

        ## Acting

            \#(binary) dispatch "workspace 3"
            \#(binary) dispatch "movetoworkspace 2" "workspace 2"
            \#(binary) dispatch --window app:Safari "movetoworkspace 3"
            \#(binary) focus app:Ghostty

        Several command lines in one `dispatch` are applied as a batch and drawn once at the end.
        Prefer that to a sequence of separate calls: the difference on screen is an arrangement
        appearing against an arrangement being assembled in front of the user.

        `--window` names a window other than the one holding the focus, and only the verbs marked
        below accept it. The directional verbs deliberately do not — `movefocus l` means "left of
        where the focus is", and pointing it somewhere else would be a different command with the
        same name. To act directionally elsewhere, `focus` there first.

        ### Selectors

            id:4213                 exactly that window — the only form that is not a guess
            app:Ghostty             application name, or its bundle identifier
            bundle:com.apple.Safari the bundle identifier alone
            title:release           a substring of the title, case-insensitive
            workspace:3             everything on that workspace
            Ghostty                 no prefix: application first, then title

        Prefer `app:`. A selector that matches more than one window is refused, and the refusal
        lists the candidates with their ids — use one of those rather than guessing.

        """#
    }

    /// The table, from `CommandCatalogue`. Generated so that a verb added to the parser and the
    /// catalogue reaches the skill file without anybody remembering to come here.
    private static var verbs: String {
        var out = "## The verbs\n\nEvery one of these is a line for `dispatch`. "
            + "`\u{2022}` marks the ones `--window` accepts.\n\n"
        for entry in CommandCatalogue.entries {
            let mark = entry.takesWindow ? "\u{2022} " : "  "
            out += "- \(mark)`\(entry.usage)` — \(entry.summary)"
            if !entry.aliases.isEmpty {
                out += " Also: \(entry.aliases.map { "`\($0)`" }.joined(separator: ", "))."
            }
            out += "\n"
        }
        out += "\n`toe query commands` is this same table as JSON, and is the authority if the two"
             + " ever disagree.\n"
        return out
    }

    private static func closing(binary: String) -> String {
        #"""

        ## Layouts

            \#(binary) layout save work
            \#(binary) layout apply work

        A profile records which workspace each window belongs on, in what order, and whether it
        floats — named by application rather than by window id, so it survives quitting and
        restarting those applications. It does not record split ratios. Applying one moves only
        the windows it names; anything else is left where it is, and windows the profile names
        that are not open come back in `missing` rather than being silently skipped.

        ## Things that will surprise you

        - **A toe workspace is not a macOS Space.** There is no public API for putting a window on
          another Space, so a hidden workspace's windows are parked far off-screen. They are still
          in Cmd-Tab and Mission Control, and a window reported as `hidden` is one of those. It has
          not been closed.
        - **A native-fullscreen window suspends half the verbs.** While one holds the focus,
          anything that moves the focus, a window or a workspace is refused — it would act on the
          workspace behind a screen the user cannot see. Check `query state` if a dispatch appears
          to have done nothing.
        - **Floating windows are the user's.** toe writes a floating window's frame once and never
          re-asserts it, on purpose. Do not repeatedly place one.
        - **Never write to a window being dragged.** toe already refuses; a burst of commands
          while somebody has hold of a window is still a fight worth not starting.
        - **`exec` and `quit` are refused over this socket** unless the config's `[cli]` section
          allows them. That is deliberate: `exec` would make this a shell. If the user wants a
          program launched, use the ordinary way of launching programs.
        - **Some applications push back.** Chromium, Electron and JetBrains windows re-apply their
          own geometry, and toe re-asserts a frame three times before leaving them alone. A window
          that will not sit in its tile has a minimum size larger than the tile.

        ## Working with the user

        Rearranging somebody's screen is visible and interrupting. Say what you are about to move
        before moving it, prefer one batch to a stream of small changes, and if the user wants to
        be able to get back — `layout save` first, and tell them the name.

        """#
    }
}
