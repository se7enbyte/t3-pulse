import AppKit
import SwiftUI
import SQLite3

enum JobState: String {
    case working, waiting, completed, failed, stopped, idle
    init(_ raw: String) {
        switch raw {
        case "preparing", "queued", "starting", "running", "working", "in_progress": self = .working
        case "waiting", "waiting_for_input", "waiting_for_approval", "blocked": self = .waiting
        case "completed", "succeeded", "done": self = .completed
        case "failed", "error": self = .failed
        case "interrupted", "cancelled", "rolled_back": self = .stopped
        default: self = .idle
        }
    }
    var label: String {
        switch self { case .working: return "Çalışıyor"; case .waiting: return "Sizi bekliyor"
        case .completed: return "Tamamlandı"; case .failed: return "Hata"; case .stopped: return "Durduruldu"; case .idle: return "Hazır" }
    }
    var color: NSColor {
        switch self { case .working: return .systemBlue; case .waiting: return .systemOrange
        case .completed: return .systemGreen; case .failed: return .systemRed; default: return .secondaryLabelColor }
    }
    var symbol: String {
        switch self { case .working: return "circle.dotted"; case .waiting: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"; case .failed: return "exclamationmark.circle.fill"
        case .stopped: return "stop.circle"; case .idle: return "circle" }
    }
    var priority: Int {
        switch self { case .waiting: return 0; case .working: return 1; case .failed: return 2
        case .completed: return 3; case .stopped: return 4; case .idle: return 5 }
    }
}

struct Job: Identifiable {
    let id: String
    let threadID: String
    let title: String
    let detail: String
    let state: JobState
    let started: Date?
    let ended: Date?
    let isSubagent: Bool
    var timeLabel: String {
        guard let started else { return "" }
        let seconds = max(0, Int((ended ?? Date()).timeIntervalSince(started)))
        if seconds < 60 { return "\(seconds) sn" }
        if seconds < 3600 { return "\(seconds / 60) dk" }
        return "\(seconds / 3600) sa \((seconds % 3600) / 60) dk"
    }
}

enum StoreError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { if case .unavailable(let message) = self { return message }; return nil }
}

