cask "steerify" do
  version "0.5.15"
  sha256 "0bb3cc425525c2ad7c23b83293f0a4b02bca66f7bd12600cada80cac2ec0038e"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
