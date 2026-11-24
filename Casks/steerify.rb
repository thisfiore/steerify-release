cask "steerify" do
  version "0.5.21"
  sha256 "4648ba4ecf8346fadef9b4fce9a8b8773065c239011796f0d5932259621d644a"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
