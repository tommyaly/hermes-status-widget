import Foundation
import Observation
import os.log
#if canImport(WidgetKit)
import WidgetKit
#endif

private let logger = Logger(subsystem: "local.hermes.statuswidget", category: "StatusStore")

@MainActor
@Observable
final class StatusStore {
    var snapshot: HermesSnapshot = .empty
    var cumulativeRange: CumulativeRange

    private let reader: HermesStatusReading

    init(reader: HermesStatusReading = LocalHermesStatusReader()) {
        self.reader = reader
        self.cumulativeRange = CumulativeRange.load()
    }

    @MainActor
    func refresh() async {
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try await self.reader.readSnapshot(cumulativeRange: self.cumulativeRange)
            }.value
            snapshot = result
            WidgetSnapshotStore.write(snapshot)
            logger.info("Snapshot refreshed successfully: gateway=\(self.snapshot.gateway.state), isRunning=\(self.snapshot.gateway.isRunning)")
            reloadWidgetTimelines()
        } catch {
            logger.error("readSnapshot failed: \(error.localizedDescription)")
            var next = HermesSnapshot.empty
            next.error = error.localizedDescription
            next.refreshedAt = Date()
            snapshot = next
            WidgetSnapshotStore.write(next)
            reloadWidgetTimelines()
        }
    }

    func setCumulativeRange(_ range: CumulativeRange) {
        cumulativeRange = range
        range.save()
        Task {
            await refresh()
        }
    }

    private func reloadWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "HermesAgentStatusWidget")
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

protocol HermesStatusReading: Sendable {
    func readSnapshot(cumulativeRange: CumulativeRange) async throws -> HermesSnapshot
}

enum CumulativeRange: String, CaseIterable, Identifiable, Equatable {
    case sevenDays
    case thirtyDays
    case ninetyDays
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sevenDays:
            return "近 7 天"
        case .thirtyDays:
            return "近 30 天"
        case .ninetyDays:
            return "近 90 天"
        case .all:
            return "全部"
        }
    }

    var since: Date? {
        switch self {
        case .sevenDays:
            return Date().addingTimeInterval(-7 * 86_400)
        case .thirtyDays:
            return Date().addingTimeInterval(-30 * 86_400)
        case .ninetyDays:
            return Date().addingTimeInterval(-90 * 86_400)
        case .all:
            return nil
        }
    }

    private static let defaultsKey = "cumulativeRange"

    static func load() -> CumulativeRange {
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? CumulativeRange.all.rawValue
        return CumulativeRange(rawValue: raw) ?? .all
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}
