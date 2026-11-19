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
         "description": "Put finished, tested work on the To test tab (same fields as deliver.mjs: id, title, area, status, what, tested[], howTo[], tests[{label,url,check,img,focus?}], shots[{img,caption,focus?}], issues[], repos[], road: <exact roadmap item text> or a list, choices: [ids of the choices this builds], reqs: [ids of the requirements this delivery meets]). Always set road so Steerify can mark the roadmap when the user approves, choices when you built a choice (it then stops offering Build my pick), and reqs so the user's OK marks those requirements built. Same id = new version. what = 2–4 bullet lines (\"- Export button on Orders\\n- Uses your filters\"), each ≤ 6 words, no prose. Pictures full size and on the feature: crop each test picture to the feature at 2× (Retina), or give focus: [x,y,w,h] 0–1; never a whole window. Tests short and visual.",
         "inputSchema": schema(["item": ["type": "object"]], ["item"])],
        ["name": "ask_choice",
         "description": "Add a choice for the user to board.json decisions: {id, areas[], tags[], title, why, options:[{id,label,rec,points[],mock|shot|proto}]} with 2–4 options and exactly one rec:true. For UI choices use proto: a live prototype built with the project kit, \"protos/<choice id>.html?v=<A|B|C>\" (see kit/README.md in the board). Keep building what does not depend on it.",
         "inputSchema": schema(["decision": ["type": "object"]], ["decision"])],
        ["name": "set_roadmap_status",
         "description": "Set the status of a roadmap item (todo | wip | review | done | you). item = exact text or its slug. Mark done only with evidence (approved delivery, commit, deploy).",
         "inputSchema": schema(["item": str, "status": ["type": "string", "enum": ["todo", "wip", "review", "done", "you"]]], ["item", "status"])],
        ["name": "set_requirement_status",
         "description": "Set a requirement's status in board.json after checking the code: built (verified in the code, with evidence) | proposed | question. Never use it to answer for the user; their verdicts live in decisions.json.",
         "inputSchema": schema(["id": str, "status": ["type": "string", "enum": ["built", "proposed", "question"]], "evidence": str], ["id", "status"])],
        ["name": "set_release_config",
         "description": "Write this project's release setup into steerify.json: {repos:{<repo>:{branch, deploy?, liveCheck?}}, notes?}. The Release tab updates at once.",
         "inputSchema": schema(["release": ["type": "object"]], ["release"])],
        ["name": "add_roadmap_item",
         "description": "Add a key result to a roadmap chapter: {chapter (exact name), text, status? (todo), area?, request? (request id it comes from), for? (the feature chapter a fix belongs to), create? (true: create the chapter if missing)}. Fixes and small refinements go to the rolling chapter \"Fixes & refinements\".",
         "inputSchema": schema(["chapter": str, "text": str, "status": str, "area": str, "request": str, "for": str, "create": ["type": "boolean"]], ["chapter", "text"])],
        ["name": "add_chapter",
         "description": "Draft a new roadmap chapter for a feature request: {name, area, objective (one line), items: [key result texts], requirements?: [{id, text}], request? (request id)}. It lands as a DRAFT: the user approves it (Add to roadmap) or discards it in Steerify. Open questions go on the board with ask_choice.",
         "inputSchema": schema(["name": str, "area": str, "objective": str, "items": ["type": "array", "items": ["type": "string"]],
                                "requirements": ["type": "array", "items": ["type": "object"]], "request": str], ["name", "items"])],
        ["name": "update_request",
         "description": "Record what a request became: {id, status (working | done | needs-you | discarded), became? [board refs: road:<slug>, track:<slug>, choice:<id>, test:<id>], note? (one line)}. Keeps the request history in Steerify honest.",
         "inputSchema": schema(["id": str, "status": str, "became": ["type": "array", "items": ["type": "string"]], "note": str], ["id"])],
        ["name": "notify",
         "description": "Tell the user in the Steerify window (a toast), optionally jumping to an item. Use after delivering, when a choice is waiting, or when you need them.",
         "inputSchema": schema(["message": str, "ref": str], ["message"])],
    ]

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
            guard let item = a["item"] as? [String: Any] else { return ("item is required", true) }
            let r = node(board, "deliver.mjs", [jsonString(item)])
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
                for (const t of b.tracks || []) for (const it of t.items || []) if (it[0] === want || slug(it[0]) === slug(want)) {
                  it[1] = st; hit = it[0];
                  if (it[2] && typeof it[2] === 'object') { if (st === 'done') it[2].doneAt = new Date().toISOString().slice(0,10); else delete it[2].doneAt }
                }
                if (!hit) throw new Error('No roadmap item ' + want);
                out = st + ': ' + hit;
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
        case "add_roadmap_item":
            guard let ch = a["chapter"] as? String, let text = a["text"] as? String, !text.isEmpty else { return ("chapter and text are required", true) }
            var meta: [String: Any] = [:]
            if let r = a["request"] as? String, !r.isEmpty { meta["req"] = r; meta["at"] = String(RequestLog.now().prefix(10)) }
            if let f = a["for"] as? String, !f.isEmpty { meta["for"] = f }
            if let ar = a["area"] as? String, !ar.isEmpty { meta["area"] = ar }
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
            guard let name = a["name"] as? String, !name.isEmpty, let items = a["items"] as? [String], !items.isEmpty else { return ("name and items are required", true) }
            let reqs = a["requirements"] as? [[String: Any]] ?? []
            let day = String(RequestLog.now().prefix(10))
            let r = editBoard(board, """
                const name = \(jsonString(name)), area = \(jsonString(a["area"] as? String ?? "")), obj = \(jsonString(a["objective"] as? String ?? ""));
                const items = \(jsonString(items)), reqs = \(jsonString(reqs)), req = \(jsonString(a["request"] as? String ?? ""));
                b.tracks = b.tracks || [];
                if (b.tracks.some(t => t.name === name && !t.draft)) throw new Error('Chapter already on the roadmap: ' + name);
                b.tracks = b.tracks.filter(t => t.name !== name);
                const t = { name, area: area || undefined, draft: true, items: items.map(x => [x, 'todo']) };
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
            guard let id = a["id"] as? String else { return ("id is required", true) }
            let ok = RequestLog.edit(board, id: id) { r in
                if let st = a["status"] as? String { r["status"] = st }
                if let bc = a["became"] as? [String] { r["became"] = Array(NSOrderedSet(array: (r["became"] as? [String] ?? []) + bc)) }
                if let n = a["note"] as? String { r["note"] = n }
                r["updated"] = RequestLog.now()
            }
            if !ok { return ("no request \(id)", true) }
            ui(["action": "refresh", "board": board])
            return ("request \(id) updated", false)
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
        case "choice":
            guard let d = (b["decisions"] as? [[String: Any]] ?? []).first(where: { $0["id"] as? String == parts[1] }) else { return ("no choice \(parts[1])", true) }
            var slim = d; slim["options"] = (d["options"] as? [[String: Any]] ?? []).map { o in o.filter { $0.key != "mock" } }
            out["choice"] = slim; out["answer"] = dec[parts[1]] ?? NSNull()
            out["how_to_read_the_answer"] = "pick = the chosen option id (__note = the note is the answer); mix = other option ids to blend into it; note = how (and anything else). Multi-choices: pick is a list."
        case "req":
            for g in b["requirements"] as? [[String: Any]] ?? [] {
                if let r = (g["items"] as? [[String: Any]] ?? []).first(where: { $0["id"] as? String == parts[1] }) { out["requirement"] = r; out["group"] = g["h"] }
            }
            out["verdict"] = dec["req:" + parts[1]] ?? NSNull()
        case "track":
            guard let t = (b["tracks"] as? [[String: Any]] ?? []).first(where: { BoardFiles.slug(($0["name"] as? String) ?? "") == parts[1] || ($0["name"] as? String) == parts[1] })
            else { return ("no roadmap chapter \(parts[1])", true) }
            out["chapter"] = t["name"]; out["area"] = t["area"] ?? NSNull()
            out["items"] = (t["items"] as? [[Any]] ?? []).map { ["text": $0.first ?? "", "status": $0.count > 1 ? $0[1] : "todo"] }
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
        default:
            return ("unknown ref kind; use test:, choice:, req:, track:, reqs:, request:", true)
        }
        return (jsonString(out), false)
    }
}
