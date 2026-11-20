cask "steerify" do
  version "0.5.2"
  sha256 "fdb95b987054732e01173a4e5a8b7d2dd4ef1a7053a17ae8ad306076292cb52e"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
