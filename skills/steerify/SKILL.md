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
| `STEERIFY_ITEM` | the item this session was started from, if any (`test:<id>`, `choice:<id>`, `road:<slug>`, `req:<id>`, `task:<id>`) |
| `STEERIFY_SESSION` | this session's id |
| `STEERIFY_ENVS` | where this project is tested (`steerify.json → environments`): the only hosts for To test links |

Board folder files (plain JSON, never reformat them; keep their indentation; stage only your own changes):

- `board.json` — written by Claude: `decisions` (choices), `requirements`, `tracks` (roadmap), `facts`, `links`.
  Older boards may use other keys (e.g. `product`, `ship`): read what is there, don't migrate silently.
- `decisions.json` — written by the user's clicks (a choice answer may carry `mix`: other option ids to blend into the
  pick, with the note saying how; build the combination, not just the pick): `choices[<decisionId>] = {pick, note}`,
  `choices["ship:<id>"] = {pick: ok|refine|broken, note, tests:{<n>:{note|ok}}}`, `"req:<id>"` verdicts.
- **Notes pinned on pictures:** `choices[<key>].pins = [{img, x, y, note, v}]` (key = `ship:<id>` for a To test item,
  the decision id for a choice). `img` is relative to the board folder, `x`/`y` are 0–1 from the top-left. Open the
  image, look at that spot, and treat every pin as a required change; say per pin what you did.
- **Every note counts, whatever the verdict:** `get_item test:<id>` → `user_notes` (card note, per-test notes / To refine marks, pins).
  `ok` + notes = apply them (small changes), test, then release; a bigger note → re-deliver. Say per note what you did.
- `sessions.json` — which Claude Code conversation belongs to which item (written by Steerify; don't edit) except to map
  the `past:<id>` links at setup, see **First setup**).
- `delivered.json` — the **To test** tab. Only change it through `node $STEERIFY_BOARD/deliver.mjs '<json>'`.
- `README.md` in the board's repo, if present, has the project's own rules (test data, areas, deploy). **Follow it**;
  it wins over the generic steps below.

## The Steerify MCP (use it when it is there)

