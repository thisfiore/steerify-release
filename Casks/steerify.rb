cask "steerify" do
  version "0.5.23"
  sha256 "0bd0290c192ac88d5c4453c3b57d63f40bed2d1ada26fd895aa43994e483c206"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
