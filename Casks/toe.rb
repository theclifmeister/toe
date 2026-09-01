# frozen_string_literal: true

cask "toe" do
  # Both lines below are rewritten by .github/workflows/release.yml on each tag.
  version "0.2.0"
  sha256 "ea516cb1dc0534cd39ac939584b6acd6a3ea6f62bae21811d878f650a9d25338"

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

  uninstall launchctl: "com.clifmeister.toe",
            quit:      "com.clifmeister.toe"

  zap trash: [
    "~/.config/toe",
    "~/Library/LaunchAgents/com.clifmeister.toe.plist",
    "~/Library/Saved Application State/com.clifmeister.toe.savedState",
  ]

  # The upgrade paragraph below is for the 0.2.0 → Developer ID switchover only. Drop it a
  # release or two after 0.3.0, once nobody is upgrading across that boundary any more.
  caveats do
    <<~EOS
      Grant toe Accessibility before it can manage windows:
        System Settings → Privacy & Security → Accessibility

      Upgrading from 0.2.0 or earlier? toe is now signed with an Apple Developer ID and
      notarized, where it used to carry a self-signed certificate. macOS keys Accessibility
      to the signature, so it sees this as a different app: remove the old toe entry from the
      Accessibility list, then add the new one. One time only — later upgrades keep the grant.

      To start toe at login, see "Start at login" at #{cask.homepage}
    EOS
  end
end
