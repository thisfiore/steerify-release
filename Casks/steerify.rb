cask "steerify" do
  version "0.5.16"
  sha256 "e512e31336b07d914de52d511a9aacadf1f2d1a305d4bdddc1c291a4f17c2188"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
