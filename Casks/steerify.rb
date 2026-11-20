cask "steerify" do
  version "0.5.1"
  sha256 "8fa2c957035dacd38f620d8da5bcc63e1745f9aad88edbf18e26177d1dbc09c6"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
