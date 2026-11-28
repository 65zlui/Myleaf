cask "myleaf" do
  version "0.3"
  sha256 "cf141ee20ab9bf861af5a1e3a29dcb38cef9bef1cdd5522637015588f8f248ba"

  # Release tags are semver (v0.3.0) while artifacts use MARKETING_VERSION
  # (0.3). Update the tag, version, and sha256 for every release.
  url "https://github.com/65zlui/Myleaf/releases/download/v0.3.0/myleaf-#{version}.dmg"
  name "myleaf"
  desc "Native macOS LaTeX editor with live PDF preview"
  homepage "https://github.com/65zlui/Myleaf"

  depends_on macos: :sonoma

  app "myleaf.app"

  uninstall quit: "com.65zlui.myleaf"

  # myleaf is ad-hoc signed and not notarized. Homebrew quarantines the DMG it
  # downloads, which would make Gatekeeper block the first launch. Strip the
  # quarantine from the installed bundle so `brew install` is a one-step install.
  postflight do
    system_command "/usr/bin/xattr",
                   args:         ["-dr", "com.apple.quarantine", "#{appdir}/myleaf.app"],
                   print_stdout: false,
                   print_stderr: false
  end

  zap trash: [
    "~/Library/Application Scripts/com.65zlui.myleaf",
    "~/Library/Application Support/myleaf",
    "~/Library/Caches/Tectonic",
    "~/Library/Caches/myleaf",
    "~/Library/HTTPStorages/com.65zlui.myleaf",
    "~/Library/Logs/myleaf",
    "~/Library/Preferences/com.65zlui.myleaf.plist",
    "~/Library/Saved Application State/com.65zlui.myleaf.savedState",
  ]
end
