cask "steerify" do
  version "0.5.9"
  sha256 "8622bb6f1505040755ca99858bdd331c34cc99a153c885b78df350bfe588ff5b"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
