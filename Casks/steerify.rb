cask "steerify" do
  version "0.5.7"
  sha256 "7abd8c2748bc426d4f99dea9a0b25bdec80918baa52e0710e0b6907d072bf1fe"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
