cask "steerify" do
  version "0.5.4"
  sha256 "e949cd8ac67332790b54cdc1855098ec7f55bc5686f7bdfbe70a17341df86602"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
