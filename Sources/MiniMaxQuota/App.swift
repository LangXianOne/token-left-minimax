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
    /// Cached on first appearance so we don't re-walk the disk on every
    /// menu-bar open. Recomputed only when the user clicks "重新检测".
    @State private var mmxInstalled: Bool = QuotaFetcher.isMmxInstalled()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store,
                        floating: floating,
                        mmxInstalled: mmxInstalled,
                        onRescanMmx: {
                            mmxInstalled = QuotaFetcher.isMmxInstalled()
                            Task { await store.refresh() }
                        })
                .environmentObject(store)
        } label: {
            MenuBarLabel(store: store, mmxInstalled: mmxInstalled)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The little glyph + number that lives in the system menu bar.
private struct MenuBarLabel: View {
    @ObservedObject var store: QuotaStore
    let mmxInstalled: Bool

    var body: some View {
        // SF Symbol chosen for legibility at 18pt menu-bar size.
        // The trailing number is the lowest interval % across active models.
        // When mmx is missing we show a warning glyph so users notice without
        // having to open the popup.
        HStack(spacing: 2) {
            Image(systemName: mmxInstalled ? "chart.bar.xaxis" : "exclamationmark.triangle")
                .foregroundStyle(mmxInstalled ? Color.primary : Color.orange)
            if mmxInstalled, let worst = activeWorstPercent(store.quotas) {
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
    let mmxInstalled: Bool
    let onRescanMmx: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            // First-run install prompt. Takes priority over everything else:
            // if mmx is missing, the quota data is meaningless anyway, so we
            // guide the user through install → login → verify before showing
            // the rest of the UI. A "我已安装,重新检测" button rescan the disk
            // for the binary (covers the case where the user installed it
            // in a separate terminal while the app was running).
            if !mmxInstalled {
                MmxInstallPrompt(onRescan: onRescanMmx)
            } else {
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
                }
            }

            Divider().padding(.vertical, 6)

            HStack(spacing: 8) {
                Button(floating.isVisible ? "隐藏悬浮窗" : "显示悬浮窗") {
                    floating.toggle()
                }
                .buttonStyle(.borderless)
                .disabled(!mmxInstalled)

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
                .disabled(!mmxInstalled)

                Button("立即刷新") {
                    Task { await store.refresh() }
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("r")
                .disabled(!mmxInstalled)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            if let t = store.lastUpdated {
                Text("更新于 \(t.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

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
        .padding(.vertical, 8)
        .frame(width: 340)
    }

    private var header: some View {
        HStack {
            Text("MiniMax 配额")
                .font(.headline)
            Spacer()
            if mmxInstalled {
                Text(store.quotas.isEmpty ? "—" : "\(store.quotas.count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("需要先安装 mmx")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
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

/// First-run install prompt. Renders the two install commands the user can
/// pick from, with one-click copy-to-clipboard, plus the login + verify
/// commands to run afterwards. Designed to be skim-readable so a first-time
/// user can install + log in without leaving the menu bar.
private struct MmxInstallPrompt: View {
    let onRescan: () -> Void
    /// Short-lived "Copied!" flash per row, so the user knows the click
    /// actually did something. Keyed by command id.
    @State private var copiedId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("首次运行 — 需要安装 mmx CLI")
                    .font(.system(size: 12, weight: .semibold))
            }

            Text("MiniMaxQuota 只是 mmx 的 GUI 壳,数据全部来自 `mmx quota show`。挑一种方式装:")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(QuotaFetcher.InstallCommand.primary) { cmd in
                CommandRow(
                    title: cmd.label,
                    note: cmd.note,
                    command: cmd.command,
                    copied: copiedId == cmd.id,
                    onCopy: {
                        copy(cmd.command, id: cmd.id)
                    }
                )
            }

            Divider().padding(.vertical, 2)

            Text("装好后:")
                .font(.system(size: 11, weight: .semibold))

            CommandRow(
                title: "登录账号",
                note: "OAuth 浏览器跳转,或直接粘 API key",
                command: QuotaFetcher.InstallCommand.loginCommand,
                copied: copiedId == "login",
                onCopy: {
                    copy(QuotaFetcher.InstallCommand.loginCommand, id: "login")
                }
            )

            CommandRow(
                title: "验证能拉到数据",
                note: "应输出若干行 quota,看到数据就 OK",
                command: QuotaFetcher.InstallCommand.verifyCommand,
                copied: copiedId == "verify",
                onCopy: {
                    copy(QuotaFetcher.InstallCommand.verifyCommand, id: "verify")
                }
            )

            Button {
                onRescan()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("我已安装,重新检测")
                }
                .font(.system(size: 11))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func copy(_ text: String, id: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        copiedId = id
        // Brief flash; the user sees the change.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedId == id { copiedId = nil }
        }
    }
}

/// One row of the install prompt: title + helper text + monospaced command
/// + a small "Copy" button. State for the "Copied!" flash lives on the parent
/// (MmxInstallPrompt) to keep the row itself dumb and re-render-friendly.
private struct CommandRow: View {
    let title: String
    let note: String
    let command: String
    let copied: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text("· \(note)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 6) {
                Text(command)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.15))
                    )
                    .textSelection(.enabled)
                Spacer()
                Button(action: onCopy) {
                    Text(copied ? "已复制" : "复制")
                        .font(.system(size: 10))
                        .frame(minWidth: 36)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
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
