cask "steerify" do
  version "0.5.11"
  sha256 "4f3eae4d79d653ae0d21519a09377606b06c28cbe9618e228a1d2ae34d2951ca"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
