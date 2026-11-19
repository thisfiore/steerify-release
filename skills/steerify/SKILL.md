---
name: steerify
description: The Steerify standard for a Claude Code session that works on a steered project (board with To test, choices, requirements, roadmap). Use at the start of every session opened by Steerify (STEERIFY_PROJECT is set), when the user types /steerify, or when the session must pick up a test, a choice, a roadmap item or a requirement, deliver work to To test, ask the user a choice, or release.
---

# Steerify

You are working inside **Steerify**: a Mac app that keeps a project's steering board next to the Claude Code
sessions doing the work. The board is the shared memory between you and the user. Questions, proposals and
results go **on the board**; the chat only says what happened and where.

## Where things are

Steerify sets these in the session's environment (read them with `echo $STEERIFY_BOARD` etc.):

| Variable | Meaning |
| --- | --- |
| `STEERIFY_PROJECT` | project id (e.g. `sb`, `blink`) |
| `STEERIFY_BOARD` | the board folder |
| `STEERIFY_ITEM` | the item this session was started from, if any (`test:<id>`, `choice:<id>`, `road:<slug>`, `req:<id>`) |
| `STEERIFY_SESSION` | this session's id |

Board folder files (plain JSON, never reformat them; keep their indentation; stage only your own changes):

- `board.json` — written by Claude: `decisions` (choices), `requirements`, `tracks` (roadmap), `facts`, `links`.
  Older boards may use other keys (e.g. `product`, `ship`): read what is there, don't migrate silently.
- `decisions.json` — written by the user's clicks (a choice answer may carry `mix`: other option ids to blend into the
  pick, with the note saying how; build the combination, not just the pick): `choices[<decisionId>] = {pick, note}`,
  `choices["ship:<id>"] = {pick: ok|refine|broken, note, tests:{<n>:{note|ok}}}`, `"req:<id>"` verdicts.
- **Notes pinned on pictures:** `choices[<key>].pins = [{img, x, y, note, v}]` (key = `ship:<id>` for a To test item,
  the decision id for a choice). `img` is relative to the board folder, `x`/`y` are 0–1 from the top-left. Open the
  image, look at that spot, and treat every pin as a required change; say per pin what you did.
- `sessions.json` — which Claude Code conversation belongs to which item (written by Steerify; don't edit).
- `delivered.json` — the **To test** tab. Only change it through `node $STEERIFY_BOARD/deliver.mjs '<json>'`.
- `README.md` in the board's repo, if present, has the project's own rules (test data, areas, deploy). **Follow it**;
  it wins over the generic steps below.

## The Steerify MCP (use it when it is there)

Sessions started by Steerify have an MCP server named **steerify**. Prefer its tools over editing board files:
`board_summary`, `get_item` (verdict, notes, pinned picture notes), `deliver` (To test), `ask_choice`,
`set_roadmap_status`, `set_release_config`, `add_roadmap_item`, `add_chapter`, `update_request`, and `notify` (a toast in the user's Steerify window, with a jump to the
item). The app updates at once. After delivering or adding a choice, `notify` the user in one short line.
Without the MCP (a plain terminal), edit the files as described below.

## Arguments

`/steerify [intent] [item]` — e.g. `/steerify fix test:retouch-ops-1-4`, `/steerify plan road:session-status`.
No arguments **and** no `STEERIFY_ITEM` → **Guided start** below.

**A session started from an item never asks what to work on.** If an item is given (argument or `STEERIFY_ITEM`),
go straight to it. The item's conversation is resumed on later starts (Steerify records the link in
`$STEERIFY_BOARD/sessions.json`), so read the new instruction against what you already did.

