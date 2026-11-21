import SwiftUI
import AppKit

// MARK: - Tasks: work Claude does for you, not code
//
// Choices tasks-place (a Tasks tab), tasks-name ("Tasks") and tasks-schedule (result-based, not "a session starts"):
// a task is an OUTCOME to reach with your tools and SOPs — a tutorial, a data collection, a report — once or on a
// schedule. It never goes on the roadmap. A run is done only when Claude hands in the result (MCP finish_task:
// summary, files, counts, each check met or not) and you check it (OK / Redo). Steerify watches every run:
// no result by its deadline, or the session gone without one → "No result", with Retry. A slot missed while the Mac
// slept or the app was closed runs as soon as Steerify is back ("late").
//
// <board>/tasks.json  {"steerify":1, "tasks":[…], "runs":[…]}   (written by Steerify and by Claude through the MCP)

struct BoardTask: Identifiable, Hashable {
    let id: String
    let title: String
    let brief: String
    let outcome: String           // what "done" looks like
    let checks: [String]          // how to tell the result is right
    let sop: String?              // the standard / skill / doc it follows
    let every: String?            // "mon 08:00", "mon,thu 09:30", "daily 08:00", "weekdays 08:00"; nil = once
    let maxMinutes: Int           // a run without a result after this long is "No result"
    let area: String?
    let request: String?
    let created: String
    let paused: Bool
    var schedule: TaskSchedule? { every.flatMap(TaskSchedule.init) }
}

struct TaskCheck: Hashable { let text: String; let ok: Bool }

/// The report standard (choice task-report-standard): what Claude fills in with finish_task `report`, drawn the same
/// way for every task and every run, so a result reads at a glance and compares week to week.
struct TaskReport: Hashable {
    struct Kpi: Hashable { let value: String; let label: String }
    struct Step: Hashable { let text: String; let n: String; let done: Bool }
    struct Row: Hashable { let name: String; let value: Double; let ref: Double?; let show: String; let tag: String }
    let headline: String          // ≤ 10 words: what you got
    let kpis: [Kpi]               // 2–4 big numbers
    let steps: [Step]             // what was done, 3–6, each with a count; done or pending
    let rowsTitle: String         // what the bars measure
    let refLabel: String          // what the reference mark is ("competitor avg")
    let rows: [Row]               // one per item: bar, value vs reference, a 2–3 word tag
    let points: [String]          // key points, max 3
    let details: String?          // the full file, kept folded

    init?(_ o: Any?) {
        guard let o = o as? [String: Any] else { return nil }
        func str(_ v: Any?) -> String { if let s = v as? String { return s }; if let n = v as? NSNumber { return n.stringValue }; return "" }
        func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue ?? (v as? String).flatMap { Double($0) } }
        headline = str(o["headline"])
        kpis = (o["kpis"] as? [[String: Any]] ?? []).prefix(4).map { Kpi(value: str($0["value"]), label: str($0["label"])) }
        steps = (o["steps"] as? [[String: Any]] ?? []).prefix(6).map { Step(text: str($0["text"]), n: str($0["n"]), done: $0["done"] as? Bool ?? true) }
        let r = o["rows"] as? [String: Any] ?? [:]
        rowsTitle = str(r["title"]); refLabel = str(r["ref"])
        rows = (r["items"] as? [[String: Any]] ?? []).prefix(12).compactMap { i in
            guard let v = num(i["value"]) else { return nil }
            return Row(name: str(i["name"]), value: v, ref: num(i["ref"]), show: str(i["show"]).isEmpty ? str(i["value"]) : str(i["show"]), tag: str(i["tag"]))
        }
        points = (o["points"] as? [String] ?? []).prefix(3).map { $0 }
        details = (o["details"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        if headline.isEmpty && kpis.isEmpty && steps.isEmpty && rows.isEmpty && points.isEmpty { return nil }
    }
}

struct TaskRun: Identifiable, Hashable {
    let id: String
    let task: String
    let status: String            // running | done (to check) | ok | redo | noresult
    let due: String?              // the schedule slot it is for
    let started: String
    let deadline: String?
    let finished: String?
    let session: String?          // Claude session id
    let term: String?             // Steerify terminal id (STEERIFY_SESSION)
    let summary: String
    let files: [String]
    let counts: [String]          // "records: 412"
    let checks: [TaskCheck]
    let late: Bool
    let why: String?              // no result: why
    let note: String?             // your Redo note
    let report: TaskReport?       // the standard report, when Claude filled it in
    var checksFailed: Int { checks.filter { !$0.ok }.count }
}

/// Every Monday 08:00, weekdays 09:30, daily 07:00… parsed from a short line (English, a few Italian words).
struct TaskSchedule: Hashable {
    let days: Set<Int>            // Calendar weekdays, 1 = Sunday
    let hour: Int, minute: Int

    static let names: [(String, Int)] = [("sun", 1), ("dom", 1), ("mon", 2), ("lun", 2), ("tue", 3), ("mar", 3), ("wed", 4), ("mer", 4),
                                         ("thu", 5), ("gio", 5), ("fri", 6), ("ven", 6), ("sat", 7), ("sab", 7)]

