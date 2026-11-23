cask "steerify" do
  version "0.5.19"
  sha256 "84bc4f113f07c8d0921b7e14fa2160175553d1fd7c596b8848b5ee9781da9052"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
