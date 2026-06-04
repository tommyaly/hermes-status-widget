import AppKit
import SwiftUI

@main
struct HermesStatusWidgetApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let controller = AppController()
        app.delegate = controller
        controller.start()

        app.run()
    }
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let store = StatusStore()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var timer: Timer?

    func start() {
        setupStatusItem()
        setupPopover()
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "bolt.horizontal.circle", accessibilityDescription: "Hermes")
        item.button?.title = " Hermes"
        item.button?.action = #selector(togglePopover)
        item.button?.target = self

        statusItem = item
    }

    private func setupPopover() {
        let rootView = HermesStatusPanelView()
            .environment(store)
            .environment(\.refreshHermesStatus, { [weak self] in
                Task { @MainActor in
                    self?.refresh()
                }
            })
            .environment(\.quitHermesStatusWidget, {
                Task { @MainActor in
                    NSApplication.shared.terminate(nil)
                }
            })

        let hosting = NSHostingController(rootView: rootView)
        let popover = NSPopover()
        popover.contentViewController = hosting
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.contentSize = NSSize(width: 400, height: 500)

        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            refresh()
            NSApplication.shared.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func refresh() {
        Task {
            await store.refresh()
            updateStatusItemTitle()
        }
    }

    private func updateStatusItemTitle() {
        let snapshot = store.snapshot
        let status = snapshot.gateway.isRunning ? "运行中" : "离线"
        let tokens = formatMenuTokenCount(snapshot.tokenUsage.total)
        statusItem?.button?.title = " Hermes \(status) · \(tokens)"
    }

    private func formatMenuTokenCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

private struct RefreshHermesStatusKey: EnvironmentKey {
    static let defaultValue: @Sendable () -> Void = {}
}

private struct QuitHermesStatusWidgetKey: EnvironmentKey {
    static let defaultValue: @Sendable () -> Void = {}
}

extension EnvironmentValues {
    var refreshHermesStatus: @Sendable () -> Void {
        get { self[RefreshHermesStatusKey.self] }
        set { self[RefreshHermesStatusKey.self] = newValue }
    }

    var quitHermesStatusWidget: @Sendable () -> Void {
        get { self[QuitHermesStatusWidgetKey.self] }
        set { self[QuitHermesStatusWidgetKey.self] = newValue }
    }
}