struct Store {
    let path: String
    static func date(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    func read() throws -> [Job] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            throw StoreError.unavailable("T3 Code veritabanı açılamadı.")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 400)
        func query(_ sql: String) throws -> [[String: String]] {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw StoreError.unavailable("T3 Code veri şeması okunamadı.")
            }
            defer { sqlite3_finalize(statement) }
            var rows = [[String: String]]()
            var code = sqlite3_step(statement)
            while code == SQLITE_ROW {
                var row = [String: String]()
                for i in 0..<sqlite3_column_count(statement) {
                    if let value = sqlite3_column_text(statement, i) {
                        row[String(cString: sqlite3_column_name(statement, i))] = String(cString: value)
                    }
                }
                rows.append(row)
                code = sqlite3_step(statement)
            }
            guard code == SQLITE_DONE else { throw StoreError.unavailable("T3 Code verileri şu an okunamıyor.") }
            return rows
        }
        // Live activity takes priority over newer cancelled/queued requests.
        // Fall back to the latest run when no active work remains.
        let threads = try query("""
        SELECT t.thread_id AS id,t.title,t.payload_json,
               COALESCE(r.status,'idle') AS status,r.requested_at,r.completed_at,
               r.payload_json AS run_payload,
               COALESCE(p.title,'T3 Code') AS project,
               COALESCE(t.provider_instance_id,t.default_provider) AS provider,
               (SELECT COUNT(*) FROM orchestration_v2_projection_runtime_requests q
                WHERE q.thread_id=t.thread_id AND q.status='pending'
                AND q.kind != 'auth_refresh'
                AND (q.kind != 'user_input' OR COALESCE(json_extract(q.payload_json,'$.blocking'),1) != 0
                     OR COALESCE(r.status,'idle') NOT IN ('preparing','starting','running'))) AS pending
        FROM orchestration_v2_projection_threads t
        LEFT JOIN projection_projects p ON p.project_id=t.project_id
        LEFT JOIN orchestration_v2_projection_runs r ON r.run_id=(
          SELECT rr.run_id FROM orchestration_v2_projection_runs rr
          WHERE rr.thread_id=t.thread_id
          ORDER BY CASE WHEN rr.status IN ('preparing','starting','running','waiting') THEN 0
                        WHEN rr.status='queued' THEN 1 ELSE 2 END,
                   rr.ordinal DESC LIMIT 1)
        WHERE t.deleted_at IS NULL AND t.archived_at IS NULL
        ORDER BY t.updated_at DESC
        """)
        let cutoff = Date().addingTimeInterval(-86400)
        var jobs = [Job]()
        for row in threads {
            let payload = (row["payload_json"]?.data(using: .utf8)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
            let run = (row["run_payload"]?.data(using: .utf8)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
            var state = JobState(row["status"] ?? "idle")
            if Int(row["pending"] ?? "0") ?? 0 > 0 { state = .waiting }
            let started = Store.date(run["startedAt"] as? String ?? row["requested_at"])
            let ended = Store.date(row["completed_at"])
            let active = state == .working || state == .waiting
            guard active || (ended ?? started ?? .distantPast) > cutoff else { continue }
            if !active && payload["settledOverride"] as? String == "settled" { continue }
            let selection = payload["modelSelection"] as? [String: Any]
            let model = selection?["model"] as? String ?? row["provider"] ?? "Ajan"
            let lineage = payload["lineage"] as? [String: Any]
            jobs.append(Job(id: row["id"]!, threadID: row["id"]!, title: row["title"] ?? "İsimsiz iş",
                            detail: "\(row["project"] ?? "T3 Code") · \(model)", state: state,
                            started: started, ended: ended, isSubagent: lineage?["relationshipToParent"] as? String == "subagent"))
        }
        // Native subagents without a visible child thread need their own row.
        let children = try query("""
        SELECT s.subagent_id AS id,s.thread_id,s.child_thread_id,s.status,s.started_at,s.completed_at,
               s.payload_json,s.provider,t.title
        FROM orchestration_v2_projection_subagents s
        JOIN orchestration_v2_projection_threads t ON t.thread_id=s.thread_id
        WHERE t.deleted_at IS NULL AND t.archived_at IS NULL
        AND (s.child_thread_id IS NULL OR s.child_thread_id='')
        ORDER BY s.updated_at DESC
        """)
        for row in children {
            let state = JobState(row["status"] ?? "idle")
            let started = Store.date(row["started_at"]), ended = Store.date(row["completed_at"])
            guard state == .working || state == .waiting || (ended ?? started ?? .distantPast) > cutoff else { continue }
            let payload = (row["payload_json"]?.data(using: .utf8)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
            let name = payload["name"] as? String ?? payload["title"] as? String ?? "Alt ajan"
            jobs.append(Job(id: row["id"]!, threadID: row["thread_id"]!, title: name,
                            detail: "\(row["title"] ?? "") · \(row["provider"] ?? "")", state: state,
                            started: started, ended: ended, isSubagent: true))
        }
        return jobs.sorted {
            if $0.state.priority != $1.state.priority { return $0.state.priority < $1.state.priority }
            return ($0.ended ?? $0.started ?? .distantPast) > ($1.ended ?? $1.started ?? .distantPast)
        }
    }
}

final class Monitor: ObservableObject {
    @Published var jobs = [Job]()
    @Published var error: String?
    @Published var online = true
    @Published var updated: Date?
    @Published var sound = UserDefaults.standard.bool(forKey: "completionSound")
    private var timer: Timer?
    private var reading = false
    private var previous = [String: JobState]()
    var changed: (() -> Void)?
    let store: Store
    init() {
        let root = ProcessInfo.processInfo.environment["T3CODE_HOME"] ?? NSHomeDirectory() + "/.t3"
        store = Store(path: root + "/userdata/statev2.sqlite")
    }
    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }
    func refresh() {
        guard !reading else { return }
        reading = true
        let store = store
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try store.read() }
            DispatchQueue.main.async { [self] in
                reading = false
                online = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.t3tools.t3code" }
                switch result {
                case .success(let fresh):
                    if sound && online && fresh.contains(where: { $0.state == .completed && [.working, .waiting].contains(previous[$0.id]) }) {
                        NSSound(named: "Glass")?.play()
                    }
                    previous = Dictionary(uniqueKeysWithValues: fresh.map { ($0.id, $0.state) })
                    jobs = fresh; error = nil; updated = Date()
                case .failure(let failure): error = failure.localizedDescription
                }
                changed?()
            }
        }
    }
    var working: Int { jobs.filter { $0.state == .working }.count }
    var waiting: Int { jobs.filter { $0.state == .waiting }.count }
    var completed: Int { jobs.filter { $0.state == .completed }.count }
    var failed: Int { jobs.filter { $0.state == .failed }.count }
}

struct StatusGlyph: View {
    let state: JobState
    @State private var spinning = false
    var body: some View {
        Image(systemName: state.symbol)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(Color(nsColor: state.color))
            .rotationEffect(.degrees(state == .working && spinning ? 360 : 0))
            .animation(state == .working ? .linear(duration: 3).repeatForever(autoreverses: false) : nil, value: spinning)
            .onAppear { spinning = true }
            .frame(width: 26, height: 26)
            .accessibilityLabel(state.label)
    }
}

