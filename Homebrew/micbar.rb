cask "micbar" do
  version "1.0.0"
  sha256 :no_check

  url "https://github.com/kishisan/MicBar/releases/download/v#{version}/MicBar.app.zip"
  name "MicBar"
  desc "macOS menu bar app that shows microphone usage status"
  homepage "https://github.com/kishisan/MicBar"

  app "MicBar.app"

  zap trash: [
    "~/Library/Preferences/com.kishisan.MicBar.plist",
  ]
end
