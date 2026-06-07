import Foundation

struct HermesSnapshot: Codable, Equatable {
    var gateway: GatewaySnapshot
    var activeSessions: [SessionSnapshot]
    var tokenUsage: TokenUsageSnapshot
    var allTimeTokenUsage: TokenUsageSnapshot
    var sevenDayTokenUsage: TokenUsageSnapshot
    var vibeCoding: VibeCodingSnapshot
    var memory: MemorySnapshot
    var refreshedAt: Date
    var error: String?

    var activeSession: SessionSnapshot? {
        activeSessions.first
    }

    init(
        gateway: GatewaySnapshot,
        activeSessions: [SessionSnapshot],
        tokenUsage: TokenUsageSnapshot,
        allTimeTokenUsage: TokenUsageSnapshot,
        sevenDayTokenUsage: TokenUsageSnapshot,
        vibeCoding: VibeCodingSnapshot,
        memory: MemorySnapshot,
        refreshedAt: Date,
        error: String?
    ) {
        self.gateway = gateway
        self.activeSessions = activeSessions
        self.tokenUsage = tokenUsage
        self.allTimeTokenUsage = allTimeTokenUsage
        self.sevenDayTokenUsage = sevenDayTokenUsage
        self.vibeCoding = vibeCoding
        self.memory = memory
        self.refreshedAt = refreshedAt
        self.error = error
    }

    static let empty = HermesSnapshot(
        gateway: .offline,
        activeSessions: [],
        tokenUsage: .empty,
        allTimeTokenUsage: .empty,
        sevenDayTokenUsage: .empty,
        vibeCoding: .empty,
        memory: .unknown,
        refreshedAt: Date(),
        error: nil
    )

    enum CodingKeys: String, CodingKey {
        case gateway
        case activeSessions
        case activeSession
        case tokenUsage
        case allTimeTokenUsage
        case sevenDayTokenUsage
        case vibeCoding
        case memory
        case refreshedAt
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacySession = try container.decodeIfPresent(SessionSnapshot.self, forKey: .activeSession)

        gateway = try container.decode(GatewaySnapshot.self, forKey: .gateway)
        activeSessions = try container.decodeIfPresent([SessionSnapshot].self, forKey: .activeSessions)
            ?? legacySession.map { [$0] }
            ?? []
        tokenUsage = try container.decode(TokenUsageSnapshot.self, forKey: .tokenUsage)
        allTimeTokenUsage = try container.decode(TokenUsageSnapshot.self, forKey: .allTimeTokenUsage)
        sevenDayTokenUsage = try container.decodeIfPresent(TokenUsageSnapshot.self, forKey: .sevenDayTokenUsage) ?? allTimeTokenUsage
        vibeCoding = try container.decode(VibeCodingSnapshot.self, forKey: .vibeCoding)
        memory = try container.decode(MemorySnapshot.self, forKey: .memory)
        refreshedAt = try container.decode(Date.self, forKey: .refreshedAt)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(gateway, forKey: .gateway)
        try container.encode(activeSessions, forKey: .activeSessions)
        try container.encodeIfPresent(activeSession, forKey: .activeSession)
        try container.encode(tokenUsage, forKey: .tokenUsage)
        try container.encode(allTimeTokenUsage, forKey: .allTimeTokenUsage)
        try container.encode(sevenDayTokenUsage, forKey: .sevenDayTokenUsage)
        try container.encode(vibeCoding, forKey: .vibeCoding)
        try container.encode(memory, forKey: .memory)
        try container.encode(refreshedAt, forKey: .refreshedAt)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

struct GatewaySnapshot: Codable, Equatable {
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

struct PlatformSnapshot: Codable, Identifiable, Equatable {
    var id: String { name }
    var name: String
    var state: String
}

struct SessionSnapshot: Codable, Identifiable, Equatable {
    var id: String
    var source: String
    var model: String
    var title: String
    var lastActive: Date
    var isLive: Bool
    var inputTokens: Int
    var outputTokens: Int
}

struct TokenUsageSnapshot: Codable, Equatable {
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

struct ModelTokenUsage: Codable, Identifiable, Equatable {
    var id: String { model }
    var model: String
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheWrite: Int
    var reasoning: Int

    var total: Int {
        input + output
    }

    var promptSideTotal: Int {
        input + cacheRead + cacheWrite
    }

    var cacheHitRate: Double? {
        guard promptSideTotal > 0 else { return nil }
        return Double(cacheRead) / Double(promptSideTotal)
    }
}

struct VibeCodingSnapshot: Codable, Equatable {
    var todaySeconds: Int
    var activeSessionSeconds: Int
    var sessionCount: Int
    var activeSessionCount: Int

    var dayRatio: Double {
        min(1, max(0, Double(todaySeconds) / 86_400))
    }

    static let empty = VibeCodingSnapshot(
        todaySeconds: 0,
        activeSessionSeconds: 0,
        sessionCount: 0,
        activeSessionCount: 0
    )
}

struct MemorySnapshot: Codable, Equatable {
    var rssBytes: Int?

    static let unknown = MemorySnapshot(rssBytes: nil)
}