    init?(_ line: String) {
        let s = line.lowercased().replacingOccurrences(of: "every", with: " ").replacingOccurrences(of: "ogni", with: " ")
        var h = 9, m = 0
        if let r = s.range(of: #"\b(\d{1,2})[:.](\d{2})\b"#, options: .regularExpression) {
            let p = s[r].split(whereSeparator: { $0 == ":" || $0 == "." }).compactMap { Int($0) }
            if p.count == 2, p[0] < 24, p[1] < 60 { h = p[0]; m = p[1] }
        }
        var d = Set<Int>()
        if s.contains("daily") || s.contains("day ") || s.hasSuffix("day") && !s.contains("weekday") || s.contains("giorno") { d = Set(1...7) }
        if s.contains("weekday") || s.contains("feriali") { d = Set(2...6) }
        if d.isEmpty {
            for w in s.split(whereSeparator: { !$0.isLetter }) {
                if let n = Self.names.first(where: { w.hasPrefix($0.0) })?.1 { d.insert(n) }
            }
        }
        guard !d.isEmpty else { return nil }
        days = d; hour = h; minute = m
    }

    private func slot(_ day: Date) -> Date? { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) }

    func next(after d: Date) -> Date? {
        let cal = Calendar.current
        for k in 0...7 {
            guard let day = cal.date(byAdding: .day, value: k, to: d), let c = slot(day) else { continue }
            if c > d && days.contains(cal.component(.weekday, from: c)) { return c }
        }
        return nil
    }

    func last(atOrBefore d: Date) -> Date? {
        let cal = Calendar.current
        for k in 0...7 {
            guard let day = cal.date(byAdding: .day, value: -k, to: d), let c = slot(day) else { continue }
            if c <= d && days.contains(cal.component(.weekday, from: c)) { return c }
        }
        return nil
    }

    var describe: String {
        let t = String(format: "%02d:%02d", hour, minute)
        if days.count == 7 { return "every day \(t)" }
        if days == Set(2...6) { return "weekdays \(t)" }
        let n = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return "every " + days.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }.map { n[$0] }.joined(separator: ", ") + " \(t)"
    }
}

/// tasks.json, shared by the app and the MCP (same binary, `--mcp`).
enum TaskStore {
    static let fileName = "tasks.json"
    static let defaultMinutes = 120
    static func file(_ dir: String) -> String { (dir as NSString).appendingPathComponent(fileName) }

    static func raw(_ dir: String) -> (tasks: [[String: Any]], runs: [[String: Any]]) {
        let o = BoardFiles.json(dir, fileName) as? [String: Any] ?? [:]
        return (o["tasks"] as? [[String: Any]] ?? [], o["runs"] as? [[String: Any]] ?? [])
    }

