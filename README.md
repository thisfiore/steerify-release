# Steerify

**You decide. Claude builds.** A native Mac app that keeps a project's steering board (To test, Choices,
Requirements, Roadmap) next to the Claude Code sessions doing the work — across all your projects.

- Native SwiftUI + [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) terminals, no Electron.
- Every board item can start (or resume) its own Claude Code conversation, already briefed.
- The board lives in your repo: a workspace folder with `steerify.json` (see [`docs/FORMAT.md`](docs/FORMAT.md)).
- Ships the `steerify` Claude Code skill ([`skills/steerify`](skills/steerify/SKILL.md)): the standard loop
  read the item → ask choices on the board → deliver to To test → read verdicts → release.

## Build

```sh
scripts/bundle.sh          # → build/Steerify.app (release, signed ad-hoc)
open build/Steerify.app
```

macOS 15+. The landing page design is in `site/` (not deployed yet; domain: steerify.dev).

Independent project, not affiliated with Anthropic. Claude is a trademark of Anthropic.
