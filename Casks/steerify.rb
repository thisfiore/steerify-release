cask "steerify" do
  version "0.5.6"
  sha256 "62ccd71027b91ad93b726a40377f816285dbe6f860f045b2d6850111585dd2c6"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
