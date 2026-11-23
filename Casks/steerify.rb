cask "steerify" do
  version "0.5.14"
  sha256 "00ecce966de308249498a58c61992caf40d3f18cba5b9da7798ffe765a921b91"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
