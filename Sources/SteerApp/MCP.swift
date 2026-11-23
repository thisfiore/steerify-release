import Foundation

/// `Steerify --mcp`: a Model Context Protocol server (JSON-RPC 2.0 over stdio) that Claude Code sessions
/// started by Steerify get automatically. Structured, validated board writes instead of hand-edited JSON,
/// and UI actions (toast, jump to an item, refresh) delivered to the running app via a distributed notification.
enum SteerifyMCP {
    static let uiNotification = Notification.Name("com.frenkfiore.steerify.ui")

    static func run() -> Never {
        let board = ProcessInfo.processInfo.environment["STEERIFY_BOARD"] ?? ""
        while let line = readLine(strippingNewline: true) {
            guard let data = line.data(using: .utf8),
                  let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let id = msg["id"]
            let method = msg["method"] as? String ?? ""
            let params = msg["params"] as? [String: Any] ?? [:]
            if id == nil { continue }                                  // notifications (e.g. initialized): no reply
            var result: Any = [:]
            switch method {
            case "initialize":
                result = ["protocolVersion": params["protocolVersion"] as? String ?? "2024-11-05",
                          "capabilities": ["tools": [:]],
                          "serverInfo": ["name": "steerify", "version": "0.1.0"]]
            case "ping": result = [:]
            case "tools/list": result = ["tools": tools]
            case "tools/call":
                let name = params["name"] as? String ?? ""
                let args = params["arguments"] as? [String: Any] ?? [:]
                let (text, isError) = call(name, args, board: board)
                result = ["content": [["type": "text", "text": text]], "isError": isError]
            default:
                reply(["jsonrpc": "2.0", "id": id!, "error": ["code": -32601, "message": "Unknown method \(method)"]]); continue
            }
            reply(["jsonrpc": "2.0", "id": id!, "result": result])
        }
        exit(0)
    }

