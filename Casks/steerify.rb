cask "steerify" do
  version "0.5.25"
  sha256 "6e8a345464978ed848b40d6a39af8a9396f083f058e6838e8bdd511aef9659b2"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
