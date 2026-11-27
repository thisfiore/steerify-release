cask "steerify" do
  version "0.5.27"
  sha256 "c27cfe0e0c773a926453d5383accc76fe3fd3c19fa9797eaa7360648f39300b5"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
