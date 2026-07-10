import Foundation
import os.log

struct LocalHermesStatusReader: HermesStatusReading {
    func readSnapshot(cumulativeRange: CumulativeRange) async throws -> HermesSnapshot {
        let home = hermesHome()
        let gateway = readGateway(home: home)
        let activeSessions = readActiveSessions(home: home)
        let tokenUsage = readTokenUsage(home: home, since: Date().addingTimeInterval(-86_400))
        let allTimeTokenUsage = readTokenUsage(home: home, since: cumulativeRange.since)
        let sevenDayTokenUsage = readTokenUsage(home: home, since: Date().addingTimeInterval(-7 * 86_400))
        let vibeCoding = readVibeCoding(home: home)
        let memory = readMemory(pid: gateway.pid)

        return HermesSnapshot(
            gateway: gateway,
            activeSessions: activeSessions,
            tokenUsage: tokenUsage,
            allTimeTokenUsage: allTimeTokenUsage,
            sevenDayTokenUsage: sevenDayTokenUsage,
            vibeCoding: vibeCoding,
            memory: memory,
            refreshedAt: Date(),
            error: nil
        )
    }

    private func hermesHome() -> URL {
        if let override = ProcessInfo.processInfo.environment["HERMES_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes", isDirectory: true)
    }

    private func readGateway(home: URL) -> GatewaySnapshot {
        let stateURL = home.appendingPathComponent("gateway_state.json")
        let pidURL = home.appendingPathComponent("gateway.pid")

        var pidFromState: Int?
        var state = "offline"
        var activeAgents = 0
        var platforms: [PlatformSnapshot] = []
        var updatedAt: Date?

        if let data = try? Data(contentsOf: stateURL),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            pidFromState = object["pid"] as? Int
            state = (object["gateway_state"] as? String) ?? state
            activeAgents = object["active_agents"] as? Int ?? 0
            updatedAt = parseDate(object["updated_at"] as? String)

            if let platformObject = object["platforms"] as? [String: Any] {
                platforms = platformObject.keys.sorted().map { name in
                    let details = platformObject[name] as? [String: Any]
                    return PlatformSnapshot(
                        name: name,
                        state: (details?["state"] as? String) ?? "unknown"
                    )
                }
            }
        }

