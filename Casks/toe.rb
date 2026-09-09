# frozen_string_literal: true

cask "toe" do
  # Both lines below are rewritten by .github/workflows/release.yml on each tag.
  version "0.22.0"
  sha256 "911762ec9c5b9036e3228dc6afe2e9a3e756b439c72c90bbd425ec44583874eb"

  url "https://github.com/theclifmeister/toe/releases/download/v#{version}/toe-#{version}-arm64.zip"
  name "Toe"
  desc "Omarchy-style dwindle window manager"
  homepage "https://github.com/theclifmeister/toe"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma
  depends_on arch: :arm64

  app "Toe.app"

  # `toe` on the PATH, pointing into the bundle rather than at a copy of it — the same binary is
  # the window manager and the command line that steers it, told apart by its first argument, so
  # there is nothing else to install and nothing that can fall out of step with the app.
  #
  # Homebrew symlinks this into its own bin, which is already on the PATH of anyone who installed
  # toe this way, and removes it on uninstall. See `toe help`, and `toe skill install` for the
  # Claude Code skill.
  binary "#{appdir}/Toe.app/Contents/MacOS/toe"

  uninstall launchctl: "com.clifmeister.toe",
            quit:      "com.clifmeister.toe"

  zap trash: [
    "~/.config/toe",
    "~/Library/LaunchAgents/com.clifmeister.toe.plist",
    "~/Library/Saved Application State/com.clifmeister.toe.savedState",
  ]

  # The upgrade paragraph below is for the 0.3.0 → Developer ID switchover only. Drop it a
  # release or two after 0.4.0, once nobody is upgrading across that boundary any more.
  caveats do
    <<~EOS
      Grant toe Accessibility before it can manage windows:
        System Settings → Privacy & Security → Accessibility

      Upgrading from 0.3.0 or earlier? toe is now signed with an Apple Developer ID and
      notarized, where it used to carry a self-signed certificate. macOS keys Accessibility
      to the signature, so it sees this as a different app: remove the old toe entry from the
      Accessibility list, then add the new one. One time only — later upgrades keep the grant.

      `toe` is now on your PATH as well: `toe query state` says what is open and where,
      `toe dispatch "workspace 3"` drives it, and `toe help` lists the rest. `toe skill install`
      writes a Claude Code skill so an agent can do the same.

      To start toe at login, see "Start at login" at #{cask.homepage}
    EOS
  end
end
