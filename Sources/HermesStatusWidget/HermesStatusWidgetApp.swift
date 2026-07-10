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
    private var launchWindow: NSWindow?
    private var timer: Timer?

    func start() {
        setupStatusItem()
        setupPopover()
        setupLaunchGuide()
        Task { @MainActor in
            refresh()
        }

        let refreshTimer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        timer = refreshTimer
        RunLoop.main.add(refreshTimer, forMode: .common)
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
        popover.contentSize = NSSize(width: HermesStatusPanelView.panelWidth, height: HermesStatusPanelView.panelHeight)

        self.popover = popover
    }

    private func setupLaunchGuide() {
        let rootView = HermesLaunchGuideView()
            .environment(\.closeHermesLaunchGuide, { [weak self] in
                Task { @MainActor in
                    self?.launchWindow?.close()
                }
            })

        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Hermes 状态小组件"
        window.contentViewController = hosting
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()

        launchWindow = window
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
        statusItem?.button?.title = " \(status)"
    }
}

private struct RefreshHermesStatusKey: EnvironmentKey {
    static let defaultValue: @Sendable () -> Void = {}
}

private struct QuitHermesStatusWidgetKey: EnvironmentKey {
    static let defaultValue: @Sendable () -> Void = {}
}

private struct CloseHermesLaunchGuideKey: EnvironmentKey {
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

    var closeHermesLaunchGuide: @Sendable () -> Void {
        get { self[CloseHermesLaunchGuideKey.self] }
        set { self[CloseHermesLaunchGuideKey.self] = newValue }
    }
}