        var pid = pidFromState
        if pid == nil,
           let data = try? Data(contentsOf: pidURL) {
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                pid = object["pid"] as? Int
            } else if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                pid = Int(text)
            }
        }

        let running = pid.map(isProcessRunning(pid:)) ?? false
        return GatewaySnapshot(
            isRunning: running,
            state: running ? state : "offline",
            pid: pid,
            activeAgents: activeAgents,
            platforms: platforms,
            updatedAt: updatedAt
        )
    }

    private func readActiveSessions(home: URL) -> [SessionSnapshot] {
        let now = Int(Date().timeIntervalSince1970)
        let recentFloor = now - 86_400
        let query = """
        WITH activity AS (
            SELECT s.id,
                   s.source,
                   COALESCE(s.model, '') AS model,
                   COALESCE(NULLIF(s.title, ''), substr(s.id, 1, 8)) AS title,
                   COALESCE(MAX(m.timestamp), s.started_at) AS last_active,
                   s.ended_at,
                   COALESCE(s.input_tokens, 0) AS input_tokens,
                   COALESCE(s.output_tokens, 0) AS output_tokens,
                   COUNT(m.timestamp) AS active_message_count
            FROM sessions s
            LEFT JOIN messages m ON m.session_id = s.id AND COALESCE(m.active, 1) = 1
            GROUP BY s.id
        )
        SELECT id,
               source,
               model,
               title,
               last_active,
               CASE WHEN ended_at IS NULL AND (? - last_active) < 300 THEN 1 ELSE 0 END,
               input_tokens,
               output_tokens
        FROM activity
        WHERE last_active >= ?
          AND (
              active_message_count > 0
              OR input_tokens > 0
              OR output_tokens > 0
          )
        ORDER BY CASE WHEN ended_at IS NULL AND (? - last_active) < 300 THEN 1 ELSE 0 END DESC,
                 last_active DESC
        LIMIT 3;
        """
        let rows = sqliteRows(home: home, query: query, arguments: [String(now), String(recentFloor), String(now)])
        return rows.compactMap { row in
            guard row.count >= 8 else { return nil }
            return SessionSnapshot(
                id: row[0],
                source: row[1],
                model: row[2].isEmpty ? "unknown" : row[2],
                title: row[3],
                lastActive: Date(timeIntervalSince1970: TimeInterval(row[4]) ?? Date().timeIntervalSince1970),
                isLive: row[5] == "1",
                inputTokens: Int(row[6]) ?? 0,
                outputTokens: Int(row[7]) ?? 0
            )
        }
    }

    private func readTokenUsage(home: URL, since: Date?) -> TokenUsageSnapshot {
        let whereClause = since == nil ? "" : "WHERE activity_at >= ?"
        let query = """
        WITH session_activity AS (
            SELECT s.model,
                   s.input_tokens,
                   s.output_tokens,
                   s.cache_read_tokens,
                   s.cache_write_tokens,
                   s.reasoning_tokens,
                   COALESCE(MAX(m.timestamp), s.ended_at, s.started_at) AS activity_at
            FROM sessions s
            LEFT JOIN messages m ON m.session_id = s.id AND COALESCE(m.active, 1) = 1
            GROUP BY s.id
        )
        SELECT COALESCE(NULLIF(model, ''), 'unknown') AS model,
               COALESCE(SUM(input_tokens), 0),
               COALESCE(SUM(output_tokens), 0),
               COALESCE(SUM(cache_read_tokens), 0),
               COALESCE(SUM(cache_write_tokens), 0),
               COALESCE(SUM(reasoning_tokens), 0)
        FROM session_activity
        \(whereClause)
        GROUP BY model
        ORDER BY COALESCE(SUM(input_tokens), 0)
               + COALESCE(SUM(output_tokens), 0) DESC
        """
        let args = since.map { [String(Int($0.timeIntervalSince1970))] } ?? []
        let rows = sqliteRows(home: home, query: query, arguments: args)
        let byModel = rows.compactMap { row -> ModelTokenUsage? in
            guard row.count >= 6 else { return nil }
            return ModelTokenUsage(
                model: row[0],
                input: Int(row[1]) ?? 0,
                output: Int(row[2]) ?? 0,
                cacheRead: Int(row[3]) ?? 0,
                cacheWrite: Int(row[4]) ?? 0,
                reasoning: Int(row[5]) ?? 0
            )
        }
        return TokenUsageSnapshot(
            total: byModel.reduce(0) { $0 + $1.total },
            input: byModel.reduce(0) { $0 + $1.input },
            output: byModel.reduce(0) { $0 + $1.output },
            cacheRead: byModel.reduce(0) { $0 + $1.cacheRead },
            cacheWrite: byModel.reduce(0) { $0 + $1.cacheWrite },
            reasoning: byModel.reduce(0) { $0 + $1.reasoning },
            byModel: byModel
        )
    }

    private func readVibeCoding(home: URL) -> VibeCodingSnapshot {
        let now = Date()
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let nowSeconds = now.timeIntervalSince1970
        let dayStartSeconds = dayStart.timeIntervalSince1970

        let query = """
        SELECT s.id,
               s.started_at,
               COALESCE(s.ended_at, ''),
               COALESCE(m.timestamp, '')
        FROM sessions s
        LEFT JOIN messages m ON m.session_id = s.id AND COALESCE(m.active, 1) = 1
        WHERE s.started_at < ?
          AND COALESCE(s.ended_at, m.timestamp, s.started_at) >= ?
        ORDER BY s.id, m.timestamp;
        """

        let args = [
            String(Int(nowSeconds)),
            String(Int(dayStartSeconds))
        ]
        let rows = sqliteRows(home: home, query: query, arguments: args)
        guard !rows.isEmpty else { return .empty }

        struct SessionActivity {
            var startedAt: TimeInterval
            var endedAt: TimeInterval?
            var messageTimes: [TimeInterval]
        }

        var sessions: [String: SessionActivity] = [:]
        for row in rows where row.count >= 4 {
            let id = row[0]
            guard let startedAt = TimeInterval(row[1]) else { continue }
            let endedAt = row[2].isEmpty ? nil : TimeInterval(row[2])
            let messageTime = row[3].isEmpty ? nil : TimeInterval(row[3])

            var activity = sessions[id] ?? SessionActivity(startedAt: startedAt, endedAt: endedAt, messageTimes: [])
            activity.endedAt = activity.endedAt ?? endedAt
            if let messageTime {
                activity.messageTimes.append(messageTime)
            }
            sessions[id] = activity
        }

        let maxIdleGap: TimeInterval = 15 * 60
        let singleMessageCredit: TimeInterval = 60
        var todaySeconds = 0
        var activeSeconds = 0
        var sessionCount = 0
        var activeSessionCount = 0

        for activity in sessions.values {
            let lastMessage = activity.messageTimes.max() ?? activity.startedAt
            let isActive = activity.endedAt == nil && (nowSeconds - lastMessage) < 300
            let rawEnd = activity.endedAt ?? (isActive ? nowSeconds : lastMessage)
            let start = max(activity.startedAt, dayStartSeconds)
            let end = min(rawEnd, nowSeconds)
            guard end > start else { continue }

            let messagePoints = activity.messageTimes
                .filter { $0 >= start && $0 <= end }
                .sorted()

            let rawDuration: TimeInterval
            if messagePoints.isEmpty {
                guard activity.startedAt >= dayStartSeconds else { continue }
                rawDuration = min(end - start, singleMessageCredit)
            } else {
                var points = messagePoints
                if activity.startedAt >= dayStartSeconds && activity.startedAt < points[0] {
                    points.insert(activity.startedAt, at: 0)
                }
                if end > (points.last ?? start), isActive || activity.endedAt != nil {
                    points.append(end)
                }

                rawDuration = zip(points, points.dropFirst()).reduce(0) { total, pair in
                    total + min(max(0, pair.1 - pair.0), maxIdleGap)
                }
            }
            let duration = messagePoints.isEmpty ? rawDuration : max(rawDuration, singleMessageCredit)

            guard duration > 0 else { continue }
            todaySeconds += Int(duration.rounded())
            sessionCount += 1

            if isActive {
                activeSessionCount += 1
                activeSeconds += Int(duration.rounded())
            }
        }

        return VibeCodingSnapshot(
            todaySeconds: todaySeconds,
            activeSessionSeconds: activeSeconds,
            sessionCount: sessionCount,
            activeSessionCount: activeSessionCount
        )
    }

    private func readMemory(pid: Int?) -> MemorySnapshot {
        guard let pid else { return .unknown }
        let result = run("/bin/ps", ["-p", String(pid), "-o", "rss="])
        guard let kb = Int(result.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .unknown
        }
        return MemorySnapshot(rssBytes: kb * 1024)
    }

    private func sqliteRows(home: URL, query: String, arguments: [String]) -> [[String]] {
        guard let db = stateDatabasePath(home: home) else { return [] }

        let script = ".parameter clear\n" +
            arguments.enumerated().map {
                ".parameter set ?\($0.offset + 1) '\($0.element.replacingOccurrences(of: "'", with: "''"))'"
            }.joined(separator: "\n") +
            "\n.mode tabs\n.headers off\n\(query)\n"

        // Write SQL script to a temp file to avoid stdin/EOF issues with Process.
        // stdin Pipe kept alive by Process prevents EOF, causing sqlite3 to hang forever.
        let tmpDir = FileManager.default.temporaryDirectory
        let scriptFile = tmpDir.appendingPathComponent("hsw-\(UUID().uuidString).sql")
        do {
            try script.write(to: scriptFile, atomically: true, encoding: .utf8)
        } catch {
            return []
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        task.arguments = ["-cmd", ".read '\(scriptFile.path)'", "file:\(db)?immutable=1"]

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr

        do {
            try task.run()
        } catch {
            try? FileManager.default.removeItem(at: scriptFile)
            return []
        }

        // Read stdout BEFORE waitUntilExit to avoid deadlock.
        // If output exceeds PIPE buffer (64KB), sqlite3 will block until stdout is consumed.
        let stdoutData = try? stdout.fileHandleForReading.readDataToEndOfFile()
        var output = String(data: stdoutData ?? Data(), encoding: .utf8) ?? ""

        task.waitUntilExit()
        try? FileManager.default.removeItem(at: scriptFile)

        if task.terminationStatus != 0 {
            let stderrData = try? stderr.fileHandleForReading.readDataToEndOfFile()
            let stderrMsg = String(data: stderrData ?? Data(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            os_log("sqlite3 terminated with status %ld: %s", type: .error, task.terminationStatus, stderrMsg)
            return []
        }

        if output.hasSuffix("\n") {
            output = String(output.dropLast())
        }
        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    }

    private func stateDatabasePath(home: URL) -> String? {
        for name in ["state.db", "hermes_state.db"] {
            let path = home.appendingPathComponent(name).path
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func isProcessRunning(pid: Int) -> Bool {
        let result = run("/bin/ps", ["-p", String(pid), "-o", "pid="])
        return result.trimmingCharacters(in: .whitespacesAndNewlines) == String(pid)
    }

    private func run(_ executable: String, _ arguments: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }
}
