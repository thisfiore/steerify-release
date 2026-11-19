# Prototype kit

Live prototypes for UI choices, in the project's own design system. A choice option points at a prototype
(`"proto": "protos/<choice id>.html?v=B"`); Steerify draws its thumbnail and opens it live ("Open it live").

```
<board>/kit/
  proto.js         the engine (generic, copy from ~/.claude/skills/steerify/kit/proto.js, never edit)
  tokens.css       the project's tokens as CSS variables (colours, radii, fonts) — from its real source
  components.css   the project's components as classes (card, button, pill, table, nav…)
  data.js          window.KIT_DATA = {…} invented sample data in the project's shapes (no client data)
  catalog.html     every component on one page (it is a prototype too: open it to check the kit)
  README.md        this file + the project's component list
<board>/protos/<choice id>.html     one prototype per choice
```

## Writing a prototype (a few lines)

```html
<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="../kit/tokens.css"><link rel="stylesheet" href="../kit/components.css">
<script src="../kit/data.js"></script></head><body>

<section data-v="today" data-label="Today">  …the screen as it is…  </section>
<section data-v="A" data-label="Inline note"> …proposal A… </section>
<section data-v="B" data-label="Side panel">  …proposal B… </section>

<script src="../kit/proto.js"></script></body></html>
```

- One `<section>` per variant: `today` (as it is now, when there is one) and `A` / `B` / `C` = the choice's options, in order.
- Each section is one full screen at the design size (`<body data-w="1200" data-h="750">`, the default; 16:10).
  It is scaled to fit: the thumbnail is a miniature, "Open it live" is the real thing.
- A switch bar on top flips Today ↔ A / B / C (keys ← →, 1–4, t). Thumbnails hide it.
- Sample data: `<div data-each="tests">…{{title}}…</div>` repeats per row (`tests:3` = first 3; `{{$i}}` = row number,
  `{{$}}` = the row when it is a plain string). `{{project.name}}` anywhere. `data-if="field"` / `data-ifnot`.
- Click-through: `data-tap="B"` on an element jumps to variant B (a flow in a few screens).
- Mark what a proposal changes with `.new` (dashed outline) or `.new-tag` (a NEW label), if the kit has them.
- Only the kit's classes and tokens; no new colours or fonts. Inline `style` for one-off layout is fine.

In the choice: `"options":[{"id":"A","label":"…","proto":"protos/<id>.html?v=A"}, {"id":"B",…,"proto":"protos/<id>.html?v=B"}]`.

## Building a project's kit (once per project)

1. Find the design system in the code: CSS variables / Tailwind config / theme file / Swift or Kotlin palette, and the
   main components (layout shell, nav, card, button, pill/badge, table, form field, modal, toast).
2. `tokens.css`: copy the real values (say the source file at the top). `components.css`: one class per component,
   named after the real component, using only the tokens. Include the app shell so a section can be a whole screen.
3. `data.js`: invented records in the real shapes (names of the project's entities, realistic counts and states).
4. `catalog.html`: sections `Shell`, `Parts`, … showing everything; open it and compare with the real app side by
   side (screenshot both). Fix until it looks like the product.
5. Copy `proto.js` from the skill folder. Commit `kit/` and `protos/` with the board.