Sessions started by Steerify have an MCP server named **steerify**. Prefer its tools over editing board files:
`board_summary`, `get_item` (verdict, notes, pinned picture notes), `deliver` (To test), `ask_choice`,
`set_roadmap_status`, `set_roadmap_kind`, `set_release_config`, `set_environments`, `add_roadmap_item`, `add_chapter`, `add_task`, `finish_task`, `update_request`, and `notify` (a toast in the user's Steerify window, with a jump to the
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
| `choose` | req (question) | Turn the question into a choice: read the code and context, then `ask_choice` with 2–4 concrete options, one suggested, each showing its result (prototype or example pictures, see the loop). Link it in the choice's `why` ("from requirement <id>"). Mark the requirement `proposed` only after the user picks (they answer on the Choices tab). |
| `consolidate` | reqs | For each open requirement of the chapter: check the code. Built and verified → `set_requirement_status built` with one line of evidence (file / commit). Not built but agreed in spirit → add a roadmap item. Questions → a choice (`ask_choice`). Never record the user's verdict for them. Report a table. |
| `consolidate` | track | Bring a chapter's statuses up to date, nothing else. For every key result not `done`: look for evidence (To test verdicts, commits in the chapter's repos — `git log --since=<chapter start> --oneline`, the code itself, deploys.json / live versions). Mark `done` only with evidence, `review` if delivered but not approved, `wip` if partly there, leave it otherwise. Use `set_roadmap_status` (MCP). Report a short table: item · old → new · evidence. Don't build anything. |
| `tag` | track | Core vs extras for a chapter that has none yet. Read its objective and every key result; for each one `set_roadmap_kind` with `proposed: true`: `core` only if the objective is not met without it, else `test` / `tutorial` / `enhancement` / `later`. Change nothing else. The user keeps or undoes the proposal on the chapter. Report a short table: item · kind · why (≤ 6 words). |
| `resume` | track / reqs | A whole chapter (`track:<slug>` = a roadmap track, `reqs:<slug>` = a requirements group). **State of the art:** read every item of the chapter, its linked choices, To test items and requirements, then check the code to see what really exists (not what the board claims). Report done / partly done / missing in a few lines, fix wrong statuses on the board, name the **next step** and start it (mark it `wip`), unless it needs a choice from the user: then add the choice and do what is ready. |
| `intake` | request | A new request the user filed with **+ Request** (⌘N). The brief has the text, screenshots, kind, chapter. Never ask what it is; open every screenshot. **Fix / refinement:** it is already a key result in "Fixes & refinements" (linked to its chapter): mark it `wip`, check the code, fix it, test, deliver (`road` = that key result), mark it `review`. **Feature:** read the code, then `add_chapter` (a draft: objective, 3–7 key results, requirements; the user approves it in Steerify; tag each key result's `kind`, see **Core and extras**) and put open questions on the board with `ask_choice`; build nothing until it is approved. **Task** (doing, not building: a tutorial from the SOP, a data collection, a report, anything on a schedule): never a chapter. Read the standard / tools it names, then `add_task` (concrete `outcome`, 2–5 `checks`, `sop`, `every` if it repeats, `request` = the request id, `runNow: true` for a one-off or a first run) and do it as `run` below; a repeating task's later runs are started by Steerify. **Question:** answer it from the code as a choice (`ask_choice`, 2–4 options, each showing its result). The kind is wrong? Say so, treat it as the right one and pass `kind` to `update_request` (Steerify learns from every correction). Always finish with `update_request` (status, became[], one-line note). |
| `run` | task | One run of a task (Tasks tab; the brief has the run id, outcome, checks, the standard to follow, a Redo note if the user sent the last result back). Do the work with the project's tools, not code changes (a needed code change → `add_roadmap_item`, then carry on). Check the result against **every** check yourself. Finish with `finish_task` (run id, `summary`, `files` to open it, `counts`, `checks: [{text, ok}]` honestly, and the `report`, see **Task report**); can't reach the outcome → `finish_task` with `failed: true` and why. Without `finish_task` the run shows "No result" when its time is up. Never deliver a task to To test. |
| `init` | setup | A new project (`setup:<project>`), started from its welcome screen: the board is empty. Follow **First setup** below: read and run the project, show what you understood, ask with choices (never a wall of questions in the chat), then draft the first chapter. Write only in the board folder; everything is a draft for the user to approve. |

## Task report (every task run)

Steerify draws the result of a run from `finish_task` → `report`, the same way for every task and every week, so the
user sees what was done and what came out without reading. **Minimal text**: numbers and short labels; prose only in
the file under Details.

| Field | What | Limit |
| --- | --- | --- |
| `headline` | what you got | ≤ 10 words |
| `kpis` | `[{value, label}]` the big numbers of the outcome | 2–4 |
| `steps` | `[{text, n, done}]` what was done, in order; `n` = its count ("244 · 60 d"); `done: false` = still pending | 3–6, text 2–3 words |
| `rows` | `{title, ref, items: [{name, value, ref, show, tag}]}` one bar per item (brand, page, platform…), `ref` = the comparison mark (avg, last week, target), `show` = the value as text ("56 · 0.6×"), `tag` = the verdict | tag 2–3 words |
| `points` | what matters, what to do next | ≤ 3, ≤ 8 words each |
| `details` | the full file (markdown / PDF / link), kept folded | optional, default `files[0]` |

The detailed file stays syntactic too: a table first, then one short bullet block per item; no paragraphs.

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

## First setup (`init`)

The user's first contact with Steerify: show you understood the project and ask **with the board**, not like a
normal chat. Short chat lines; questions and proposals are choices with pictures.

1. **Read** the project: README, code layout, package files, `git log --oneline -30`, briefs / docs / backlog.
   Find what it is, its parts (→ areas), how it ships, what is in flight, dates and deadlines. Empty folder: skip to 3.
   **Past conversations:** links in `sessions.json` with `"item": "past:<id>"` are this folder's earlier Claude Code
   chats, linked by Steerify when setup started (title = the first thing asked; transcript in
   `~/.claude/projects/*/<id>.jsonl`). Read them: they tell you what is in flight. Say in the snapshot what they were
   about. Once a choice or key result exists that one continues, map it exactly: append a link with the same
   `claudeSession`, `"item"` = that board ref (`road:<slug>`, `choice:<id>`, `track:<slug>`), `"by": "init"`, keeping the
   file's format. The user can then resume it from that item.
2. **Run it** when you can do it safely in a few minutes (dev server, simulator, `swift run`, the built app; never
   deploy, never touch production data). Take 1–3 full-size screenshots into `img/setup/` in the board folder.
   Can't run it (needs secrets, devices, long builds)? Say why in one line and use what exists (README images, store
   pictures) or none.
   **Where it is tested:** find each part's real addresses (deploy config, env files, README: live URL, local dev
   port) and put them in the snapshot (`<b>Test at</b> …`). An address you could not find for sure is an option
   "Tell me in the note". Save them with `set_environments` once confirmed.
