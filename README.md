<p align="center">
  <img src="site/assets/icons/icon-256.png" width="96" height="96" alt="Steerify">
</p>
<h1 align="center">Steerify</h1>
<p align="center"><b>You decide. Claude builds.</b><br>
A native Mac app for steering <a href="https://claude.com/claude-code">Claude Code</a> across your projects.</p>

<p align="center">
  <a href="https://github.com/thisfiore/steerify-release/releases"><img alt="Latest release" src="https://img.shields.io/github/v/release/thisfiore/steerify-release?include_prereleases&label=release&color=ffb020"></a>
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-f2e8cf"></a>
  <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-8fb0ff">
  <a href="https://github.com/thisfiore/steerify-release/stargazers"><img alt="GitHub stars" src="https://img.shields.io/github/stars/thisfiore/steerify-release?color=4ade80"></a>
</p>

<p align="center">
  <a href="https://github.com/thisfiore/steerify-release/releases"><b>Download for Mac</b></a> ·
  <a href="https://steerify.dev">steerify.dev</a> ·
  <a href="https://github.com/thisfiore/steerify-release/issues/new?template=bug.yml">Report a bug</a> ·
  <a href="https://github.com/thisfiore/steerify-release/issues/new?template=feature.yml">Suggest a feature</a>
</p>

<p align="center"><img src="docs/img/hero.gif" width="820" alt="The loop: you say, you pick, Claude builds, you look, shipped"></p>

## The problem

Nine Claude sessions open. Fine, nineteen. Okay, ninety-nine. Three of them are waiting on you. Guess which.

<p align="center"><img src="docs/img/problem.gif" width="820" alt="A wall of terminals grows from 9 to 99; three of them turn amber"></p>

Steerify puts every session on a roadmap item and shows you the ones that need you.

## Deciding is the whole job

Claude never builds on a guess. It asks on the board first, one picture per option, and you answer in seconds:
pick one, blend two with a note, write your own, or park it. Your answers start the build.

<p align="center"><img src="docs/img/decide.gif" width="820" alt="A choice with three mockups: pick B, blend in A, add a note, done, build"></p>

## How it works

<table>
  <tr>
    <td width="50%"><img src="docs/img/build.gif" alt="Roadmap items each start a briefed session"><br><b>Build the right thing.</b> Each answer starts a Claude session, already briefed, in the right repo.</td>
    <td width="50%"><img src="docs/img/sync.gif" alt="Sessions deliver and their items move to To test"><br><b>Always in sync.</b> Every session sits on its roadmap item. The status moves on its own.</td>
  </tr>
  <tr>
    <td><img src="docs/img/filter.gif" alt="Nine sessions filtered down to the three waiting on you"><br><b>Only what needs you.</b> Many sessions running, a few waiting on you. You see those.</td>
    <td><img src="docs/img/standard.gif" alt="Three deliveries checked against the same design and tests"><br><b>One standard.</b> Finished work arrives as pictures, checked against the same design and tests. Pin a note where it is wrong.</td>
  </tr>
</table>

And this is the real thing, on Steerify's own board:

<p align="center"><img src="site/assets/shots/hero-now.jpg" width="820" alt="Steerify: a choice with three visual options next to the session panel"></p>

## Install

1. [Download the latest build](https://github.com/thisfiore/steerify-release/releases), open the DMG and drag Steerify to Applications.
2. Open it and add a project: pick any folder. Steerify creates a `.steerify/` board inside it.
3. Start an item. It opens a Claude Code session in the right repo, already briefed.

Or with Homebrew:

```sh
brew tap thisfiore/steerify https://github.com/thisfiore/steerify-release
brew trust thisfiore/steerify   # Homebrew 7+ asks you to trust third-party taps
brew install --cask steerify
```

You need macOS 15 or later and [Claude Code](https://claude.com/claude-code) with your own login. Mac only.

Early builds are not notarized by Apple yet: the first time, open the app from System Settings → Privacy & Security → Open Anyway.

## Under the hood

- **Native.** SwiftUI and [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) terminals. No Electron.
- **Your board lives in your repo.** Plain JSON files in a workspace folder, described in [`docs/FORMAT.md`](docs/FORMAT.md). Delete Steerify and it is all still yours.
- **A Claude Code skill does the talking.** Steerify installs [`skills/steerify`](skills/steerify/SKILL.md), the loop every session follows: read the item, ask choices on the board, deliver to To test, read verdicts, release.
- **Three ways to use git,** per project: on main, a worktree per feature, or a branch with a pull request that your OK merges.
- **The small jobs stay on your Mac.** Session summaries, request sorting and screenshot checks use Apple Intelligence on-device, when it is turned on. Claude Code still does the building.

<p align="center"><img src="docs/img/flows.gif" width="820" alt="On main, worktree per feature, or branch plus pull request"></p>

## Build from source

```sh
scripts/bundle.sh          # → build/Steerify.app
open build/Steerify.app
```

The landing page ([steerify.dev](https://steerify.dev)) is in `site/`. The pictures in this README are rendered from it with `node scripts/readme-art.mjs`.

## Feedback

Found a bug or want something? [Open an issue](https://github.com/thisfiore/steerify-release/issues/new/choose): there is a short form for each. To contribute code, read [CONTRIBUTING.md](CONTRIBUTING.md).

## License and name

Code is [MIT](LICENSE). The Steerify name and logo are not covered by that license — see [TRADEMARK.md](TRADEMARK.md).

Independent project, not affiliated with Anthropic or Apple. Claude is a trademark of Anthropic; Apple Intelligence is a trademark of Apple.
