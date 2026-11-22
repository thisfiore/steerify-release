cask "steerify" do
  version "0.5.12"
  sha256 "5545ced16d59d12a136e10824105ee8c9cd0aac98df299cdf26460cfd373c5d7"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