3. **Snapshot = choice `setup-understood`** ("Did I get <project> right?"), via `ask_choice`:
   `gallery` = the screenshots (caption: what it shows, "running in the simulator"); `why` = the snapshot, one fact
   per line (`<b>Product</b> …<br><b>Areas</b> …<br><b>State</b> …<br><b>Dates</b> …<br><b>Ships</b> …`);
   options `right` "Yes, that's it" (`rec`) and `fix` "Fix something" (point: "say what in the note"), each with
   `simple: true` and a tiny `mock` (a big ✓ / ✎ and one line); the snapshot itself is already above them.
4. **Questions = choices** (1–3 at a time, the ones that change the first chapter most): what chapter 1 is for, who
   uses it today, what to leave out. 2–4 options each from what you found (real names, real dates), one `rec`, and a
   `mock` per option showing **what the roadmap would look like** with it (chapter name + 3–4 key results as rows).
   These roadmap choices set `simple: true`. Facts you can't guess (a number, a URL) go in the same choice as an option "Tell me in the note".
5. **Chat:** at most 4 lines: what you read, that it runs (or why not), "N to answer on the board". `notify` once.
   If the user answers in the chat instead, that is fine: record nothing in `decisions.json` for them, just go on.
6. When the answers are in (read them with `get_item`; check again whenever the user comes back to the session):
   `goal` and `areas` in `board.json` (one area per part, mapped to its repo), `add_chapter` for the first chapter
   (objective, 3–7 key results, requirements), a follow-up choice only if something is still open. Never mark
   anything agreed or done. The welcome screen goes away as soon as the first choice lands; the board takes over.