    static func load(_ dir: String) -> (tasks: [BoardTask], runs: [TaskRun]) {
        let r = raw(dir)
        let tasks = r.tasks.map { t in
            BoardTask(id: s(t["id"]), title: s(t["title"]), brief: s(t["brief"]), outcome: s(t["outcome"]),
                      checks: t["checks"] as? [String] ?? [], sop: t["sop"] as? String, every: (t["every"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                      maxMinutes: t["maxMinutes"] as? Int ?? defaultMinutes, area: t["area"] as? String, request: t["request"] as? String,
                      created: s(t["created"]), paused: t["paused"] as? Bool ?? false)
        }
        let runs = r.runs.map { u in
            let res = u["result"] as? [String: Any] ?? [:]
            let counts: [String] = (res["counts"] as? [String: Any] ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
            let checks = (res["checks"] as? [[String: Any]] ?? []).map { TaskCheck(text: s($0["text"]), ok: $0["ok"] as? Bool ?? false) }
            return TaskRun(id: s(u["id"]), task: s(u["task"]), status: s(u["status"]), due: u["due"] as? String, started: s(u["started"]),
                           deadline: u["deadline"] as? String, finished: u["finished"] as? String, session: u["session"] as? String,
                           term: u["term"] as? String, summary: s(res["summary"]), files: res["files"] as? [String] ?? [], counts: counts,
                           checks: checks, late: u["late"] as? Bool ?? false, why: u["why"] as? String, note: u["note"] as? String,
                           report: TaskReport(res["report"]))
        }
        return (tasks, runs.sorted { $0.started > $1.started })
    }

    /// Read-modify-write of the whole file (small; one writer at a time in practice). Returns false if it could not write.
    @discardableResult
    static func edit(_ dir: String, _ change: (inout [[String: Any]], inout [[String: Any]]) -> Void) -> Bool {
        var (t, r) = raw(dir)
        change(&t, &r)
        // Keep the history readable: the last 60 runs per task.
        var per: [String: Int] = [:]
        r = r.sorted { s($0["started"]) > s($1["started"]) }.filter { u in per[s(u["task"]), default: 0] += 1; return per[s(u["task"])]! <= 60 }
        let o: [String: Any] = ["steerify": 1, "tasks": t, "runs": r]
        guard let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return false }
        return (try? d.write(to: URL(fileURLWithPath: file(dir)), options: .atomic)) != nil
    }

    static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    static let isoPlain: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
    static func now() -> String { iso.string(from: Date()) }
    static func string(_ d: Date) -> String { iso.string(from: d) }
    static func date(_ s: String?) -> Date? { s.flatMap { iso.date(from: $0) ?? isoPlain.date(from: $0) } }

    static func runId(_ task: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyMMdd-HHmmss"; f.locale = Locale(identifier: "en_US_POSIX")
        return task + "@" + f.string(from: Date())
    }

    /// A new run record (status running). Returns its id.
    static func addRun(_ dir: String, task: String, due: Date?, late: Bool, session: String?, term: String?, note: String?) -> String? {
        let t = load(dir).tasks.first { $0.id == task }
        let id = runId(task)
        let mins = t?.maxMinutes ?? defaultMinutes
        let ok = edit(dir) { _, runs in
            var u: [String: Any] = ["id": id, "task": task, "status": "running", "started": now(),
                                    "deadline": string(Date().addingTimeInterval(Double(mins) * 60))]
            if let due { u["due"] = string(due) }
            if late { u["late"] = true }
            if let session { u["session"] = session }
            if let term { u["term"] = term }
            if let note, !note.isEmpty { u["note"] = note }
            runs.append(u)
        }
        return ok ? id : nil
    }

    static func setRun(_ dir: String, id: String, _ change: (inout [String: Any]) -> Void) {
        edit(dir) { _, runs in if let i = runs.firstIndex(where: { s($0["id"]) == id }) { change(&runs[i]) } }
    }

    static func setTask(_ dir: String, id: String, _ change: (inout [String: Any]) -> Void) {
        edit(dir) { tasks, _ in if let i = tasks.firstIndex(where: { s($0["id"]) == id }) { change(&tasks[i]) } }
    }

    /// One line per task for board_summary.
    static func summary(_ dir: String) -> [String] {
        let (tasks, runs) = load(dir)
        return tasks.map { t in
            let last = runs.first { $0.task == t.id }
            let when = t.schedule?.describe ?? "once"
            return "- task:\(t.id) — \(t.title) (\(when)\(t.paused ? ", paused" : "")) · last run: " + (last.map { "\($0.status) \($0.started.prefix(16))" } ?? "none")
        }
    }

    private static func s(_ v: Any?) -> String { (v as? String) ?? "" }
}

// MARK: - The clock: runs on schedule, watches results (no polling: one timer to the next event)

@MainActor
final class TaskClock {
    static let shared = TaskClock()
    var timer: Timer?
    var told = Set<String>()        // runs already reported as "No result"
    var observing = false
    /// Test copies run it only with `--scratch-writes --dry-sessions` (sessions print their command instead of starting).
    static var enabled: Bool {
        let a = CommandLine.arguments
        let real = ProcessInfo.processInfo.environment["STEERIFY_TEST_REAL_SESSIONS"] == "1"   // a test copy allowed real sessions (Remote Control test)
        return AppModel.mayWriteBoards && (!a.contains("--background") || a.contains("--dry-sessions") || real)
    }
}

@MainActor
extension AppModel {
    func startTaskClock() {
        let c = TaskClock.shared
        guard !c.observing else { return }
        c.observing = true
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.taskTick() }
        }
        NotificationCenter.default.addObserver(forName: .steerifyBoardReloaded, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.taskTick() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.taskTick() }   // sessions restored first
    }

