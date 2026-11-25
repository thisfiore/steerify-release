cask "steerify" do
  version "0.5.26"
  sha256 "981e9159c968fb4729294fcdbfc3ed6dcd3766f6dded55355aa7bca4049bdb9c"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
