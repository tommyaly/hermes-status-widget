import Foundation
import Observation

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

    func refresh() async {
        do {
            snapshot = try await reader.readSnapshot(cumulativeRange: cumulativeRange)
        } catch {
            var next = HermesSnapshot.empty
            next.error = error.localizedDescription
            next.refreshedAt = Date()
            snapshot = next
        }
    }

    func setCumulativeRange(_ range: CumulativeRange) {
        cumulativeRange = range
        range.save()
        Task {
            await refresh()
        }
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
