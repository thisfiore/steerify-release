cask "steerify" do
  version "0.5.22"
  sha256 "9424d8356bc192e87e2fb7b26e0f7ca233e02c5b364199c0017d80a72565612d"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