    private static func reply(_ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: d, encoding: .utf8) else { return }
        FileHandle.standardOutput.write((s + "\n").data(using: .utf8)!)
    }

    // MARK: Tools

    private static func schema(_ props: [String: [String: Any]], _ required: [String] = []) -> [String: Any] {
        ["type": "object", "properties": props, "required": required]
    }
    private static let str: [String: Any] = ["type": "string"]

    static let tools: [[String: Any]] = [
        ["name": "board_summary",
         "description": "What the Steerify board of this project says now: items to test, refines/brokens with notes, open choices, roadmap items in progress or waiting on the user. Read this before choosing what to do.",
         "inputSchema": schema([:])],
        ["name": "get_item",
         "description": "One board item with the user's verdict, notes, per-test notes and notes pinned on pictures. ref = test:<id> | choice:<id> | req:<id> | track:<slug> (roadmap chapter + items) | reqs:<slug> (requirements chapter).",
         "inputSchema": schema(["ref": str], ["ref"])],
        ["name": "deliver",
         "description": "Put finished, tested work on the To test tab (same fields as deliver.mjs: id, title, area, status, kind (design = a mockup to approve, OK builds it | local = on the Mac / local server, OK sends it to the release | stage | prod = testable only once released: waits for the release, then comes back to To test), what, tested[], howTo[], tests[{label,url,check,img,focus?}], shots[{img,caption,focus?}], issues[], repos[], road: <exact roadmap item text> or a list, choices: [ids of the choices this builds], reqs: [ids of the requirements this delivery meets], notesDone: [one line per note of the version before (get_item → user_notes order: card, tests, pinned), what you did, ≤ 8 words]). Always set road so Steerify can mark the roadmap when the user approves, choices when you built a choice (it then stops offering Build my pick), and reqs so the user's OK marks those requirements built. Same id = new version. what = 2–4 bullet lines (\"- Export button on Orders\\n- Uses your filters\"), each ≤ 6 words, no prose. Pictures full size and on the feature: crop each test picture to the feature at 2× (Retina), or give focus: [x,y,w,h] 0–1; never a whole window. Tests short and visual.",
         "inputSchema": schema(["item": ["type": "object"]], ["item"])],
        ["name": "ask_choice",
         "description": "Add a choice for the user to board.json decisions: {id, areas[], tags[], title, why, options:[{id,label,rec,points[],mock|shot|proto}]} with 2–4 options and exactly one rec:true. For UI choices use proto: a live prototype built with the project kit, \"protos/<choice id>.html?v=<A|B|C>\" (see kit/README.md in the board). Keep building what does not depend on it.",
         "inputSchema": schema(["decision": ["type": "object"]], ["decision"])],
        ["name": "set_roadmap_status",
         "description": "Set the status of a roadmap item (todo | wip | review | done | you). item = exact text or its slug. Mark done only with evidence (approved delivery, commit, deploy).",
         "inputSchema": schema(["item": str, "status": ["type": "string", "enum": ["todo", "wip", "review", "done", "you"]]], ["item", "status"])],
        ["name": "set_roadmap_kind",
         "description": "Say what a key result is for: core (the chapter's objective is met when every core key result is done) or an extra that never holds the chapter back: test | tutorial | enhancement | later (an idea, not promised). item = exact text or its slug; kind \"\" = clear (Steerify guesses from the words). proposed: true = a draft the user keeps or undoes on the chapter (use it when tagging an existing chapter, intent tag).",
         "inputSchema": schema(["item": str, "kind": ["type": "string", "enum": ["core", "test", "tutorial", "enhancement", "later", ""]], "proposed": ["type": "boolean"]], ["item", "kind"])],
        ["name": "set_focus",
         "description": "Chapters in focus (up to 3, in order): Steerify lists them first on the Roadmap, filters every tab to them (★ Focus), pins their sessions and groups them first on Ready and Release. {chapter (exact name), on (true = add, false = take off), position? (1–3, default: last)}. Only when the user asks for it.",
         "inputSchema": schema(["chapter": str, "on": ["type": "boolean"], "position": ["type": "integer"]], ["chapter", "on"])],
        ["name": "set_requirement_status",
         "description": "Set a requirement's status in board.json after checking the code: built (verified in the code, with evidence) | proposed | question. Never use it to answer for the user; their verdicts live in decisions.json.",
         "inputSchema": schema(["id": str, "status": ["type": "string", "enum": ["built", "proposed", "question"]], "evidence": str], ["id", "status"])],
        ["name": "set_release_config",
         "description": "Write this project's release setup into steerify.json: {repos:{<repo>:{branch, deploy?, liveCheck?}}, notes?}. The Release tab updates at once.",
         "inputSchema": schema(["release": ["type": "object"]], ["release"])],
        ["name": "set_environments",
         "description": "Save where this project is tested into steerify.json: environments = [{name, url, area?, note?}] (e.g. {name:\"platform\", url:\"https://platform.example.com\", area:\"platform\"}, {name:\"local\", url:\"http://localhost:5173\"}). To test links must start with one of these; deliver refuses a project host that is not listed. Only save addresses you found in the code / deploy config or the user gave you.",
         "inputSchema": schema(["environments": ["type": "array", "items": ["type": "object"]]], ["environments"])],
        ["name": "add_roadmap_item",
         "description": "Add a key result to a roadmap chapter: {chapter (exact name), text, status? (todo), kind? (core | test | tutorial | enhancement | later: core = needed for the objective, the rest are extras), area?, request? (request id it comes from), for? (the feature chapter a fix belongs to), create? (true: create the chapter if missing)}. Fixes and small refinements go to the rolling chapter \"Fixes & refinements\".",
         "inputSchema": schema(["chapter": str, "text": str, "status": str, "kind": str, "area": str, "request": str, "for": str, "create": ["type": "boolean"]], ["chapter", "text"])],
        ["name": "add_chapter",
         "description": "Draft a new roadmap chapter for a feature request: {name, area, objective (one line), items: [key result texts, or {text, kind}: kind = core (needed for the objective) | test | tutorial | enhancement | later; untagged items are guessed from their words], requirements?: [{id, text}], request? (request id)}. It lands as a DRAFT: the user approves it (Add to roadmap) or discards it in Steerify. Open questions go on the board with ask_choice.",
         "inputSchema": schema(["name": str, "area": str, "objective": str, "items": ["type": "array"],
                                "requirements": ["type": "array", "items": ["type": "object"]], "request": str], ["name", "items"])],
        ["name": "update_request",
         "description": "Record what a request became: {id, status (working | done | needs-you | discarded), became? [board refs: road:<slug>, track:<slug>, choice:<id>, test:<id>], note? (one line), kind? (fix | refine | feature | task | question: set it when the filed kind was wrong; Steerify learns from it)}. Keeps the request history in Steerify honest.",
         "inputSchema": schema(["id": str, "status": str, "became": ["type": "array", "items": ["type": "string"]], "note": str, "kind": str], ["id"])],
        ["name": "add_task",
         "description": "Put a task on the Tasks tab: work Claude DOES for the user with existing tools and standards (a tutorial from the SOP, a data collection, a report), never code. {id? (slug), title, outcome (what done looks like, concrete: what file / where / how many), checks: [how to tell the result is right, 2–5 short lines], sop? (the standard, skill or doc it follows), brief? (anything else), every? (\"mon 08:00\", \"mon,thu 09:30\", \"weekdays 08:00\", \"daily 07:00\"; omit = once), maxMinutes? (default 120: no result by then = No result), area?, request? (request id), runNow? (true: this session runs it now; you get the run id)}. Same id = update the task. Steerify starts scheduled runs itself and watches each run for a result.",
         "inputSchema": schema(["id": str, "title": str, "outcome": str, "checks": ["type": "array", "items": ["type": "string"]], "sop": str, "brief": str,
                                "every": str, "maxMinutes": ["type": "integer"], "area": str, "request": str, "runNow": ["type": "boolean"]], ["title", "outcome"])],
        ["name": "finish_task",
         "description": "Hand in the result of a task run (the only way a run ends well). {run? (run id from the brief) or task (task id: closes its running run), summary (1–2 lines: what you produced), files: [paths relative to the board, absolute paths or URLs to open the result], counts?: {name: number} (records, pages, …), checks: [{text, ok}] (every check of the task, honestly), failed? (true: you could not reach the outcome; say why in summary), report (the standard report Steerify draws, keep text minimal: {headline (≤ 10 words: what you got), kpis: [{value, label}] 2–4 big numbers, steps: [{text (2–3 words), n (a count: \"244 · 60 d\"), done (false = still pending)}] 3–6 = what was done, rows?: {title (what the bars measure), ref? (what the reference mark is, e.g. \"competitor avg\"), items: [{name, value (number), ref? (number), show? (\"56 · 0.6×\"), tag (2–3 words)}]} one per item, points: [≤ 3 bullets, ≤ 8 words each], details? (the full file, shown folded; default files[0])})}. The run goes to To check on the Tasks tab; the user says OK or Redo.",
         "inputSchema": schema(["run": str, "task": str, "summary": str, "files": ["type": "array", "items": ["type": "string"]], "counts": ["type": "object"],
                                "checks": ["type": "array", "items": ["type": "object"]], "failed": ["type": "boolean"], "report": ["type": "object"]], ["summary"])],
        ["name": "notify",
         "description": "Tell the user in the Steerify window (a toast), optionally jumping to an item. Use after delivering, when a choice is waiting, or when you need them.",
         "inputSchema": schema(["message": str, "ref": str], ["message"])],
    ]

    /// Soft checks on a task report: Steerify draws it either way, but tells Claude what breaks the standard.
    static func reportTips(_ r: Any?, failed: Bool) -> [String] {
        guard !failed else { return [] }
        guard let r = r as? [String: Any] else { return ["no report: add report {headline, kpis, steps, rows, points} so the result reads at a glance"] }
        var t: [String] = []
        let words = { (s: String) in s.split(whereSeparator: { $0 == " " }).count }
        if let h = r["headline"] as? String { if words(h) > 12 { t.append("headline has \(words(h)) words: keep it ≤ 10") } } else { t.append("headline is missing") }
        let k = (r["kpis"] as? [Any])?.count ?? 0
        if k < 2 || k > 4 { t.append("kpis: \(k), use 2–4") }
        let st = (r["steps"] as? [Any])?.count ?? 0
        if st < 2 || st > 6 { t.append("steps: \(st), use 3–6") }
        let p = r["points"] as? [String] ?? []
        if p.count > 3 { t.append("points: \(p.count), max 3 (only the first 3 are shown)") }
        for x in p where words(x) > 10 { t.append("point too long (\(words(x)) words): \"\(x.prefix(40))…\"") }
        return t
    }

    static func call(_ name: String, _ a: [String: Any], board: String) -> (String, Bool) {
        guard !board.isEmpty, FileManager.default.fileExists(atPath: board) else {
            return ("No board: this session was not started by Steerify (STEERIFY_BOARD is not set).", true)
        }
        switch name {
        case "board_summary": return (summary(board), false)
        case "get_item":
            guard let ref = a["ref"] as? String else { return ("ref is required", true) }
            return getItem(ref, board)
        case "deliver":
            guard var item = a["item"] as? [String: Any] else { return ("item is required", true) }
            // A re-delivery by id (status → live, keepVerdict) keeps what the previous version said.
            if let prev = deliveredItem(board, id: item["id"] as? String) {
                for k in ["title", "area", "what"] where (item[k] as? String ?? "").isEmpty { if let v = prev[k] { item[k] = v } }
            }
            // Areas are spelled many ways ("Mac app", "mac", "iPhone"): resolve to the board's key, or say which ones exist.
            switch resolveArea(item["area"] as? String, board: board) {
            case .success(let k): if let k { item["area"] = k }
            case .failure(let e): return (e.message, true)
            }
            // Board-relative links (protos/x.html?v=B, img/…) open from the board folder.
            if var tl = item["tests"] as? [[String: Any]] {
                for i in tl.indices { if let u = tl[i]["url"] as? String, let abs = boardFileURL(u, board: board) { tl[i]["url"] = abs } }
                item["tests"] = tl
            }
            // Test links go to the project's own environments only (steerify.json), never a guessed host.
            let envs = TestEnvs.load(board), testList = item["tests"] as? [[String: Any]] ?? []
            var wrong = TestEnvs.problems(tests: testList, area: item["area"] as? String, envs: envs)
            // The Test it button opens the exact thing under test: no home pages, no bare app links.
            for (i, t) in testList.enumerated() {
                if let u = t["url"] as? String, let why = TestEnvs.generic(u, envs: envs) {
                    wrong.append("test \(i + 1): \(u) opens \(why). Link the exact page / record / item to test "
                                 + "(e.g. …/image/<id>, steerify://open?project=<p>&item=test:<id>), or leave url out if the picture is the test")
                }
            }
            let reach = TestEnvs.reach(tests: testList)
            wrong += reach.broken
            if !wrong.isEmpty {
                return ("Not delivered: wrong test link\(wrong.count == 1 ? "" : "s"). Fix the url and deliver again with the same id:\n"
                        + wrong.map { "- " + $0 }.joined(separator: "\n")
                        + "\nThis project's environments: " + TestEnvs.describe(envs), true)
            }
            var r = node(board, "deliver.mjs", [jsonString(item)])
            if !r.1, !reach.down.isEmpty {
                r.0 += "\n\nThese test links did not answer just now (server stopped?). Start it, or the user's Test it button will not work:\n"
                    + reach.down.map { "- " + $0 }.joined(separator: "\n")
            }
            let unchecked = envs.isEmpty ? TestEnvs.unchecked(tests: testList) : []
            if !r.1, !unchecked.isEmpty {
                r.0 += "\n\nThis project has no environments in steerify.json, so the links (\(unchecked.joined(separator: ", "))) were not checked. "
                    + "If you are not sure they are the right addresses, ask the user (ask_choice); then save them with set_environments."
            }
            // Picture check (local, no tokens): tell Claude now, not the user after a wasted test.
            let tests = (item["tests"] as? [[String: Any]] ?? []).map { (label: $0["label"] as? String ?? "", img: $0["img"] as? String) }
            let shots = (item["shots"] as? [[String: Any]] ?? []).compactMap { $0["img"] as? String }
            let focused = Set(((item["tests"] as? [[String: Any]] ?? []) + (item["shots"] as? [[String: Any]] ?? []))
                .filter { $0["focus"] != nil }.compactMap { $0["img"] as? String })
            let issues = ShotCheck.basic(dir: board, shots: shots, tests: tests, focused: focused)
            guard !r.1, !issues.isEmpty else { return r }
            return (r.0 + "\n\nPicture check found \(issues.count) problem(s), fix them and deliver again with the same id:\n"
                    + issues.map { "- " + ($0.test.map { "test \($0 + 1)" } ?? "screenshot") + ($0.img.map { " (\($0))" } ?? "") + ": " + $0.problem }.joined(separator: "\n"), false)
        case "ask_choice":
            guard let d = a["decision"] as? [String: Any], d["id"] != nil, d["title"] != nil,
                  let opts = d["options"] as? [[String: Any]], (2...4).contains(opts.count) else {
                return ("decision needs id, title and 2–4 options", true)
            }
            guard opts.filter({ $0["rec"] as? Bool == true }).count == 1 else { return ("exactly one option needs rec: true", true) }
            if let problems = ChoiceVisuals.problems(d, board: board) { return (problems, true) }
            let r = editBoard(board, """
                const d = \(jsonString(d)); d.added = d.added || new Date().toISOString().slice(0,10);
                const from = \(jsonString(ProcessInfo.processInfo.environment["STEERIFY_ITEM"] ?? ""));
                if (!d.from && from && !b.decisions.some(x => x.id === d.id)) d.from = from;   // the item / request that asked it: its sibling choices are built together
                const i = b.decisions.findIndex(x => x.id === d.id);
                if (i >= 0 && !d.from) {   // a revision keeps where the choice came from
                  const old = b.decisions[i], m = (old.why || '').match(/\\br\\d{6}-\\d{6}\\b/);
                  if (old.from) d.from = old.from; else if (m) d.from = 'request:' + m[0];
                }
                if (i >= 0) { d.revisedAt = new Date().toISOString(); b.decisions[i] = d } else b.decisions.push(d);
                out = (i >= 0 ? 'revised ' : 'added ') + d.id;
                """)
            if !r.1 { ui(["action": "focus", "ref": "choice:\(d["id"]!)", "message": "New choice: \(d["title"]!)", "board": board]) }
            return r
        case "set_roadmap_status":
            guard let item = a["item"] as? String, let st = a["status"] as? String else { return ("item and status are required", true) }
            return editBoard(board, """
                const want = \(jsonString(item)); const st = \(jsonString(st));
                const slug = s => s.normalize('NFD').replace(/[\\u0300-\\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'').slice(0,48);
                let hit = null;
                const near = []; for (const t of b.tracks || []) for (const it of t.items || []) { const a = slug(it[0]), w = slug(want); if (a && w && a !== w && (a.startsWith(w) || w.startsWith(a))) near.push(it[0]) }
                const exact = (b.tracks || []).some(t => (t.items || []).some(it => it[0] === want || slug(it[0]) === slug(want)));
                const target = !exact && near.length === 1 ? near[0] : null;
                for (const t of b.tracks || []) for (const it of t.items || []) if (it[0] === want || slug(it[0]) === slug(want) || it[0] === target) {
                  if (it[1] !== st) { if (!(it[2] && typeof it[2] === 'object')) it[2] = {}; it[2].moved = new Date().toISOString() }
                  it[1] = st; hit = it[0];
                  if (st === 'done') { if (!(it[2] && typeof it[2] === 'object')) it[2] = {}; it[2].doneAt = new Date().toISOString().slice(0,10) }
                  else if (it[2] && typeof it[2] === 'object') { delete it[2].doneAt; if (!Object.keys(it[2]).length) it.length = 2 }
                }
                if (!hit) throw new Error('No roadmap item ' + want);
                out = st + ': ' + hit;
                """)
        case "set_roadmap_kind":
            guard let item = a["item"] as? String, let k = a["kind"] as? String, k.isEmpty || RoadItem.kinds.contains(k) else {
                return ("item and kind (core | test | tutorial | enhancement | later | \"\") are required", true)
            }
            let r = editBoard(board, """
                const want = \(jsonString(item)); const k = \(jsonString(k)); const proposed = \(a["proposed"] as? Bool == true ? "true" : "false");
                const slug = s => s.normalize('NFD').replace(/[\\u0300-\\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'').slice(0,48);
                let hit = null;
                const near = []; for (const t of b.tracks || []) for (const it of t.items || []) { const a = slug(it[0]), w = slug(want); if (a && w && a !== w && (a.startsWith(w) || w.startsWith(a))) near.push(it[0]) }
                const exact = (b.tracks || []).some(t => (t.items || []).some(it => it[0] === want || slug(it[0]) === slug(want)));
                const target = !exact && near.length === 1 ? near[0] : null;
                for (const t of b.tracks || []) for (const it of t.items || []) if (it[0] === want || slug(it[0]) === slug(want) || it[0] === target) {
                  if (it.length < 2) it[1] = 'todo';
                  if (k) { if (!(it[2] && typeof it[2] === 'object')) it[2] = {}; it[2].kind = k; if (proposed) it[2].kindProposed = true; else delete it[2].kindProposed }
                  else if (it[2] && typeof it[2] === 'object') { delete it[2].kind; delete it[2].kindProposed; if (!Object.keys(it[2]).length) it.length = 2 }
                  hit = it[0];
                }
                if (!hit) throw new Error('No roadmap item ' + want);
                out = (k || 'guessed') + ': ' + hit;
                """)
            if !r.1 { ui(["action": "refresh", "board": board]) }
            return r
        case "set_focus":
            guard let ch = a["chapter"] as? String, let on = a["on"] as? Bool else { return ("chapter and on are required", true) }
            let pos = (a["position"] as? Int).map { String($0) } ?? "null"
            let r = editBoard(board, """
                const ch = \(jsonString(ch)), on = \(on ? "true" : "false"), pos = \(pos);
                const names = (b.tracks || []).map(t => t.name);
                if (!names.includes(ch)) throw new Error('No chapter ' + ch);
                let f = (Array.isArray(b.focus) ? b.focus : []).filter(n => names.includes(n) && n !== ch);
                if (on) {
                  if (f.length >= 3) throw new Error('3 chapters are in focus already: take one off first');
                  const i = pos ? Math.max(0, Math.min(f.length, pos - 1)) : f.length; f.splice(i, 0, ch);
                }
                if (f.length) b.focus = f; else delete b.focus;
                out = f.length ? 'in focus: ' + f.map((n, i) => (i + 1) + '. ' + n).join(' · ') : 'no chapter in focus';
                """)
            if !r.1 { ui(["action": "refresh", "board": board]) }
            return r
        case "keep_kinds", "undo_kinds":                     // app-only (Keep / Undo on a chapter Claude tagged)
            guard let ch = a["chapter"] as? String else { return ("chapter is required", true) }
            let keep = name == "keep_kinds"
            return editBoard(board, """
                const ch = \(jsonString(ch)), keep = \(keep ? "true" : "false"); let n = 0;
                const t = (b.tracks || []).find(x => x.name === ch); if (!t) throw new Error('No chapter ' + ch);
                for (const it of t.items || []) if (it[2] && typeof it[2] === 'object' && it[2].kindProposed) {
                  delete it[2].kindProposed; if (!keep) delete it[2].kind; n++;
                  if (!Object.keys(it[2]).length) it.length = 2;
                }
                out = (keep ? 'kept ' : 'undid ') + n + ' kinds in ' + ch;
                """)
        case "set_requirement_status":
            guard let id = a["id"] as? String, let st = a["status"] as? String else { return ("id and status are required", true) }
            let ev = a["evidence"] as? String ?? ""
            return editBoard(board, """
                const id = \(jsonString(id)), st = \(jsonString(st)), ev = \(jsonString(ev)); let hit = null;
                for (const g of b.requirements || []) for (const r of g.items || []) if (r.id === id) { r.status = st; if (ev) r.evidence = ev; hit = r.text }
                if (!hit) throw new Error('No requirement ' + id);
                out = st + ': ' + hit;
                """)
        case "set_release_config":
            guard let rel = a["release"] as? [String: Any], rel["repos"] is [String: Any] else { return ("release.repos is required", true) }
            let r = JSONFile.edit((board as NSString).appendingPathComponent("steerify.json"), key: "release", value: rel)
            if r.1 { return r }
            ui(["action": "refresh", "message": "Release setup updated", "board": board])
            return ("release setup saved in steerify.json", false)
        case "set_environments":
            guard let envs = a["environments"] as? [[String: Any]],
                  envs.allSatisfy({ ($0["name"] as? String ?? "").isEmpty == false && TestEnvs.host($0["url"] as? String ?? "") != nil }) else {
                return ("environments = [{name, url (http/https), area?, note?}]", true)
            }
            let r = JSONFile.edit((board as NSString).appendingPathComponent("steerify.json"), key: "environments", value: envs)
            if r.1 { return r }
            ui(["action": "refresh", "message": "Test environments updated", "board": board])
            return ("environments saved in steerify.json: " + TestEnvs.describe(TestEnvs.load(board)), false)
        case "add_roadmap_item":
            guard let ch = a["chapter"] as? String, let text = a["text"] as? String, !text.isEmpty else { return ("chapter and text are required", true) }
            var meta: [String: Any] = [:]
            if let r = a["request"] as? String, !r.isEmpty { meta["req"] = r; meta["at"] = String(RequestLog.now().prefix(10)) }
            if let f = a["for"] as? String, !f.isEmpty { meta["for"] = f }
            if let ar = a["area"] as? String, !ar.isEmpty { meta["area"] = ar }
            if let k = a["kind"] as? String, RoadItem.kinds.contains(k) { meta["kind"] = k }
            let r = editBoard(board, """
                const ch = \(jsonString(ch)), text = \(jsonString(text)), st = \(jsonString(a["status"] as? String ?? "todo"));
                const meta = \(jsonString(meta)), create = \(a["create"] as? Bool == true ? "true" : "false"), area = \(jsonString(a["area"] as? String ?? ""));
                b.tracks = b.tracks || [];
                let t = b.tracks.find(x => x.name === ch);
                if (!t) { if (!create) throw new Error('No chapter ' + ch + ' (pass create: true)'); t = { name: ch, area: area || undefined, rolling: true, items: [] }; b.tracks.push(t) }
                if (t.items.some(i => i[0] === text)) throw new Error('Already there: ' + text);
                t.items.push(Object.keys(meta).length ? [text, st, meta] : [text, st]);
                out = 'added to ' + ch + ': ' + text;
                """)
            if !r.1 { ui(["action": "refresh", "board": board]) }
            return r
        case "add_chapter":
            // items: plain texts, or {text, kind} so Claude says which key results are the core.
            let items: [[Any]] = (a["items"] as? [Any] ?? []).compactMap { x in
                if let t = x as? String, !t.isEmpty { return [t, "todo"] }
                guard let o = x as? [String: Any], let t = o["text"] as? String, !t.isEmpty else { return nil }
                if let k = o["kind"] as? String, RoadItem.kinds.contains(k) { return [t, "todo", ["kind": k]] }
                return [t, "todo"]
            }
            guard let name = a["name"] as? String, !name.isEmpty, !items.isEmpty else { return ("name and items are required", true) }
            let reqs = a["requirements"] as? [[String: Any]] ?? []
            let day = String(RequestLog.now().prefix(10))
            let r = editBoard(board, """
                const name = \(jsonString(name)), area = \(jsonString(a["area"] as? String ?? "")), obj = \(jsonString(a["objective"] as? String ?? ""));
                const items = \(jsonString(items)), reqs = \(jsonString(reqs)), req = \(jsonString(a["request"] as? String ?? ""));
                b.tracks = b.tracks || [];
                if (b.tracks.some(t => t.name === name && !t.draft)) throw new Error('Chapter already on the roadmap: ' + name);
                b.tracks = b.tracks.filter(t => t.name !== name);
                const t = { name, area: area || undefined, draft: true, items };
                if (obj) t.objective = obj; if (req) t.request = req;
                b.tracks.push(t);
                if (reqs.length) {
                  b.requirements = (b.requirements || []).filter(g => g.h !== name);
                  b.requirements.push({ area: area || undefined, h: name, draft: true, request: req || undefined,
                    items: reqs.map(r => ({ id: r.id, text: r.text, status: 'proposed', src: 'Claude, \(day)' })) });
                }
                out = 'draft chapter ' + name + ' (' + items.length + ' key results, ' + reqs.length + ' requirements): waiting for the user';
                """)
            if !r.1 { ui(["action": "focus", "ref": "track:" + BoardFiles.slug(name), "message": "Chapter draft to approve: \(name)", "board": board]) }
            return r
        case "approve_chapter", "discard_chapter":            // app-only (buttons on a draft chapter)
            guard let chName = a["name"] as? String else { return ("name is required", true) }
            let approve = name == "approve_chapter"
            return editBoard(board, """
                const name = \(jsonString(chName)), approve = \(approve ? "true" : "false");
                const t = (b.tracks || []).find(x => x.name === name); if (!t) throw new Error('No chapter ' + name);
                if (approve) {
                  delete t.draft;
                  // Approving a chapter agrees its requirements: nothing is left to confirm one by one.
                  for (const g of b.requirements || []) if (g.h === name) {
                    delete g.draft;
                    for (const r of g.items || []) if (!r.status || r.status === 'proposed') { r.status = 'agreed'; r.evidence = 'chapter approved ' + new Date().toISOString().slice(0, 10) }
                  }
                }
                else { b.tracks = b.tracks.filter(x => x !== t); b.requirements = (b.requirements || []).filter(g => !(g.h === name && g.draft)) }
                out = (approve ? 'approved ' : 'discarded ') + name;
                """)
        case "update_request":
            guard let rawId = a["id"] as? String else { return ("id is required", true) }
            let id = rawId.hasPrefix("request:") ? String(rawId.dropFirst(8)) : rawId
            let ok = RequestLog.edit(board, id: id) { r in
                if let st = a["status"] as? String { r["status"] = st }
                if let bc = a["became"] as? [String] { r["became"] = Array(NSOrderedSet(array: (r["became"] as? [String] ?? []) + bc)) }
                if let n = a["note"] as? String { r["note"] = n }
                // Claude's correction of the kind: the suggestion stays as `guess`, so the triage learns (TriageLessons).
                if let k = (a["kind"] as? String).flatMap(RequestKind.init(rawValue:)), k.rawValue != r["kind"] as? String {
                    if r["guess"] == nil { r["guess"] = r["kind"] }
                    r["kind"] = k.rawValue; r["kindBy"] = "claude"
                }
                r["updated"] = RequestLog.now()
            }
            if !ok { return ("no request \(id)", true) }
            ui(["action": "refresh", "board": board])
            return ("request \(id) updated", false)
        case "add_task":
            guard let title = a["title"] as? String, let outcome = a["outcome"] as? String else { return ("title and outcome are required", true) }
            let id = (a["id"] as? String).flatMap { $0.isEmpty ? nil : BoardFiles.slug($0) } ?? BoardFiles.slug(title)
            if let e = a["every"] as? String, !e.isEmpty, TaskSchedule(e) == nil {
                return ("every: can't read \"\(e)\". Use e.g. \"mon 08:00\", \"mon,thu 09:30\", \"weekdays 08:00\", \"daily 07:00\".", true)
            }
            var existed = false
            let ok = TaskStore.edit(board) { tasks, _ in
                var t: [String: Any] = tasks.first { $0["id"] as? String == id } ?? ["id": id, "created": TaskStore.now()]
                existed = tasks.contains { $0["id"] as? String == id }
                t["title"] = title; t["outcome"] = outcome
                for k in ["checks", "sop", "brief", "every", "maxMinutes", "area", "request"] { if let v = a[k] { t[k] = v } }
                if let i = tasks.firstIndex(where: { $0["id"] as? String == id }) { tasks[i] = t } else { tasks.append(t) }
            }
            if !ok { return ("could not write tasks.json", true) }
            if let rq = a["request"] as? String {
                RequestLog.edit(board, id: rq) { r in r["became"] = Array(NSOrderedSet(array: (r["became"] as? [String] ?? []) + ["task:" + id])) }
            }
            var msg = (existed ? "updated" : "added") + " task:\(id)"
            if let e = a["every"] as? String, let s = TaskSchedule(e) { msg += " (\(s.describe); Steerify starts each run and briefs a fresh session)" }
            if a["runNow"] as? Bool == true {
                let env = ProcessInfo.processInfo.environment
                if let run = TaskStore.addRun(board, task: id, due: nil, late: false, session: nil, term: env["STEERIFY_SESSION"], note: nil) {
                    msg += ". Run \(run) started in this session: reach the outcome, then finish_task with run \"\(run)\"."
                }
            }
            ui(["action": "refresh", "board": board])
            return (msg, false)
        case "finish_task":
            guard let summary = a["summary"] as? String else { return ("summary is required", true) }
            let (_, runs) = TaskStore.load(board)
            var runId = a["run"] as? String
            if runId == nil, let t = a["task"] as? String {
                runId = runs.first { $0.task == t && $0.status == "running" }?.id
                    ?? TaskStore.addRun(board, task: t, due: nil, late: false, session: nil, term: ProcessInfo.processInfo.environment["STEERIFY_SESSION"], note: nil)
            }
            if let r = runId, !TaskStore.raw(board).runs.contains(where: { $0["id"] as? String == r }),
               let t = r.split(separator: "@").first.map(String.init), TaskStore.raw(board).tasks.contains(where: { $0["id"] as? String == t }) {
                runId = runs.first { $0.task == t && $0.status == "running" }?.id
                    ?? TaskStore.addRun(board, task: t, due: nil, late: false, session: nil, term: ProcessInfo.processInfo.environment["STEERIFY_SESSION"], note: nil)
            }
            guard let rid = runId, TaskStore.raw(board).runs.contains(where: { $0["id"] as? String == rid }) else {
                return ("no such run; pass run (from your brief) or task", true)
            }
            var result: [String: Any] = ["summary": summary]
            for k in ["files", "counts", "checks", "report"] { if let v = a[k] { result[k] = v } }
            let failed = a["failed"] as? Bool == true
            TaskStore.setRun(board, id: rid) { r in
                r["status"] = failed ? "noresult" : "done"; r["finished"] = TaskStore.now(); r["result"] = result
                if failed { r["why"] = "Claude couldn't reach the outcome" }
            }
            let bad = (a["checks"] as? [[String: Any]] ?? []).filter { $0["ok"] as? Bool != true }.count
            let task = TaskStore.load(board).runs.first { $0.id == rid }?.task ?? ""
            ui(["action": "notify", "board": board, "ref": "task:" + task,
                "message": failed ? "Task result: couldn't reach the outcome" : "Task result to check" + (bad > 0 ? " · \(bad) check\(bad == 1 ? "" : "s") failed" : "")])
            var msg = "run \(rid) handed in: it is on the Tasks tab, To check. Say in the chat what you produced and where."
            let tips = reportTips(a["report"], failed: failed)
            if !tips.isEmpty { msg += "\n\nReport standard (fix with finish_task again, same run):\n" + tips.map { "- " + $0 }.joined(separator: "\n") }
            return (msg, false)
        case "notify":
            guard let m = a["message"] as? String else { return ("message is required", true) }
            var info: [String: String] = ["action": "notify", "message": m, "board": board]
            if let r = a["ref"] as? String { info["ref"] = r }
            ui(info)
            return ("shown in Steerify", false)
        default: return ("Unknown tool \(name)", true)
        }
    }

    // MARK: Helpers

    struct AreaError: Error { let message: String }

    /// The delivered item with this id, if any (for re-deliveries that only send what changed).
    static func deliveredItem(_ board: String, id: String?) -> [String: Any]? {
        guard let id, !id.isEmpty, let d = BoardFiles.json(board, "delivered.json") else { return nil }
        let items = (d as? [String: Any])?["items"] as? [[String: Any]] ?? (d as? [[String: Any]] ?? [])
        return items.first { $0["id"] as? String == id }
    }

    /// The board.json area key for what a session wrote: the key itself, any case, or the area's name, or the one
    /// area whose key / name contains it. nil area = leave it (deliver.mjs says it is missing).
    static func resolveArea(_ given: String?, board: String) -> Result<String?, AreaError> {
        guard let given = given?.trimmingCharacters(in: .whitespaces), !given.isEmpty else { return .success(nil) }
        let areas = (BoardFiles.json(board, "board.json") as? [String: Any])?["areas"] as? [String: Any] ?? [:]
        guard !areas.isEmpty else { return .success(given) }
        let names = areas.mapValues { (($0 as? [String: Any])?["name"] as? String) ?? "" }
        let g = given.lowercased(), gs = BoardFiles.slug(given).lowercased()
        if areas[given] != nil { return .success(given) }
        if let k = names.keys.first(where: { $0.lowercased() == g || BoardFiles.slug($0).lowercased() == gs }) { return .success(k) }
        if let k = names.first(where: { $0.value.lowercased() == g || BoardFiles.slug($0.value).lowercased() == gs })?.key { return .success(k) }
        let words = { (s: String) in Set(BoardFiles.slug(s).lowercased().split(separator: "-").map(String.init)) }
        let gw = words(given)
        let near = names.filter { k, n in !gw.isDisjoint(with: words(k).union(words(n))) }
        if near.count == 1, let k = near.first?.key { return .success(k) }
        let list = names.keys.sorted().map { k in names[k]!.isEmpty ? k : "\(k) (\(names[k]!))" }.joined(separator: ", ")
        return .failure(AreaError(message: "area \"\(given)\" is not one of this board's areas. Use one of: \(list)"))
    }

    static func boardFileURL(_ s: String, board: String) -> String? { TestEnvs.boardFile(s, board: board) }

    private static func jsonString(_ v: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed])).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }

    /// Edit board.json with node, keeping its own formatting (1-space JSON) so diffs stay small.
    private static func editBoard(_ board: String, _ js: String) -> (String, Bool) {
        let script = """
        const fs = require('fs'); const P = process.argv[1] + '/board.json';
        const raw = fs.readFileSync(P, 'utf8'); const b = JSON.parse(raw); let out = 'ok';
        const indent = (raw.match(/\\n( +)"/) || [, ' '])[1].length;
        try {
        \(js)
        } catch (e) { console.error(e.message); process.exit(1) }
        fs.writeFileSync(P, JSON.stringify(b, null, indent) + '\\n'); console.log(out);
        """
        return runNode(["-e", script, board], cwd: board)
    }

    private static func node(_ board: String, _ file: String, _ args: [String]) -> (String, Bool) {
        let path = (board as NSString).appendingPathComponent(file)
        guard FileManager.default.fileExists(atPath: path) else { return ("\(file) not found in the board folder", true) }
        let r = runNode([path] + args, cwd: board)
        if !r.1 { ui(["action": "refresh", "message": r.0.split(separator: "\n").last.map(String.init) ?? "delivered", "board": board]) }
        return r
    }

    private static func runNode(_ args: [String], cwd: String) -> (String, Bool) {
        guard let node = BoardServers.shared.node else { return ("node not found", true) }
        let r = BoardServers.exec(node, args, cwd: cwd, timeout: 60)
        let o = r.out.trimmingCharacters(in: .whitespacesAndNewlines), e = r.err.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.status == 0 ? (o, false) : (e.isEmpty ? o : e, true)
    }

    /// UI actions for the running Steerify app (distributed notification: same user, instant).
    private static func ui(_ info: [String: String]) {
        DistributedNotificationCenter.default().postNotificationName(uiNotification, object: nil, userInfo: info, deliverImmediately: true)
    }

    private static func summary(_ board: String) -> String {
        let b = BoardFiles.json(board, "board.json") as? [String: Any] ?? [:]
        let dec = (BoardFiles.json(board, "decisions.json") as? [String: Any])?["choices"] as? [String: Any] ?? [:]
        let del = (BoardFiles.json(board, "delivered.json") as? [String: Any])?["items"] as? [[String: Any]] ?? []
        var lines: [String] = []
        var toTest: [String] = [], waiting: [String] = []
        for it in del {
            let id = it["id"] as? String ?? "", ver = it["version"] as? Int ?? 1
            let v = dec["ship:" + id] as? [String: Any] ?? [:]
            let pick = (v["v"] as? Int) == ver ? v["pick"] as? String : nil
            let title = it["title"] as? String ?? id
            if pick == nil { toTest.append("- test:\(id) — \(title)") }
            else if pick == "refine" || pick == "broken" { waiting.append("- test:\(id) — \(title) [\(pick!)] \((v["note"] as? String ?? "").prefix(160))") }
        }
        let open = (b["decisions"] as? [[String: Any]] ?? []).filter { dec[$0["id"] as? String ?? ""] == nil }
            .map { "- choice:\($0["id"] ?? "") — \($0["title"] ?? "")" }
        var road: [String] = []
        for t in b["tracks"] as? [[String: Any]] ?? [] {
            for it in t["items"] as? [[Any]] ?? [] where ["wip", "you", "review"].contains(it.count > 1 ? (it[1] as? String ?? "") : "") {
                road.append("- [\(it[1])] \(it[0]) (\(t["name"] ?? ""))")
            }
        }
        lines.append("TO TEST (\(toTest.count))"); lines += toTest.prefix(15)
        lines.append("\nWAITING ON CLAUDE: refine/broken (\(waiting.count))"); lines += waiting.prefix(15)
        lines.append("\nOPEN CHOICES (\(open.count))"); lines += open.prefix(15)
        lines.append("\nROADMAP in progress / review / waiting on the user (\(road.count))"); lines += road.prefix(25)
        let tasks = TaskStore.summary(board)
        if !tasks.isEmpty { lines.append("\nTASKS (\(tasks.count))"); lines += tasks.prefix(15) }
        return lines.joined(separator: "\n")
    }

    private static func getItem(_ ref: String, _ board: String) -> (String, Bool) {
        let parts = ref.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return ("ref must look like test:<id>", true) }
        let b = BoardFiles.json(board, "board.json") as? [String: Any] ?? [:]
        let dec = (BoardFiles.json(board, "decisions.json") as? [String: Any])?["choices"] as? [String: Any] ?? [:]
        var out: [String: Any] = ["ref": ref]
        switch parts[0] {
        case "test":
            let del = (BoardFiles.json(board, "delivered.json") as? [String: Any])?["items"] as? [[String: Any]] ?? []
            guard let it = del.first(where: { $0["id"] as? String == parts[1] }) else { return ("no To test item \(parts[1])", true) }
            out["item"] = it; out["verdict"] = dec["ship:" + parts[1]] ?? NSNull()
            // Every note of the current version in one place (request r261122-095541): Claude acts on them whatever the pick.
            let ver = dec["ship:" + parts[1]] as? [String: Any] ?? [:]
            let cur = it["version"] as? Int ?? 1
            if (ver["v"] as? Int) == cur {
                var notes: [String: Any] = [:]
                if let n = (ver["note"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { notes["card"] = n }
                let tests = it["tests"] as? [[String: Any]] ?? []
                let per = (ver["tests"] as? [String: Any] ?? [:]).compactMap { k, v -> [String: Any]? in
                    guard let i = Int(k), let d = v as? [String: Any] else { return nil }
                    let note = ((d["note"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard (d["refine"] as? Bool ?? false) || !note.isEmpty else { return nil }
                    let t = i < tests.count ? tests[i] : [:]
                    var x: [String: Any] = ["test": i + 1, "label": t["label"] ?? "", "note": note.isEmpty ? "(marked To refine, no words: look at its picture again)" : note]
                    if let img = t["img"] as? String { x["img"] = img.hasPrefix("/") ? img : (board as NSString).appendingPathComponent(img) }
                    return x
                }.sorted { ($0["test"] as? Int ?? 0) < ($1["test"] as? Int ?? 0) }
                if !per.isEmpty { notes["tests"] = per }
                let pins = (ver["pins"] as? [[String: Any]] ?? []).filter { p in (p["v"] as? Int).map { $0 == cur } ?? true }.map { p -> [String: Any] in
                    let img = p["img"] as? String ?? ""
                    return ["note": p["note"] ?? "", "x": p["x"] ?? 0, "y": p["y"] ?? 0, "img": img.hasPrefix("/") ? img : (board as NSString).appendingPathComponent(img)]
                }
                if !pins.isEmpty { notes["pinned"] = pins }
                if !notes.isEmpty {
                    notes["count"] = (notes["card"] == nil ? 0 : 1) + per.count + pins.count
                    out["user_notes"] = notes
                    out["how_to_read_the_notes"] = "Every note is a required change, whatever the pick. pick ok + notes = OK once the notes are applied: apply them (small changes), test, then release; a note bigger than a tweak → re-deliver for a new check. pick refine / broken / none → fix them and re-deliver with the same id. Pinned: open img, look at x/y (0–1 from the top-left). Say per note what you did: on the re-delivery set notesDone = one short line per note (≤ 8 words), in this order: card, tests by number, pinned. The new version starts clean and shows them as processed."
                }
            }
            // Notes of an older version: already processed by an earlier delivery. Apart, never to act on again.
            let tl = (it["tests"] as? [[String: Any]] ?? []).map { $0["label"] as? String ?? "" }
            if let pn = BoardStore.previousNotes(entry: ver, version: cur, testLabels: tl, done: it["notesDone"] as? [String] ?? []), !pn.notes.isEmpty {
                var j = pn.json
                j["notes"] = (j["notes"] as? [[String: Any]] ?? []).map { n in
                    var n = n; if let img = n["img"] as? String, !img.hasPrefix("/") { n["img"] = (board as NSString).appendingPathComponent(img) }; return n }
                out["previous_notes"] = j
                out["about_previous_notes"] = "Notes on v\(pn.v ?? cur - 1), processed by this version (done = what it said it did). Context only: act on user_notes."
            }
        case "choice":
            guard let d = (b["decisions"] as? [[String: Any]] ?? []).first(where: { $0["id"] as? String == parts[1] }) else { return ("no choice \(parts[1])", true) }
            var slim = d; slim["options"] = (d["options"] as? [[String: Any]] ?? []).map { o in o.filter { $0.key != "mock" } }
            out["choice"] = slim; out["answer"] = dec[parts[1]] ?? NSNull()
            let entry = dec[parts[1]] as? [String: Any] ?? [:]
            let revised = d["revisedAt"] as? String
            if let pn = BoardStore.previousChoiceNotes(entry: entry, revisedAt: revised) {
                out["previous_notes"] = pn.json
                out["about_previous_notes"] = "The answer given before your last revision (\(revised ?? "")): processed. Context only."
                if let r = revised, let at = entry["at"] as? String, at < r { out["answer"] = NSNull() }
            }
            out["how_to_read_the_answer"] = "pick = the chosen option id (__note = the note is the answer); mix = other option ids to blend into it; note = how (and anything else). Multi-choices: pick is a list. pinned_notes = notes the user pinned on an option's picture: open img, look at x/y (0–1 from the top-left); each one on the picked option is a required change, build it and say per note what you did."
            let opts = d["options"] as? [[String: Any]] ?? []
            let pins = (((dec[parts[1]] as? [String: Any])?["pins"] as? [[String: Any]]) ?? []).filter { p in
                guard let r = revised else { return true }
                return ((p["at"] as? String) ?? r) >= r
            }
            if !pins.isEmpty {
                out["pinned_notes"] = pins.map { p -> [String: Any] in
                    let img = p["img"] as? String ?? ""
                    let i = opts.firstIndex { o in (o["id"] as? String) == (p["opt"] as? String) || (!img.isEmpty && (o["shot"] as? String) == img) }
                    var x: [String: Any] = ["note": p["note"] ?? "", "x": p["x"] ?? 0, "y": p["y"] ?? 0,
                                            "img": img.hasPrefix("/") ? img : (board as NSString).appendingPathComponent(img)]
                    if let i { x["option"] = opts[i]["id"] ?? NSNull(); x["letter"] = String(UnicodeScalar(65 + i)!) }
                    else { x["option"] = NSNull() }
                    return x
                }
            }
        case "req":
            for g in b["requirements"] as? [[String: Any]] ?? [] {
                if let r = (g["items"] as? [[String: Any]] ?? []).first(where: { $0["id"] as? String == parts[1] }) { out["requirement"] = r; out["group"] = g["h"] }
            }
            out["verdict"] = dec["req:" + parts[1]] ?? NSNull()
        case "track":
            let tracks = b["tracks"] as? [[String: Any]] ?? []
            let want = BoardFiles.slug(parts[1]).lowercased()
            let tslug = { (t: [String: Any]) in BoardFiles.slug((t["name"] as? String) ?? "").lowercased() }
            // Sessions slug the whole name; Steerify's slugs stop at 48 characters: match either way, if only one fits.
            let loose = tracks.filter { let s = tslug($0); return !s.isEmpty && (s.hasPrefix(want) || want.hasPrefix(s)) }
            guard let t = tracks.first(where: { tslug($0) == want || ($0["name"] as? String) == parts[1] }) ?? (loose.count == 1 ? loose.first : nil)
            else { return ("no roadmap chapter \(parts[1]). Chapters: " + tracks.compactMap { ($0["name"] as? String).map { "track:" + BoardFiles.slug($0) } }.joined(separator: ", "), true) }
            out["chapter"] = t["name"]; out["area"] = t["area"] ?? NSNull()
            out["items"] = (t["items"] as? [[Any]] ?? []).map { ["text": $0.first ?? "", "status": $0.count > 1 ? $0[1] : "todo"] }
        case "road":
            let want = BoardFiles.slug(parts[1]).lowercased()
            var hits: [(String, [Any])] = []
            for t in b["tracks"] as? [[String: Any]] ?? [] {
                for it in t["items"] as? [[Any]] ?? [] {
                    let s = BoardFiles.slug((it.first as? String) ?? "").lowercased()
                    if s == want || it.first as? String == parts[1] { hits = [((t["name"] as? String) ?? "", it)]; break }
                    if !s.isEmpty, s.hasPrefix(want) || want.hasPrefix(s) { hits.append(((t["name"] as? String) ?? "", it)) }
                }
                if hits.count == 1, BoardFiles.slug((hits[0].1.first as? String) ?? "").lowercased() == want { break }
            }
            guard hits.count == 1, let (chapter, it) = hits.first else { return ("no roadmap item \(parts[1])", true) }
            out["chapter"] = chapter; out["text"] = it.first ?? ""; out["status"] = it.count > 1 ? it[1] : "todo"
            if it.count > 2 { out["meta"] = it[2] }
        case "reqs":
            guard let g = (b["requirements"] as? [[String: Any]] ?? []).first(where: { BoardFiles.slug(($0["h"] as? String) ?? "") == parts[1] })
            else { return ("no requirements chapter \(parts[1])", true) }
            out["chapter"] = g["h"]
            out["items"] = (g["items"] as? [[String: Any]] ?? []).map { r -> [String: Any] in
                var x = r; x["verdict"] = dec["req:" + (r["id"] as? String ?? "")] ?? NSNull(); return x }
        case "request":
            guard let r = RequestLog.raw(board).first(where: { $0["id"] as? String == parts[1] }) else { return ("no request \(parts[1])", true) }
            var x = r
            x["imgs"] = (r["imgs"] as? [String] ?? []).map { (board as NSString).appendingPathComponent($0) }
            out["request"] = x
        case "task":
            let (tasks, runs) = TaskStore.raw(board)
            guard let t = tasks.first(where: { $0["id"] as? String == parts[1] }) else { return ("no task \(parts[1])", true) }
            out["task"] = t
            out["runs"] = Array(runs.filter { $0["task"] as? String == parts[1] }.sorted { ($0["started"] as? String ?? "") > ($1["started"] as? String ?? "") }.prefix(8))
            if let e = t["every"] as? String, let s = TaskSchedule(e) { out["schedule"] = s.describe }
        default:
            return ("unknown ref kind; use test:, choice:, req:, road:, track:, reqs:, request:, task:", true)
        }
        return (jsonString(out), false)
    }
}
