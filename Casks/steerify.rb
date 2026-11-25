cask "steerify" do
  version "0.5.24"
  sha256 "658145bbc81b83aab89682db6fdb1176486b84487aa2491b6c72ae89557818a4"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
