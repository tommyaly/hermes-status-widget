import Foundation

struct LocalHermesStatusReader: HermesStatusReading {
    func readSnapshot(cumulativeRange: CumulativeRange) async throws -> HermesSnapshot {
        let home = hermesHome()
        let gateway = readGateway(home: home)
        let activeSession = readActiveSession(home: home)
        let tokenUsage = readTokenUsage(home: home, since: Date().addingTimeInterval(-86_400))
        let allTimeTokenUsage = readTokenUsage(home: home, since: cumulativeRange.since)
        let memory = readMemory(pid: gateway.pid)

        return HermesSnapshot(
            gateway: gateway,
            activeSession: activeSession,
            tokenUsage: tokenUsage,
            allTimeTokenUsage: allTimeTokenUsage,
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
           let data = try? Data(contentsOf: pidURL),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            pid = object["pid"] as? Int
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

    private func readActiveSession(home: URL) -> SessionSnapshot? {
        let query = """
        SELECT s.id,
               s.source,
               COALESCE(s.model, ''),
               COALESCE(NULLIF(s.title, ''), substr(s.id, 1, 8)),
               COALESCE(MAX(m.timestamp), s.started_at) AS last_active,
               CASE WHEN (? - COALESCE(MAX(m.timestamp), s.started_at)) < 300 THEN 1 ELSE 0 END,
               COALESCE(s.input_tokens, 0),
               COALESCE(s.output_tokens, 0)
        FROM sessions s
        LEFT JOIN messages m ON m.session_id = s.id AND COALESCE(m.active, 1) = 1
        WHERE s.ended_at IS NULL
        GROUP BY s.id
        ORDER BY last_active DESC
        LIMIT 1;
        """
        let rows = sqliteRows(home: home, query: query, arguments: [String(Int(Date().timeIntervalSince1970))])
        guard let row = rows.first, row.count >= 8 else { return nil }

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

    private func readTokenUsage(home: URL, since: Date?) -> TokenUsageSnapshot {
        let whereClause = since == nil ? "" : "WHERE started_at >= ?"
        let query = """
        SELECT COALESCE(NULLIF(model, ''), 'unknown') AS model,
               COALESCE(SUM(input_tokens), 0),
               COALESCE(SUM(output_tokens), 0),
               COALESCE(SUM(cache_read_tokens), 0),
               COALESCE(SUM(cache_write_tokens), 0),
               COALESCE(SUM(reasoning_tokens), 0)
        FROM sessions
        \(whereClause)
        GROUP BY model
        ORDER BY COALESCE(SUM(input_tokens), 0)
               + COALESCE(SUM(output_tokens), 0)
               + COALESCE(SUM(cache_read_tokens), 0)
               + COALESCE(SUM(cache_write_tokens), 0)
               + COALESCE(SUM(reasoning_tokens), 0) DESC
        LIMIT 5;
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

    private func readMemory(pid: Int?) -> MemorySnapshot {
        guard let pid else { return .unknown }
        let result = run("/bin/ps", ["-p", String(pid), "-o", "rss="])
        guard let kb = Int(result.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .unknown
        }
        return MemorySnapshot(rssBytes: kb * 1024)
    }

    private func sqliteRows(home: URL, query: String, arguments: [String]) -> [[String]] {
        let db = home.appendingPathComponent("state.db").path
        guard FileManager.default.fileExists(atPath: db) else { return [] }

        let sql = ".parameter clear\n" +
            arguments.enumerated().map { ".parameter set ?\($0.offset + 1) '\($0.element.replacingOccurrences(of: "'", with: "''"))'" }.joined(separator: "\n") +
            "\n.mode tabs\n.headers off\n\(query)\n"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        task.arguments = ["-readonly", "file:\(db)?mode=ro"]

        let stdin = Pipe()
        let stdout = Pipe()
        task.standardInput = stdin
        task.standardOutput = stdout
        task.standardError = Pipe()

        do {
            try task.run()
            stdin.fileHandleForWriting.write(sql.data(using: .utf8) ?? Data())
            try? stdin.fileHandleForWriting.close()
            task.waitUntilExit()
        } catch {
            return []
        }

        guard task.terminationStatus == 0 else { return [] }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
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