struct PulsePanel: View {
    @ObservedObject var monitor: Monitor
    let openT3: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path").font(.title2).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("T3 Pulse").font(.system(size: 17, weight: .semibold))
                    Text(monitor.online ? "Ajanlar ve işler · canlı" : "T3 Code kapalı · son bilinen durum")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(monitor.error != nil ? .red : monitor.online ? .green : .gray).frame(width: 7, height: 7)
            }.padding(18)
            HStack(spacing: 18) {
                counter("Çalışan", monitor.working, .blue)
                counter("Bekleyen", monitor.waiting, .orange)
                counter("Tamamlanan", monitor.completed, .green)
                counter("Hata", monitor.failed, .red)
            }.padding(.horizontal, 18).padding(.bottom, 16)
            Divider()
            if let error = monitor.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).padding(18)
            } else if monitor.jobs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text("Şu anda aktif iş yok").font(.headline)
                    Text("Yeni işler burada otomatik görünür.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(monitor.jobs) { job in
                            HStack(alignment: .center, spacing: 10) {
                                StatusGlyph(state: job.state)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 5) {
                                        if job.isSubagent { Image(systemName: "arrow.triangle.branch").foregroundStyle(.secondary) }
                                        Text(job.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    }
                                    Text(job.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(job.state.label).foregroundStyle(Color(nsColor: job.state.color))
                                    Text(job.timeLabel).foregroundStyle(.secondary).monospacedDigit()
                                }.font(.system(size: 10))
                            }.padding(.horizontal, 16).padding(.vertical, 11)
                            Divider().padding(.leading, 52)
                        }
                    }
                }.frame(maxHeight: 340)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Toggle("İş tamamlanınca ses çal", isOn: $monitor.sound)
                    .toggleStyle(.checkbox).font(.system(size: 11))
                    .onChange(of: monitor.sound) { _, value in UserDefaults.standard.set(value, forKey: "completionSound") }
                HStack {
                    Text("2 sn’de yenilenir · son 24 saat").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button("T3 Code’u aç", action: openT3).controlSize(.small)
                    Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                        .buttonStyle(.plain).help("T3 Pulse’tan çık")
                }
            }.padding(14)
        }.frame(width: 430)
    }
    func counter(_ title: String, _ number: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(number)").font(.system(size: 23, weight: .semibold, design: .rounded)).foregroundStyle(color)
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = Monitor()
    var item: NSStatusItem!
    let popover = NSPopover()
    var animationTimer: Timer?
    var phase: CGFloat = 0
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PulsePanel(monitor: monitor, openT3: { [weak self] in self?.openT3() }))
        monitor.changed = { [weak self] in self?.drawStatus() }
        monitor.start()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self, monitor.working > 0, monitor.online, monitor.error == nil else { return }
            phase += 0.11; drawStatus()
        }
        drawStatus()
        if CommandLine.arguments.contains("--show") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.toggle() } }
    }
    func drawStatus() {
        var groups: [(JobState, Int)] = []
        if monitor.error != nil { groups = [(.failed, 0)] }
        else if !monitor.online { groups = [(.idle, 0)] }
        else {
            if monitor.working > 0 { groups.append((.working, monitor.working)) }
            if monitor.waiting > 0 { groups.append((.waiting, monitor.waiting)) }
            if monitor.completed > 0 { groups.append((.completed, monitor.completed)) }
            if monitor.failed > 0 { groups.append((.failed, monitor.failed)) }
            if groups.isEmpty { groups = [(.idle, 0)] }
        }
        let widths = groups.map { CGFloat($0.1 > 0 ? 31 + max(0, String($0.1).count - 1) * 7 : 21) }
        let width = widths.reduce(4, +)
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { [self] _ in
            var x: CGFloat = 2
            for (index, group) in groups.enumerated() {
                let (state, count) = group
                let center = NSPoint(x: x + 8, y: 11)
                state.color.setStroke()
                if state == .working {
                    for segment in 0..<9 {
                        let angle = CGFloat(segment) * .pi * 2 / 9 + phase
                        let path = NSBezierPath()
                        path.appendArc(withCenter: center, radius: 6.5, startAngle: angle * 180 / .pi, endAngle: angle * 180 / .pi + 21)
                        path.lineWidth = 1.7; path.lineCapStyle = .round; path.stroke()
                    }
                } else {
                    let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                    if let symbol = NSImage(systemSymbolName: state.symbol, accessibilityDescription: state.label)?.withSymbolConfiguration(config) {
                        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
                            symbol.draw(in: rect); state.color.setFill(); rect.fill(using: .sourceIn); return true
                        }
                        tinted.draw(in: NSRect(x: x, y: 3, width: 16, height: 16))
                    }
                }
                if count > 0 {
                    ("\(count)" as NSString).draw(at: NSPoint(x: x + 19, y: 4), withAttributes: [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.labelColor])
                }
                x += widths[index]
            }
            return true
        }
        image.isTemplate = false
        item.button?.image = image
        item.button?.setAccessibilityLabel("T3 Pulse: \(monitor.working) çalışan, \(monitor.waiting) bekleyen, \(monitor.completed) tamamlanan, \(monitor.failed) hata")
        item.button?.toolTip = monitor.error ?? (monitor.online ? "T3 Pulse · \(monitor.working) çalışan · \(monitor.completed) tamamlanan" : "T3 Code kapalı")
    }
    @objc func toggle() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            monitor.refresh()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    func openT3() {
        popover.performClose(nil)
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.t3tools.t3code")
            ?? URL(fileURLWithPath: "/Applications/T3 Code (Beta).app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

if CommandLine.arguments.contains("--check") {
    do {
        let monitor = Monitor()
        let jobs = try monitor.store.read()
        for job in jobs { print("\(job.state.rawValue)\t\(job.title)\t\(job.timeLabel)") }
        print("OK: \(jobs.count) iş; salt okunur bağlantı.")
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