    /// Start what is due, close what has no result, then sleep until the next due slot or deadline.
    func taskTick() {
        guard TaskClock.enabled else { return }
        let now = Date()
        var wake: Date? = nil
        func soon(_ d: Date?) { if let d, d > now { wake = min(wake ?? d, d) } }
        for p in projects where FileManager.default.fileExists(atPath: TaskStore.file(p.boardDir)) {
            let (tasks, runs) = TaskStore.load(p.boardDir)
            // 1 · Watch running runs: a result is the only way out; no result by the deadline (or no session) is reported.
            for r in runs where r.status == "running" {
                let started = TaskStore.date(r.started) ?? now
                let deadline = TaskStore.date(r.deadline) ?? started.addingTimeInterval(Double(TaskStore.defaultMinutes) * 60)
                let alive = sessions.contains { s in s.running && ((r.session != nil && s.claudeId == r.session) || (r.term != nil && s.id.uuidString == r.term)) }
                var why: String? = nil
                if now >= deadline { why = "No result after \(Int(deadline.timeIntervalSince(started) / 60)) min" }
                else if !alive && now.timeIntervalSince(started) > 180 { why = "The session ended without a result" }
                if let why {
                    TaskStore.setRun(p.boardDir, id: r.id) { $0["status"] = "noresult"; $0["why"] = why; $0["finished"] = TaskStore.now() }
                    if !TaskClock.shared.told.contains(r.id) {
                        TaskClock.shared.told.insert(r.id)
                        let title = tasks.first { $0.id == r.task }?.title ?? r.task
                        showToast("Task “\(title)”: \(why.lowercased())", projectId: p.id, ref: "task:" + r.task)
                        Notify.send("No result: \(title)", why)
                    }
                } else { soon(deadline) }
            }
            // 2 · Scheduled tasks: the latest slot that has passed and has no run yet starts now (late if > 10 min).
            for t in tasks where !t.paused {
                guard let sch = t.schedule else { continue }
                let created = TaskStore.date(t.created) ?? .distantPast
                if let slot = sch.last(atOrBefore: now), slot > created,
                   !runs.contains(where: { $0.task == t.id && (TaskStore.date($0.due).map { abs($0.timeIntervalSince(slot)) < 60 } ?? false
                                                               || (TaskStore.date($0.started) ?? .distantPast) >= slot) }) {
                    runTask(projectId: p.id, taskId: t.id, due: slot, late: now.timeIntervalSince(slot) > 600, focus: false)
                }
                soon(sch.next(after: now))
            }
        }
        TaskClock.shared.timer?.invalidate()
        if let wake {
            let t = Timer(fire: wake.addingTimeInterval(1), interval: 0, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.taskTick() } }
            t.tolerance = 5
            RunLoop.main.add(t, forMode: .common)
            TaskClock.shared.timer = t
        }
    }

    /// Start one run of a task: a run record (with its deadline), then a fresh session briefed with the outcome.
    @discardableResult
    func runTask(projectId: String, taskId: String, due: Date? = nil, late: Bool = false, note: String? = nil, focus: Bool = true) -> String? {
        guard let p = projects.first(where: { $0.id == projectId }),
              let t = TaskStore.load(p.boardDir).tasks.first(where: { $0.id == taskId }) else { return nil }
        let dry = CommandLine.arguments.contains("--dry-sessions")
        guard let runId = TaskStore.addRun(p.boardDir, task: t.id, due: due, late: late, session: nil, term: nil, note: note) else {
            showToast("Couldn't start “\(t.title)”: tasks.json is not writable", projectId: p.id); return nil
        }
        var item = ItemRef(ref: "task:" + t.id)!
        item.title = t.title; item.area = t.area
        var brief = ["TASK RUN \(runId) — \"\(t.title)\"" + (due.map { " (scheduled \(TaskStore.string($0).prefix(16)))" } ?? "") + (late ? " · started late, the Mac was away at the slot" : ""),
                     "Outcome (what done looks like): \(t.outcome)"]
        if !t.checks.isEmpty { brief.append("Checks:\n" + t.checks.map { "- " + $0 }.joined(separator: "\n")) }
        if let sop = t.sop { brief.append("Follow: \(sop)") }
        if !t.brief.isEmpty { brief.append("Brief:\n\(t.brief)") }
        if let note, !note.isEmpty { brief.append("The user sent the last result back (Redo): \"\(note)\"") }
        brief.append("Follow the steerify skill, intent `run`. You have \(t.maxMinutes) min. Finish with finish_task (run \(runId)): summary, files, counts, every check ok or not, and the report (headline, 2–4 kpis, steps done, rows per item, ≤ 3 points; minimal text, details in the file). No finish_task = the run shows \"No result\".")
        let s = start(projectId: p.id, item: item, intent: .run, dry: dry, extraBrief: brief.joined(separator: "\n\n"), focus: focus, fresh: true)
        TaskStore.setRun(p.boardDir, id: runId) { r in
            if let cid = s?.claudeId { r["session"] = cid }
            if let s { r["term"] = s.id.uuidString }
        }
        board(for: p).reload()
        return runId
    }

    func setRunVerdict(projectId: String, run: TaskRun, ok: Bool, note: String?) {
        guard let p = projects.first(where: { $0.id == projectId }) else { return }
        TaskStore.setRun(p.boardDir, id: run.id) { r in
            r["status"] = ok ? "ok" : "redo"; r["checked"] = TaskStore.now()
            if let note, !note.isEmpty { r["verdictNote"] = note }
        }
        if !ok { runTask(projectId: projectId, taskId: run.task, note: note) }
        board(for: p).reload()
    }
}

// MARK: - The Tasks tab: Now · To check · Scheduled · Ready · Done

