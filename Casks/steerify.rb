cask "steerify" do
  version "0.5.4"
  sha256 "d0a21f8c772bd40d12a86ba5ff98d73d635a079671fc13eb683136b368dda8b2"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
