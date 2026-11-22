cask "steerify" do
  version "0.5.10"
  sha256 "c4e9654793b16b461f8f0ec55445e4f3c69327fe738375797ed164600104c6bd"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