struct TasksScreen: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    @State private var selected: String?      // run id whose report is open
    @State private var closed = false         // you closed the report panel

    var body: some View {
        let _ = board.loadedAt
        let (tasks, runs) = TaskStore.load(board.project.boardDir)
        let byId = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let now = runs.filter { $0.status == "running" }
        let check = runs.filter { $0.status == "done" || $0.status == "noresult" }
        let scheduled = tasks.filter { $0.schedule != nil }
        let ready = tasks.filter { t in t.schedule == nil && !runs.contains { $0.task == t.id } }
        let done = runs.filter { r in (r.status == "ok") && byId[r.task]?.schedule == nil }.prefix(12)
        // The report panel: the run you clicked, else the first result to check that has a report.
        let open: TaskRun? = closed ? nil
            : (runs.first { $0.id == selected && $0.report != nil } ?? check.first { $0.report != nil && $0.status == "done" })
        GeometryReader { g in
            // Room for list + report side by side? Otherwise the report opens under its card.
            let wide = g.size.width >= S(960)
            let row = { (r: TaskRun) in
                VStack(spacing: 0) {
                    RunRow(board: board, run: r, task: byId[r.task], selected: open?.id == r.id) {
                        if open?.id == r.id { closed = true } else { selected = r.id; closed = false }
                    }
                    if !wide, open?.id == r.id {
                        TaskReportPanel(board: board, run: r, task: byId[r.task], inline: true) { closed = true }
                            .background(RoundedRectangle(cornerRadius: 8).fill(Brand.bg))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.line))
                            .padding(.top, 6)
                    }
                }
            }
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if tasks.isEmpty {
                            EmptyBoard(projectId: board.project.id, title: "NO TASKS YET", line: "Ask for an outcome, not a feature: a tutorial, a report, a weekly collection.", kind: .task)
                        } else {
                            HStack {
                                Text("Things Claude does for you, with your tools and your standards. Not code: they never go on the roadmap.")
                                    .font(.system(size: S(12))).foregroundStyle(Brand.mute)
                                Spacer()
                                ActionButton(title: "+ Task", icon: "task") { model.requestKindSeed = .task; model.requestOpen = true }
                                    .help("Describe the outcome you want; Claude sets up the task and runs it")
                            }
                        }
                        if !now.isEmpty { group("NOW") { ForEach(now) { r in row(r) } } }
                        if !check.isEmpty { group("TO CHECK") { ForEach(check) { r in row(r) } } }
                        if !scheduled.isEmpty { group("SCHEDULED") { ForEach(scheduled) { t in TaskRow(board: board, task: t, runs: runs.filter { $0.task == t.id }) } } }
                        if !ready.isEmpty { group("READY TO RUN") { ForEach(ready) { t in TaskRow(board: board, task: t, runs: []) } } }
                        if !done.isEmpty { group("DONE") { ForEach(Array(done)) { r in row(r) } } }
                    }
                    .padding(12)
                }
                .frame(width: wide && open != nil ? S(460) : g.size.width).clipped()
                if wide, let r = open {
                    Rectangle().fill(Brand.line).frame(width: 1)
                    ScrollView {
                        TaskReportPanel(board: board, run: r, task: byId[r.task], inline: false) { closed = true }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Brand.bg)
    }

    @ViewBuilder private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        Text(title).font(Brand.label(10.5)).tracking(1.6).foregroundStyle(Brand.mute).padding(.top, 8).padding(.leading, 2)
        content()
    }
}

private func taskCard<C: View>(_ hl: Color? = nil, selected: Bool = false, @ViewBuilder _ c: () -> C) -> some View {
    c().padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Brand.panel2 : Brand.panel))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(hl ?? (selected ? Brand.cream.opacity(0.5) : Brand.line), lineWidth: selected ? 2 : 1))
}

private func clock(_ iso: String?) -> String {
    guard let d = TaskStore.date(iso) else { return "" }
    let f = DateFormatter()
    f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "EEE d MMM HH:mm"
    return f.string(from: d)
}

