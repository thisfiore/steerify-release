cask "steerify" do
  version "0.5.13"
  sha256 "fdb34e968c5f36fe33b2557ed28d41bb3c846682ea834f96691a82b5e0fe6b83"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
