cask "steerify" do
  version "0.5.5"
  sha256 "37035177d61f9c6d9fe65b2c8124d9b33e029c9d2b222a822e78cd03848745f0"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