| Intent | On | Do |
| --- | --- | --- |
| `fix` | test | Read the item and every note (overall + per test). Fix, test it yourself, re-deliver with the **same id**. |
| `release` | test | Only when the verdict is `ok`: land the work as the project's **flow** says (below: commit + push on main, merge the feature branch, or merge the PR), deploy as the README says, re-deliver with `"status":"live","keepVerdict":true`. |
| `plan` | road | Read the code that the item touches; write what exists, what is missing, the steps. Mark the item `wip`. If a decision is needed, add a choice; otherwise start building. |
| `build` | road / choice | Build it (for a choice: the user's pick + note). Test, deliver (`choices: [<id>]` for a choice), mark the track item `review`. |
| `check` | req | Check whether the code meets the requirement; report on the board (track note or To test item). |
| `look` | any | Read only: summarise the item and its state in the chat, change nothing. |
| `ship` | release | Release everything ready in the project: To test items with verdict `ok` not yet `live` (+ branches ahead). Follow `release` in `steerify.json` (per repo: branch, deploy, notes) and the README. Per repo: land approved feature branches / PRs first (flow below), commit only your own hunks, push, deploy, check it is live; then re-deliver each item with `"status":"live","keepVerdict":true` and write release notes where the project keeps them. Stop and ask on the board if something is not clean. |
| `plan` | release | No release setup yet: read each repo (deploy scripts, CI, README, package.json) and write `release` into `steerify.json` (`{"repos":{"<repo>":{"branch":"main","deploy":"…"}},"notes":"…"}`), then tell the user to check it in the Release tab. |
| `choose` | req (question) | Turn the question into a choice: read the code and context, then `ask_choice` with 2–4 concrete options, one suggested, a visual mock each. Link it in the choice's `why` ("from requirement <id>"). Mark the requirement `proposed` only after the user picks (they answer on the Choices tab). |
| `consolidate` | reqs | For each open requirement of the chapter: check the code. Built and verified → `set_requirement_status built` with one line of evidence (file / commit). Not built but agreed in spirit → add a roadmap item. Questions → a choice (`ask_choice`). Never record the user's verdict for them. Report a table. |
| `consolidate` | track | Bring a chapter's statuses up to date, nothing else. For every key result not `done`: look for evidence (To test verdicts, commits in the chapter's repos — `git log --since=<chapter start> --oneline`, the code itself, deploys.json / live versions). Mark `done` only with evidence, `review` if delivered but not approved, `wip` if partly there, leave it otherwise. Use `set_roadmap_status` (MCP). Report a short table: item · old → new · evidence. Don't build anything. |
| `resume` | track / reqs | A whole chapter (`track:<slug>` = a roadmap track, `reqs:<slug>` = a requirements group). **State of the art:** read every item of the chapter, its linked choices, To test items and requirements, then check the code to see what really exists (not what the board claims). Report done / partly done / missing in a few lines, fix wrong statuses on the board, name the **next step** and start it (mark it `wip`), unless it needs a choice from the user: then add the choice and do what is ready. |
| `intake` | request | A new request the user filed with **+ Request** (⌘N). The brief has the text, screenshots, kind, chapter. Never ask what it is; open every screenshot. **Fix / refinement:** it is already a key result in "Fixes & refinements" (linked to its chapter): mark it `wip`, check the code, fix it, test, deliver (`road` = that key result), mark it `review`. **Feature:** read the code, then `add_chapter` (a draft: objective, 3–7 key results, requirements; the user approves it in Steerify) and put open questions on the board with `ask_choice`; build nothing until it is approved. **Question:** answer it from the code as a choice (`ask_choice`, 2–4 options with mocks). The kind is wrong? Say so and treat it as the right one. Always finish with `update_request` (status, became[], one-line note). |

## Branches and releases (the project's flow)

`release.flow` in `steerify.json` (also `$STEERIFY_FLOW`) says how sessions use git. The user picks it in the
Release tab; projects that don't say use the Settings default (`main`).