/// One run: running (with its deadline), to check (result + OK / Redo), no result (Retry), done.
struct RunRow: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    let run: TaskRun
    let task: BoardTask?
    var selected = false
    var onSelect: () -> Void = {}
    @State private var redo = false
    @State private var note = ""

    var body: some View {
        let ref = "task:" + run.task
        let tint: Color? = run.status == "done" ? Brand.amber : run.status == "noresult" ? Brand.red : nil
        let rep = run.report.flatMap { _ in run.status == "done" || run.status == "ok" ? run.report : nil }
        taskCard(tint, selected: selected) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    Text(icon).font(.system(size: S(14), weight: .bold)).frame(width: S(26), height: S(26))
                        .background(RoundedRectangle(cornerRadius: 6).fill(Brand.panel2)).foregroundStyle(tint ?? Brand.cream)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task?.title ?? run.task).font(.system(size: S(13.5), weight: .semibold)).foregroundStyle(Brand.cream)
                        if let rep, !rep.headline.isEmpty {
                            Text(rep.headline).font(.system(size: S(12))).foregroundStyle(Brand.ink).lineLimit(2)
                        } else {
                            Text(subtitle).font(.system(size: S(11.5))).foregroundStyle(Brand.mute).lineLimit(2)
                        }
                    }
                    .frame(minWidth: S(140), alignment: .leading).layoutPriority(1)
                    Spacer(minLength: 8)
                    if rep == nil { status; actions(ref).fixedSize() }
                    else if run.status == "ok" { status }
                    else { Text(clock(run.finished)).font(.system(size: S(11.5))).foregroundStyle(Brand.mute) }
                }
                if let rep {
                    if !rep.kpis.isEmpty { KpiTiles(kpis: rep.kpis, big: false) }
                    HStack(spacing: 8) {
                        if !run.checks.isEmpty { ChecksBar(checks: run.checks) }
                        Spacer(minLength: 4)
                        if run.status == "done" { actions(ref).fixedSize() }
                    }
                } else if run.status == "done" || run.status == "ok", !(run.summary.isEmpty && run.files.isEmpty && run.counts.isEmpty) { result }
                if redo {
                    HStack {
                        TextField("What should be different?", text: $note).textFieldStyle(.roundedBorder).font(.system(size: S(12)))
                            .onSubmit { send(false) }
                        ActionButton(title: "Redo", icon: "task", primary: true) { send(false) }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if rep != nil { onSelect() } }
        .help(rep != nil ? (selected ? "Close the report" : "Open the report") : "")
        .id(ref + "@" + run.id).flash(ref)
    }

    private var icon: String { ["running": "▶", "done": "✓", "noresult": "!", "ok": "✓", "redo": "↺"][run.status] ?? "·" }

    private var subtitle: String {
        var parts: [String] = []
        if let o = task?.outcome, !o.isEmpty { parts.append(o) }
        if let s = task?.sop { parts.append("follows " + s) }
        if run.late { parts.append("started late") }
        if let n = run.note { parts.append("redo: “\(n)”") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var status: some View {
        switch run.status {
        case "running":
            let left = TaskStore.date(run.deadline).map { max(0, Int($0.timeIntervalSinceNow / 60)) }
            pill("RUNNING" + (left.map { " · \($0) MIN LEFT" } ?? ""), Brand.claude)
        case "done":
            if run.checksFailed > 0 { pill("\(run.checksFailed) CHECK\(run.checksFailed == 1 ? "" : "S") FAILED", Brand.red) }
            Text("finished " + clock(run.finished)).font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
        case "noresult": pill((run.why ?? "No result").uppercased(), Brand.red)
        case "ok": Text("OK · " + clock(run.finished)).font(.system(size: S(11.5))).foregroundStyle(Brand.green)
        default: EmptyView()
        }
    }

    @ViewBuilder private func actions(_ ref: String) -> some View {
        switch run.status {
        case "running":
            ActionButton(title: "Jump to session", icon: "term") { model.openCombo(projectId: board.project.id, ref: ref, startNew: false) }
        case "done":
            ActionButton(title: "OK", icon: "test", primary: true) { model.setRunVerdict(projectId: board.project.id, run: run, ok: true, note: nil) }
            ActionButton(title: "Redo", icon: "task") { redo.toggle() }
        case "noresult":
            ActionButton(title: "Retry", icon: "task", primary: true) {
                TaskStore.setRun(board.project.boardDir, id: run.id) { $0["status"] = "retried" }
                model.runTask(projectId: board.project.id, taskId: run.task)
            }
            ActionButton(title: "Session", icon: "term") { model.openCombo(projectId: board.project.id, ref: ref, startNew: false) }
        default: EmptyView()
        }
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !run.summary.isEmpty { Text(run.summary).font(.system(size: S(12))).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true) }
            if !run.counts.isEmpty {
                HStack(spacing: 6) { ForEach(run.counts, id: \.self) { c in pill(c, Brand.blue) } }
            }
            if !run.checks.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(run.checks, id: \.self) { c in
                        Text((c.ok ? "✓ " : "✗ ") + c.text).font(.system(size: S(11.5))).foregroundStyle(c.ok ? Brand.green : Brand.red)
                    }
                }
            }
            if !run.files.isEmpty {
                HStack(spacing: 10) {
                    ForEach(run.files, id: \.self) { f in
                        Button { open(f) } label: { Text("↗ " + (f.hasPrefix("http") ? f : (f as NSString).lastPathComponent)).font(.system(size: S(11.5))).underline() }
                            .buttonStyle(.plain).foregroundStyle(Brand.cream).pointerStyle(.link)
                    }
                }
            }
        }
        .padding(.leading, S(38))
    }

    private func open(_ f: String) { openTaskFile(f, board: board.project.boardDir) }

    private func send(_ ok: Bool) {
        model.setRunVerdict(projectId: board.project.id, run: run, ok: ok, note: note)
        redo = false; note = ""
    }
}

