cask "steerify" do
  version "0.5.17"
  sha256 "da622fb66a96ed016bd9bffdef2dbbb1c2023ef416e1499b71258af5945f1c3a"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
