cask "steerify" do
  version "0.5.20"
  sha256 "159920b391788675d16ae0df3a0973ecf9f9d67a4ae4e507acc5764003fc43b1"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
