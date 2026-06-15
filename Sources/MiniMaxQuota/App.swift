import SwiftUI
import AppKit

@main
struct MiniMaxQuotaApp: App {
    // Both the menu bar popup and the floating window must observe the same
    // QuotaStore, so the timer in start() updates both surfaces. The previous
    // design had a separate `QuotaStore.shared` for the floating window whose
    // start() was never called, so it stayed frozen on its first snapshot.
    private static let sharedStore: QuotaStore = {
        let s = QuotaStore()
        s.start()  // boot the timer eagerly so the UI is never blank
        return s
    }()
    @StateObject private var store = MiniMaxQuotaApp.sharedStore
    @StateObject private var floating = FloatingWindowController(store: MiniMaxQuotaApp.sharedStore)

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store, floating: floating)
                .environmentObject(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The little glyph + number that lives in the system menu bar.
private struct MenuBarLabel: View {
    @ObservedObject var store: QuotaStore

    var body: some View {
        // SF Symbol chosen for legibility at 18pt menu-bar size.
        // The trailing number is the lowest interval % across active models.
        HStack(spacing: 2) {
            Image(systemName: "chart.bar.xaxis")
            if let worst = activeWorstPercent(store.quotas) {
                Text("\(worst)")
                    .monospacedDigit()
            }
        }
    }

    private func activeWorstPercent(_ qs: [ModelQuota]) -> Int? {
        guard !qs.isEmpty else { return nil }
        return qs.map(\.intervalRemainingPercent).min()
    }
}

/// The popup that appears when the user clicks the menu bar icon.
struct MenuContent: View {
    @ObservedObject var store: QuotaStore
    @ObservedObject var floating: FloatingWindowController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let err = store.lastError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }

            if !store.quotas.isEmpty {
                ForEach(store.quotas) { q in
                    QuotaRow(quota: q)
                }
            } else if store.lastError == nil {
                Text("加载中…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else if store.lastError?.contains("mmx") == true {
                // Friendlier install hint when the failure looks like a missing mmx.
                VStack(alignment: .leading, spacing: 4) {
                    Text("需要安装 mmx CLI:")
                        .font(.system(size: 11, weight: .semibold))
                    Text("brew install mmx-cli")
                        .font(.system(size: 11, design: .monospaced))
                    Text("或")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("npm install -g mmx-cli")
                        .font(.system(size: 11, design: .monospaced))
                    Text("然后: mmx auth login --api-key <你的key>")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Divider().padding(.vertical, 6)

            HStack(spacing: 8) {
                Button(floating.isVisible ? "隐藏悬浮窗" : "显示悬浮窗") {
                    floating.toggle()
                }
                .buttonStyle(.borderless)

                Spacer()

                Menu {
                    Button("15 秒") { store.setRefreshInterval(15) }
                    Button("30 秒") { store.setRefreshInterval(30) }
                    Button("1 分钟") { store.setRefreshInterval(60) }
                    Button("5 分钟") { store.setRefreshInterval(300) }
                } label: {
                    Text(refreshIntervalLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button("立即刷新") {
                    Task { await store.refresh() }
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("r")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            if let t = store.lastUpdated {
                Text("更新于 \(t.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

            Divider().padding(.vertical, 4)

            HStack {
                Spacer()
                Button("退出") {
                    // MenuBarExtra apps have no built-in quit affordance.
                    // NSApp.terminate kills the process; the timer in
                    // QuotaStore stops via the deactivation path.
                    NSApp.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Text("MiniMax 配额")
                .font(.headline)
            Spacer()
            Text(store.quotas.isEmpty ? "—" : "\(store.quotas.count) 项")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    /// Label for the refresh-interval menu. Single source of truth so the
    /// popup and the actual timer stay in sync.
    private var refreshIntervalLabel: String {
        switch store.refreshInterval {
        case ..<60:    return "每 \(Int(store.refreshInterval)) 秒"
        case 60..<300: return "每分钟"
        default:       return "每 \(Int(store.refreshInterval / 60)) 分钟"
        }
    }
}

struct QuotaRow: View {
    let quota: ModelQuota

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Header: model name (with window-length badge) on the left.
            HStack {
                Text(quota.displayName)
                    .font(.system(size: 12, weight: .semibold))
                Text("· \(quota.intervalWindowLabel)周期")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            // Hourly pool: 进度条 + 剩余百分比 + 倒计时 + 周期起止.
            HStack {
                Text("小时")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .leading)
                Text("\(quota.intervalRemainingPercent)%")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(color(for: quota.intervalRemainingPercent))
                    .frame(width: 36, alignment: .trailing)
            }
            ProgressView(value: Double(quota.intervalRemainingPercent), total: 100)
                .progressViewStyle(.linear)
                .tint(color(for: quota.intervalRemainingPercent))
            HStack {
                Text(windowLabel(start: quota.intervalStart, end: quota.intervalEnd))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("剩 \(intervalRemainLabel)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            // Weekly pool: 进度条 + 剩余百分比 + 倒计时 + 周期起止.
            HStack {
                Text("周")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .leading)
                Text("\(quota.weeklyRemainingPercent)%")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(color(for: quota.weeklyRemainingPercent))
                    .frame(width: 36, alignment: .trailing)
            }
            ProgressView(value: Double(quota.weeklyRemainingPercent), total: 100)
                .progressViewStyle(.linear)
                .tint(color(for: quota.weeklyRemainingPercent))
            HStack {
                Text(windowLabel(start: quota.weeklyStart, end: quota.weeklyEnd))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("剩 \(weeklyRemainLabel)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// "20:00 → 00:00" — local 24h time. Short and scannable.
    private func windowLabel(start: Date, end: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return "\(f.string(from: start)) → \(f.string(from: end))"
    }

    private var intervalRemainLabel: String {
        let mins = max(0, quota.intervalRemainsMs / 60_000)
        let h = mins / 60
        let m = mins % 60
        if h > 0 && m > 0 { return "\(h)小时\(m)分" }
        if h > 0          { return "\(h)小时" }
        return "\(m)分"
    }

    private var weeklyRemainLabel: String {
        let mins = max(0, quota.weeklyRemainsMs / 60_000)
        let d = mins / (60 * 24)
        let h = (mins % (60 * 24)) / 60
        let m = mins % 60
        if d > 0 { return "\(d)天\(h)小时" }
        if h > 0 { return "\(h)小时\(m)分" }
        return "\(m)分"
    }

    private func color(for percent: Int) -> Color {
        switch percent {
        case ..<10:  return .red
        case ..<30:  return .orange
        default:     return .green
        }
    }
}
