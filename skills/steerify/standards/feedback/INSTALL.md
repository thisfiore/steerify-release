# Install the Feedback standard

Goal: the project's own users (people and agents) can ask for a feature, report a bug or ask a question with no
account; it lands on this board as a Request (Ready › New requests), and the reporter follows it to Live.

Work in this order. Each step: check what is already there first, never do a step twice.

## 1. Inbox
`feedback_setup {title}` (Steerify MCP). It registers the inbox on the relay, keeps the secret in the Keychain and
writes `steerify.json → feedback`. Title = the product name people know. Already set up → it says so and returns the links.

## 2. Brand
Find the product's look in the code: logo file (svg / png in public/, assets/), background, text and accent colours,
fonts (CSS variables, Tailwind config, theme file). Then `feedback_setup {brand: {name, logo, home, bg, card, card2,
line, ink, mute, accent, accentInk, font, heading}}`. `logo` is a path relative to the board folder (copy the file into
`img/brand/` first) or an https URL. Only real values from the code; skip what you cannot find.

## 3. Widget (web apps only)
Add the snippet `feedback_setup` returned to the app's main layout, once, for signed-in pages:
```html
<script src="https://relay.steerify.dev/w.js" data-inbox="<inbox>" defer></script>
```
Tell it who and where when the app knows: `SteerifyFeedback.configure({ name, email, version, page })` after sign-in.
Any element with `data-steerify-feedback="bug|feature|question"` opens it; or a menu item calling
`SteerifyFeedback.open('bug')`. Put the button where the app already keeps help / account actions; if there is no
obvious place, ask with a choice (prototype of 2–3 places). No web app → skip.

## 4. MCP / API (if the project has an MCP server or a public API)
Add one tool, `report_issue`, that POSTs to `https://relay.steerify.dev/v1/feedback/<inbox>`:
`{kind: bug|feature|question, title, text, page, version, source: "person"|"agent", agent, name, email, context}`.
- `found_by: "person"`: the user asked to report it (their name; email only if they want status mails).
- `found_by: "agent"`: the agent hit an error or a wrong result itself; put the call and the error verbatim in `context`.
- Describe in the tool when to use it and when not (validation errors, permissions, once per problem).
- If the server has guides or docs for agents, add a short "feedback" guide with the same rules.
Test it once with a real call (title "Test report from <project> MCP") and check it reaches Ready › New requests.
No MCP / API → skip.

## 5. Roadmap page
Ask which chapters may be public with a choice: list the board's areas and chapters, propose the product ones
(features, UX) as public and business / internal / client work as hidden. Then
`feedback_setup {areas: [...], hide: ["word in a chapter name", ...]}`. What's new only shows work delivered for a
public chapter.

## Finish
Deliver one To test card: the form link, the roadmap link, a screenshot of the widget in the app (if added), the MCP
test report (if added). `kind: "local"` when the widget / MCP change still has to ship, `"design"` otherwise.
Then `update_request` (status done, one line).
