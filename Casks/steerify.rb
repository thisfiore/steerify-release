cask "steerify" do
  version "0.5.28"
  sha256 "45512a38aa1e99ec12a8435ceb2ac1cc131a6bf7d965878b0dda59090c4e2158"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
