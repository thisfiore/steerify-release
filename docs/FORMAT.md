# The Steerify workspace format (v1)

**Everything about a project lives in the project. The app only remembers which workspaces you opened.**

A *workspace* is one folder, inside a git repo, that holds the project's board. It can be a dedicated repo
(`acme-steering/board`) or a folder inside the main repo (`<repo>/.steerify`). Commit it and the whole project
(roadmap, choices, verdicts, To test, the list of repos) travels with GitHub.

```
<workspace>/
  steerify.json     the manifest: name + every repo of the project      (written by you / Steerify)
  board.json        choices, requirements, roadmap (tracks), facts, links (written by Claude)
  decisions.json    your picks, notes and test verdicts                 (written by the app / web board)
  delivered.json    the To test tab                                     (written by deliver.mjs)
  requests.json     what you asked with + Request (⌘N), where it went   (written by the app + Claude)
  img/              mockups and screenshots (git-ignore it when it holds client assets)
  kit/              prototype kit: the project's tokens, components, sample data + proto.js (see kit/README.md)
  protos/           live prototypes for UI choices (an option's "proto": "protos/<id>.html?v=B")
```

## steerify.json

```json
{
  "steerify": 1,
  "id": "acme",
  "name": "Acme",
  "repos": [
    { "name": "acme-api", "path": "../../acme-api", "git": "git@github.com:you/acme-api.git", "areas": ["api"] },
    { "name": "steer-app",  "path": "../../../steer-app", "areas": ["mac"] }
  ],
  "webBoard": { "port": 8098, "server": "server.mjs" }
}
```

| Field | Meaning |
| --- | --- |
| `steerify` | format version |
| `id`, `name` | project id (used in `steerify://` links and `STEERIFY_PROJECT`) and display name |
| `repos[].path` | path **relative to the workspace folder**, so any clone works on any Mac |
| `repos[].git` | remote URL; when the path is missing, Steerify can clone it there |
| `repos[].areas` | board areas this repo serves; a session for an item in that area starts here |
| `webBoard` | optional: the project's own HTML board server (older setups) |

## On this Mac only (not in the project)

`~/Library/Application Support/Steerify/workspaces.json` — the list of workspace folders you opened.
Window layout and open sessions are app state too. Nothing else.

## Links and sessions

- `steerify://start?project=<id>&item=<kind>:<id>&intent=<fix|release|plan|build|check|look>` opens (or focuses)
  a Claude Code session for that item, in the item's repo, started as `claude '/steerify <intent> <item>'`.
- `steerify://new?project=<id>` opens a fresh session that starts with the guided list (`/steerify`).
- Item kinds: `test:<delivered id>`, `choice:<decision id>`, `road:<slug of the roadmap item>`, `req:<requirement id>`, `track:<slug of a track name>` (a roadmap chapter), `reqs:<slug of a requirements heading>`, `request:<request id>` (a request filed with + Request). Intents: fix, release, plan, build, check, look, resume (chapter: state of the art + next step), intake (a new request).
- Every session gets `STEERIFY_PROJECT`, `STEERIFY_BOARD` (the workspace), `STEERIFY_ITEM`, `STEERIFY_SESSION`.

## The skill

Steerify installs `~/.claude/skills/steerify/SKILL.md` (source: `skills/steerify/SKILL.md`), the standard every
session follows: read the item, ask choices on the board, deliver to To test, read verdicts, release.
A project's own rules go in the workspace repo's `README.md`; the skill tells Claude to follow them.

## Requests (+ Request, ⌘N)

`requests.json` → `items[]`: `{id, at, text, kind: fix|refine|feature|question, chapter, imgs[], context, status, became[], note}`.
Screenshots are copied to `img/requests/<id>-<n>.png`. Fixes and refinements land at once as key results of the
rolling chapter **Fixes & refinements**; such items carry a third element `{req, for, at, area, doneAt}`
(`for` = the feature chapter they belong to; done ones older than a week are shown as archived).
A chapter Claude drafts from a feature request has `"draft": true` (and `request`, `objective`) until you approve it.