/// A task itself: its schedule, its run history (one bar per run), Run now, Pause.
struct TaskRow: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    let task: BoardTask
    let runs: [TaskRun]

    var body: some View {
        let ref = "task:" + task.id
        taskCard {
            HStack(alignment: .top, spacing: 12) {
                Text(task.schedule == nil ? "▶" : "↻").font(.system(size: S(14), weight: .bold)).frame(width: S(26), height: S(26))
                    .background(RoundedRectangle(cornerRadius: 6).fill(Brand.panel2)).foregroundStyle(Brand.cream)
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).font(.system(size: S(13.5), weight: .semibold)).foregroundStyle(Brand.cream)
                    Text(([task.schedule?.describe ?? "once", task.outcome] + (task.sop.map { ["follows " + $0] } ?? [])).filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: S(11.5))).foregroundStyle(Brand.mute).lineLimit(2)
                }
                Spacer(minLength: 8)
                if !runs.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(runs.prefix(10).reversed()) { r in
                            RoundedRectangle(cornerRadius: 2).fill(color(r)).frame(width: S(9), height: S(14))
                                .help("\(clock(r.started)) · \(label(r))")
                        }
                    }
                }
                if let sch = task.schedule {
                    Text(task.paused ? "paused" : "next: " + clock(sch.next(after: Date()).map(TaskStore.string)))
                        .font(.system(size: S(11.5))).foregroundStyle(task.paused ? Brand.amber : Brand.mute)
                    ActionButton(title: task.paused ? "Resume" : "Pause", icon: "task") {
                        TaskStore.setTask(board.project.boardDir, id: task.id) { $0["paused"] = !task.paused }
                        board.reload()
                    }
                }
                ActionButton(title: "Run now", icon: "play", primary: task.schedule == nil) { model.runTask(projectId: board.project.id, taskId: task.id) }
            }
        }
        .id(ref).flash(ref)
    }

    private func color(_ r: TaskRun) -> Color {
        switch r.status { case "ok": Brand.green; case "done": Brand.amber; case "noresult", "redo", "retried": Brand.red; case "running": Brand.claude; default: Brand.line2 }
    }
    private func label(_ r: TaskRun) -> String {
        ["ok": "OK", "done": "to check", "noresult": r.why ?? "no result", "redo": "sent back", "retried": "no result, retried", "running": "running"][r.status] ?? r.status
    }
}

private func pill(_ text: String, _ c: Color) -> some View {
    Text(text).font(Brand.label(9)).tracking(0.6).foregroundStyle(c).lineLimit(1)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(c.opacity(0.7), lineWidth: 1)).fixedSize()
}

private func openTaskFile(_ f: String, board: String) {
    if f.hasPrefix("http"), let u = URL(string: f) { NSWorkspace.shared.open(u); return }
    let path = f.hasPrefix("/") ? f : (board as NSString).appendingPathComponent(f)
    NSWorkspace.shared.open(URL(fileURLWithPath: path))
}

private func fileName(_ f: String) -> String { f.hasPrefix("http") ? f : (f as NSString).lastPathComponent }

/// 2–4 big numbers, same width each.
struct KpiTiles: View {
    let kpis: [TaskReport.Kpi]
    let big: Bool
    var body: some View {
        HStack(spacing: 8) {
            ForEach(kpis, id: \.self) { k in
                VStack(alignment: .leading, spacing: 2) {
                    Text(k.value).font(.system(size: S(big ? 24 : 18), weight: .bold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                    Text(k.label.uppercased()).font(Brand.label(8.5)).tracking(0.4).foregroundStyle(Brand.mute).lineLimit(1).minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 10).padding(.vertical, big ? 9 : 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7).fill(big ? Brand.panel : Brand.bg.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Brand.line))
            }
        }
    }
}

/// One segment per check: green met, red not; then "4/5 checks".
struct ChecksBar: View {
    let checks: [TaskCheck]
    var body: some View {
        let ok = checks.filter(\.ok).count
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(Array(checks.enumerated()), id: \.offset) { _, c in
                    RoundedRectangle(cornerRadius: 2).fill(c.ok ? Brand.green : Brand.red).frame(width: S(14), height: S(6)).help(c.text)
                }
            }
            Text("\(ok)/\(checks.count) checks").font(.system(size: S(11.5))).foregroundStyle(ok == checks.count ? Brand.green : Brand.red)
        }
    }
}

/// The report, drawn by Steerify from the standard Claude fills in: headline, KPIs, what was done, one bar per item,
/// key points, the file folded under Details.
struct TaskReportPanel: View {
    @ObservedObject var board: BoardStore
    let run: TaskRun
    let task: BoardTask?
    var inline = false
    let close: () -> Void
    @State private var showChecks = false

