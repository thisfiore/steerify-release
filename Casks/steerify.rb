cask "steerify" do
  version "0.5.3"
  sha256 "48010987ebdc2158ba5a4ea86af5da947b4dd3403c76860dc17b1a1f4e5c4cd7"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