**Recipe setup** (the project has `recipe.json` at the top: it was started from a recipe, e.g. a build of the book
AI Traction; the session brief carries the recipe's first message). The reader is **not technical**:
- Their first request is the recipe's `firstMessage`, not "map the codebase". Skip step 2 (nothing to run); read
  `recipe.json`, `START-HERE.md` and every file the reader filled. The skills it names are in `.claude/skills`.
- The snapshot (`setup-understood`) is what you understood **from their files** + what is missing from them.
- Then follow the message's own order (interview one question at a time, smallest test by hand, estimate, roadmap),
  every question as a choice with pictures (`simple: true` where nothing is visual), plain words, no git / branch /
  MCP wording. First runs on invented material. Draft the first chapter from the recipe's build, never build before
  the reader says the sample pieces are good.

## Core and extras (every key result)

A chapter's progress is its **core**: the key results without which the objective is not met. Everything else is an
**extra** that never holds the chapter back: `test` (a test project, a study), `tutorial` (tutorials, videos, docs),
`enhancement` (polish, edge cases, nice follow-ups), `later` (an idea, not promised). When all core key results are
done, Steerify shows the chapter as **Core released**. Tag every key result you add: `add_chapter` items as
`{text, kind}`, `add_roadmap_item` with `kind`; fix a wrong one with `set_roadmap_kind` (on an existing chapter: `proposed: true`, the user keeps or undoes it). Untagged items are guessed
from their first words ("Later: …", "Tutorial …"). Keep the core small and honest (usually 2–5 per chapter).

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
   **Show the result, never a diagram.** Each option shows what the user would *see* after picking it, so they can
   compare by looking, not by reading. A box with words in it (`<div class="dia"><div class="box">…`) is not a mockup.
   - **Screens, panels, flows** → a live prototype in the project's design system: `protos/<choice id>.html` with a
     section per option (+ `today`), each option's `"proto": "protos/<choice id>.html?v=A"`. It uses the board's
     `kit/` (tokens, components, sample data); no kit yet → build it first (`~/.claude/skills/steerify/kit/README.md`).
   - **What a tool does to an output** (an image, a video, a PDF, an export, a message) → a real example per option:
     the same input (`today`) and what each option makes of it, as pictures (`"shot": "img/choices/<id>-A.png"`, or a
     `proto` section with the images in the tool's real screen). Use the project's test data; produce the result for
     real when it is cheap, otherwise composite it faithfully (PIL / canvas) and say so in the caption.
   - **How something works** (a flow, a pipeline, who does what, where data goes) → a logical scheme: the parts as
     boxes joined by arrows, short labels. For a screen when a full prototype is too much, a high-level mockup (a
     laid-out wireframe in `mock`: the regions, the controls, short labels) is fine.
   - **Only scope, naming, order or yes/no** has nothing to look at: then `simple: true` on the choice and a small
     `mock` (rows, a ✓). If you hesitate, it is visual.
   `ask_choice` refuses a mock that is only words in a box on a choice that is not `simple`.
3. **Build and test it yourself** (the project's real tests, the real UI for anything visible).
4. **Deliver** with `deliver.mjs`: honest `tested[]`, one direct link per test (the exact page / record / item under test, opened on the state to check: never a home page, a bare `steerify://` or a repo front page; `deliver` refuses those and 404s), screenshots taken after testing,
   known `issues[]`. **Say what kind of test it is** with `kind` (Steerify shows it on the card, with what the OK does): `design` (a
   mockup / prototype to approve: OK = build it, nothing to release), `local` (on the user's Mac or a local server: OK =
   it goes in the release), `stage` / `prod` (only testable once released: the card waits in "After release", rides the
   next release untested, and comes back to To test when live). Not set → guessed from the links (protos/ → design, a
   real host → stage / prod, else local).
   Same id = new version of the same item. **Every picture full size** (≥1400 px wide, shots and
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
   **Links only to the project's environments** (`STEERIFY_ENVS`, `steerify.json → environments`): never guess a
   host from the product name. `deliver` refuses a link to one of the project's hosts that is not listed. No
   environments yet → find them in the deploy config, or ask the user (`ask_choice`), then `set_environments`.
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
- **Woken by a deploy** ("Steerify just deployed <repo>…"): the user pressed Deploy on the Release tab. Check it is live, run the checks you named, re-deliver approved items with `"status":"live","keepVerdict":true`, mark the roadmap and `update_request`; items not approved yet stay in To test.
- End every turn so Steerify can tell whether the session is done (it reads your last words): what waits on the user
  goes on the board (To test, a choice, the release) and you name it; a step you would take next is one last line
  `Next step: …`; a question only the chat can answer ends with `?`. Nothing open → say it is done, no question.
- Labels the user sees are short and plain; one idea per line.