    var body: some View {
        let r = run.report!
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if inline {
                        Text("REPORT").font(Brand.label(9.5)).tracking(1.4).foregroundStyle(Brand.mute)
                    } else {
                        Text(task?.title ?? run.task).font(.system(size: S(19), weight: .bold)).foregroundStyle(.white).lineLimit(2).layoutPriority(1)
                    }
                    Spacer(minLength: 8)
                    if !run.checks.isEmpty {
                        let bad = run.checksFailed
                        Button { showChecks.toggle() } label: {
                            Text(bad == 0 ? "\(run.checks.count)/\(run.checks.count) CHECKS" : "\(bad) CHECK\(bad == 1 ? "" : "S") FAILED")
                                .font(Brand.label(9)).tracking(0.6).foregroundStyle(bad == 0 ? Brand.green : Brand.red)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke((bad == 0 ? Brand.green : Brand.red).opacity(0.7)))
                                .lineLimit(1).fixedSize()
                        }.buttonStyle(.plain).help("Show the checks")
                    }
                    Text(when).font(.system(size: S(11.5))).foregroundStyle(Brand.mute).lineLimit(1).fixedSize()
                    Button(action: close) { Text("✕").font(.system(size: S(12), weight: .semibold)).foregroundStyle(Brand.mute) }
                        .buttonStyle(.plain).help("Close the report")
                }
                if !inline, !r.headline.isEmpty {
                    Text(r.headline).font(.system(size: S(13))).foregroundStyle(Brand.ink).padding(.top, -10)
                }
                if showChecks {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(run.checks, id: \.self) { c in
                            Text((c.ok ? "✓ " : "✗ ") + c.text).font(.system(size: S(11.5))).foregroundStyle(c.ok ? Brand.green : Brand.red)
                        }
                    }
                }
                if !inline, !r.kpis.isEmpty { KpiTiles(kpis: r.kpis, big: true) }   // inline: the card above already shows them
                if !r.steps.isEmpty {
                    section("WHAT WAS DONE")
                    timeline(r.steps)
                }
                if !r.rows.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        section("RESULT" + (r.rowsTitle.isEmpty ? "" : " · " + r.rowsTitle.uppercased()))
                        Spacer(minLength: 8)
                        if r.rows.contains(where: { $0.ref != nil }) {
                            Text("│ = " + (r.refLabel.isEmpty ? "reference" : r.refLabel)).font(.system(size: S(11))).foregroundStyle(Brand.mute).lineLimit(1).fixedSize()
                        }
                    }
                    bars(r.rows)
                }
                if !r.points.isEmpty {
                    section("KEY POINTS")
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(r.points, id: \.self) { p in
                            (Text("→ ").foregroundColor(Brand.amber) + Text(p).foregroundColor(Brand.ink)).font(.system(size: S(12.5)))
                        }
                    }
                }
                let files = (r.details.map { [$0] } ?? []) + run.files.filter { $0 != r.details }
                if !files.isEmpty {
                    HStack(spacing: 10) {
                        Text("▸ Details").font(.system(size: S(12))).foregroundStyle(Brand.mute)
                        Spacer(minLength: 4)
                        ForEach(files, id: \.self) { f in
                            Button { openTaskFile(f, board: board.project.boardDir) } label: {
                                Text("↗ " + fileName(f)).font(.system(size: S(11.5))).underline().lineLimit(1)
                            }.buttonStyle(.plain).foregroundStyle(Brand.cream).pointerStyle(.link)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Brand.line))
                }
            }
            .padding(.horizontal, inline ? 14 : 22).padding(.vertical, inline ? 12 : 18)
    }

    private var when: String {
        let fin = clock(run.finished)
        guard let a = TaskStore.date(run.started), let b = TaskStore.date(run.finished) else { return fin }
        let m = max(1, Int(b.timeIntervalSince(a) / 60))
        return fin + " · " + (m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min")
    }

    private func section(_ t: String) -> some View {
        Text(t).font(Brand.label(9.5)).tracking(1.4).foregroundStyle(Brand.mute).padding(.bottom, -6)
    }

    private func timeline(_ steps: [TaskReport.Step]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                VStack(spacing: 4) {
                    ZStack {
                        HStack(spacing: 0) {
                            Rectangle().fill(i == 0 ? .clear : Brand.green.opacity(0.55)).frame(height: 2)
                            Rectangle().fill(i == steps.count - 1 ? .clear : Brand.green.opacity(0.55)).frame(height: 2)
                        }
                        Circle().fill(s.done ? Brand.green : Brand.amber).frame(width: S(16), height: S(16))
                            .overlay(Text(s.done ? "✓" : "…").font(.system(size: S(9), weight: .heavy)).foregroundStyle(Color(hex: 0x06140b)))
                    }
                    Text(s.text).font(.system(size: S(11.5), weight: .semibold)).foregroundStyle(Brand.ink).multilineTextAlignment(.center).lineLimit(2)
                    if !s.n.isEmpty { Text(s.n.uppercased()).font(Brand.label(8.5)).tracking(0.4).foregroundStyle(Brand.mute).multilineTextAlignment(.center).lineLimit(2) }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func bars(_ rows: [TaskReport.Row]) -> some View {
        let top = max(1, rows.map { max($0.value, $0.ref ?? 0) }.max() ?? 1)
        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    Text(row.name).font(.system(size: S(12.5), weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Brand.panel2)
                            RoundedRectangle(cornerRadius: 3).fill(Brand.blue).frame(width: max(2, g.size.width * row.value / top))
                            if let ref = row.ref {
                                Rectangle().fill(Brand.cream.opacity(0.75)).frame(width: 2, height: S(18)).offset(x: min(g.size.width - 2, g.size.width * ref / top))
                            }
                        }
                    }
                    .frame(height: S(12)).frame(minWidth: S(120))
                    Text(row.show).font(.system(size: S(11.5), weight: .bold, design: .monospaced)).foregroundStyle(Brand.ink).lineLimit(1).fixedSize()
                    Text(row.tag).font(.system(size: S(12), weight: .semibold)).foregroundStyle(Brand.amber).lineLimit(1).fixedSize()
                }
            }
        }
    }
}
