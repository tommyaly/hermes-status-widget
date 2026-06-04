import Foundation

struct HermesSnapshot: Equatable {
    var gateway: GatewaySnapshot
    var activeSession: SessionSnapshot?
    var tokenUsage: TokenUsageSnapshot
    var allTimeTokenUsage: TokenUsageSnapshot
    var memory: MemorySnapshot
    var refreshedAt: Date
    var error: String?

    static let empty = HermesSnapshot(
        gateway: .offline,
        activeSession: nil,
        tokenUsage: .empty,
        allTimeTokenUsage: .empty,
        memory: .unknown,
        refreshedAt: Date(),
        error: nil
    )
}

struct GatewaySnapshot: Equatable {
    var isRunning: Bool
    var state: String
    var pid: Int?
    var activeAgents: Int
    var platforms: [PlatformSnapshot]
    var updatedAt: Date?

    static let offline = GatewaySnapshot(
        isRunning: false,
        state: "offline",
        pid: nil,
        activeAgents: 0,
        platforms: [],
        updatedAt: nil
    )
}

struct PlatformSnapshot: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var state: String
}

struct SessionSnapshot: Equatable {
    var id: String
    var source: String
    var model: String
    var title: String
    var lastActive: Date
    var isLive: Bool
    var inputTokens: Int
    var outputTokens: Int
}

struct TokenUsageSnapshot: Equatable {
    var total: Int
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheWrite: Int
    var reasoning: Int
    var byModel: [ModelTokenUsage]

    var cacheTotal: Int {
        cacheRead + cacheWrite
    }

    var promptSideTotal: Int {
        input + cacheRead + cacheWrite
    }

    var cacheHitRate: Double? {
        guard promptSideTotal > 0 else { return nil }
        return Double(cacheRead) / Double(promptSideTotal)
    }

    static let empty = TokenUsageSnapshot(
        total: 0,
        input: 0,
        output: 0,
        cacheRead: 0,
        cacheWrite: 0,
        reasoning: 0,
        byModel: []
    )
}

struct ModelTokenUsage: Identifiable, Equatable {
    var id: String { model }
    var model: String
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheWrite: Int
    var reasoning: Int

    var total: Int {
        input + output + cacheRead + cacheWrite + reasoning
    }

    var promptSideTotal: Int {
        input + cacheRead + cacheWrite
    }

    var cacheHitRate: Double? {
        guard promptSideTotal > 0 else { return nil }
        return Double(cacheRead) / Double(promptSideTotal)
    }
}

struct MemorySnapshot: Equatable {
    var rssBytes: Int?

    static let unknown = MemorySnapshot(rssBytes: nil)
}
