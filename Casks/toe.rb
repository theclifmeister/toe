# frozen_string_literal: true

cask "toe" do
  # Both lines below are rewritten by .github/workflows/release.yml on each tag.
  version "0.2.0"
  sha256 "ea516cb1dc0534cd39ac939584b6acd6a3ea6f62bae21811d878f650a9d25338"

  url "https://github.com/theclifmeister/toe/releases/download/v#{version}/toe-#{version}-arm64.zip"
  name "toe"
  desc "Omarchy-style dwindle window manager"
  homepage "https://github.com/theclifmeister/toe"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma
  depends_on arch: :arm64

  app "Toe.app"

  uninstall launchctl: "com.clifmeister.toe",
            quit:      "com.clifmeister.toe"

  zap trash: [
    "~/.config/toe",
    "~/Library/LaunchAgents/com.clifmeister.toe.plist",
    "~/Library/Saved Application State/com.clifmeister.toe.savedState",
  ]

  caveats do
    <<~EOS
      Grant toe Accessibility before it can manage windows:
        System Settings → Privacy & Security → Accessibility

      toe is signed, but with a self-signed certificate rather than an Apple Developer ID, so
      it is not notarized. Homebrew no longer quarantines cask downloads, so this is usually
      invisible. If macOS refuses to open the app, clear the quarantine attribute by hand:
        xattr -dr com.apple.quarantine /Applications/Toe.app

      To start toe at login, see "Start at login" at #{cask.homepage}
    EOS
  end
end
