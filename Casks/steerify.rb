cask "steerify" do
  version "0.5.18"
  sha256 "5c82f1af78cea4f13cb4539c8fe6b925701c2dbd6a489dd41d49b8948da82044"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
