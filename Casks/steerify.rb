cask "steerify" do
  version "0.5.8"
  sha256 "8f1ad62cf9a964dd10ffda18a14984a465fdaf2f733072de8a84441280444a19"

  url "https://github.com/thisfiore/steerify-release/releases/download/v#{version}/Steerify-#{version}.dmg"
  name "Steerify"
  desc "Steering board for Claude Code sessions"
  homepage "https://steerify.dev/"

  depends_on macos: ">= :sequoia"

  app "Steerify.app"

  zap trash: "~/Library/Application Support/Steerify"
end
