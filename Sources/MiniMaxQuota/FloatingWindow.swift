import SwiftUI
import AppKit

/// A frameless, always-on-top, draggable card that mirrors the menu-bar popup data.
/// Owned by the App scene; the menu bar popup toggles it via `toggle()`.
///
/// `store` is injected from the App scene (the same instance the menu bar
/// observes) so both surfaces show identical data and update from the same
/// timer. Previously this controller had its own `QuotaStore.shared`
/// singleton whose `start()` was never called, leaving the floating window
/// frozen on its first-render snapshot until the user clicked "refresh".
@MainActor
final class FloatingWindowController: ObservableObject {
    @Published private(set) var isVisible: Bool = false
    private let store: QuotaStore
    private var window: NSWindow?

    init(store: QuotaStore) {
        self.store = store
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        if window == nil { window = makeWindow() }
        guard let w = window else { return }
        if w.frame.origin == .zero {
            // first-show placement: top-right of the main screen, with margin
            if let screen = NSScreen.main {
                let sz = w.frame.size
                let margin: CGFloat = 24
                w.setFrameOrigin(NSPoint(
                    x: screen.visibleFrame.maxX - sz.width - margin,
                    y: screen.visibleFrame.maxY - sz.height - margin
                ))
            }
        }
        w.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        window?.orderOut(nil)
        isVisible = false
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 140),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.backgroundColor = .clear
        w.hasShadow = true
        w.contentView = NSHostingView(rootView: FloatingCardView(store: store))
        return w
    }
}

/// Compact, always-on-top card. Mirrors the menu content but smaller.
struct FloatingCardView: View {
    // @ObservedObject (not @EnvironmentObject) so SwiftUI registers a
    // subscription on QuotaStore and re-renders the NSHostingView whenever
    // the store changes. @EnvironmentObject did not propagate updates into
    // the NSHostingView's backing layer, leaving the floating window frozen.
    @ObservedObject var store: QuotaStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "chart.bar.xaxis")
                Text("MiniMax 配额")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
            }

            Divider()

            if store.quotas.isEmpty && store.lastError == nil {
                Text("加载中…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if let err = store.lastError {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(3)
            } else {
                ForEach(store.quotas) { q in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("\(q.displayName)·\(q.intervalWindowLabel)周期")
                                .font(.system(size: 10, weight: .semibold))
                            Spacer()
                        }
                        HStack(spacing: 4) {
                            Text("时")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .frame(width: 12, alignment: .leading)
                            Text("\(q.intervalRemainingPercent)%")
                                .font(.system(size: 9, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(color(for: q.intervalRemainingPercent))
                                .frame(width: 32, alignment: .trailing)
                            ProgressView(value: Double(q.intervalRemainingPercent), total: 100)
                                .progressViewStyle(.linear)
                                .tint(color(for: q.intervalRemainingPercent))
                        }
                        HStack(spacing: 4) {
                            Text("周")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .frame(width: 12, alignment: .leading)
                            Text("\(q.weeklyRemainingPercent)%")
                                .font(.system(size: 9, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(color(for: q.weeklyRemainingPercent))
                                .frame(width: 32, alignment: .trailing)
                            ProgressView(value: Double(q.weeklyRemainingPercent), total: 100)
                                .progressViewStyle(.linear)
                                .tint(color(for: q.weeklyRemainingPercent))
                        }
                        HStack {
                            Text(intervalCycleLabel(q))
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text(weeklyCycleLabel(q))
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .padding(10)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 0.5)
        )
    }

    private func color(for percent: Int) -> Color {
        switch percent {
        case ..<10:  return .red
        case ..<30:  return .orange
        default:     return .green
        }
    }

    private func shortTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }

    /// Compact cycle for the floating card: just end-times of each window.
    private func intervalCycleLabel(_ q: ModelQuota) -> String {
        let mins = max(0, q.intervalRemainsMs / 60_000)
        let h = mins / 60
        let m = mins % 60
        let in_: String
        if h > 0 { in_ = "\(h)小时\(m)分" } else { in_ = "\(m)分" }
        return "时→\(shortTime(q.intervalEnd)) 剩\(in_)"
    }

    private func weeklyCycleLabel(_ q: ModelQuota) -> String {
        let mins = max(0, q.weeklyRemainsMs / 60_000)
        let d = mins / (60 * 24)
        let h = (mins % (60 * 24)) / 60
        let in_: String
        if d > 0 { in_ = "\(d)天\(h)小时" } else if h > 0 { in_ = "\(h)小时" } else { in_ = "\(mins)分" }
        return "周→\(shortTime(q.weeklyEnd)) 剩\(in_)"
    }
}