| Flow | While building | On the user's OK (`release`) |
| --- | --- | --- |
| `main` | Work in the repo's checkout, on the release branch. Other sessions share it: commit **only your own hunks**, build before every commit, push. | Already on main: push, deploy. |
| `worktree` | Steerify starts code work (`build`, `fix`, `plan`) in the feature's own folder `$STEERIFY_WORKTREE`, branch `$STEERIFY_BRANCH` (`steer/<feature>`). Commit there freely; don't push to the release branch; build and test from this folder. | In the feature folder: `git rebase $STEERIFY_RELEASE_BRANCH`, build, test. Then in `$STEERIFY_REPO_MAIN`: `git merge --ff-only <branch>`, push, deploy; `git worktree remove` the folder and delete the branch. |
| `pr` | As `worktree`, and when you deliver: `git push -u origin <branch>`, `gh pr create` (title = the item, body = the delivery's `what`), put the PR link in the delivery's `tests[]`. | `gh pr merge --squash --delete-branch`, pull in `$STEERIFY_REPO_MAIN`, deploy; remove the folder. |

- **The board is never in the branch.** Read and write it at `$STEERIFY_BOARD` (main checkout), never the `.steerify`
  copy inside a feature folder. `deliver.mjs` commits the board on main by itself.
- One feature = one folder: a fix on a delivered feature reopens the same folder (Steerify resumes it there).
- Conflicts on rebase / merge you can't resolve with certainty: stop and ask on the board (`ask_choice`).
- `ship` lands every approved branch / PR first, oldest first, then releases as usual. If the project versions its
  builds (README / release notes), bump the version and tag `vX.Y` when shipping.

## Guided start (no item)

1. Read `decisions.json`, `delivered.json`, `board.json`.
2. Offer a short numbered list, in this order, max 6 lines, each with why:
   1. To test items with `refine` or `broken` (newest note first)
   2. Choices the user answered that are not built yet
   3. The next `todo`/`wip` roadmap item in the current track
   4. "Something else (tell me)"
3. Wait for the number, then run the matching intent.

## The loop (every item)

1. **Read** the item, its notes, its pinned picture notes and linked requirements before touching code.
2. **Need a decision?** Add a choice to `board.json → decisions` (2–4 options, exactly one `rec: true`, a visual
   mockup per option, short labels) and keep building what does not depend on it.
   **UI choices get a live prototype** in the project's design system: `protos/<choice id>.html` with a section per
   option (+ `today`), each option's `"proto": "protos/<choice id>.html?v=A"`. It uses the board's `kit/`
   (tokens, components, sample data); no kit yet → build it first (`~/.claude/skills/steerify/kit/README.md`).
3. **Build and test it yourself** (the project's real tests, the real UI for anything visible).
4. **Deliver** with `deliver.mjs`: honest `tested[]`, one direct link per test, screenshots taken after testing,
   known `issues[]`. Same id = new version of the same item. **Every picture full size** (≥1400 px wide, shots and
   per-test `img` alike, never pre-shrunk thumbnails): Steerify shows them big and makes its own thumbnails.
   **Focused on the feature:** each test picture shows the thing under test, never the whole window: crop it to the
   feature at 2× (a Retina capture of that region), or add `"focus": [x, y, w, h]` (0–1 from the top-left) on the test
   or shot. The card shows one row per test (picture 65% wide, fixed height), so a whole window is unreadable there.
   **`what` is 2–4 bullets, ≤ 6 words each**, one per line (`"- Export button on Orders\n- Uses your filters"`):
   what changed for the user, not how; no prose, nothing the user has to study. Details go in `tested[]`.
   **Link it to the roadmap:** set `road` to the exact text of the roadmap item(s) this delivery completes, so
   Steerify can mark them done when the user says OK (no consolidation needed later). Built a choice? Set
   `choices: ["<decision id>"]` too, so the choice shows "Built" instead of "Build my pick".
   Meets requirements? Set `reqs: ["<requirement id>", …]`: the user's OK marks them built (with the delivery as
   evidence). Requirements of an approved chapter are already agreed; never ask the user to confirm them again.
   **Tests are visual and schematic:** every test has a picture of exactly what to look at; `label` ≤ 6 words
   (what to do), `check` ≤ 12 words (what you should see), no explanations; details go in `tested[]`.
5. **Mark** the roadmap item (`wip` → `review` → `done` after the user's ok).
6. **Tell** the chat in 2–4 lines: delivered card, what is now `wip`, which choices were added.

## Rules

- Never claim something works without having run it.
- Never edit `decisions.json` except to record a pick the user gave in the chat.
- A choice is built only when a delivery names it (`choices: [id]`). Never set `built` on a choice by hand: it hides
  the user's pick from Ready to build. A picked choice that is not built yet gets a roadmap key result.
- Choices asked while working on a request or item carry `from` (ask_choice sets it); choices of one origin are built
  together, in one session.
- Other sessions edit the same board: pull before writing, write only your items, commit only your own changes.
- Labels the user sees are short and plain; one idea per line.
