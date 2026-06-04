import SwiftUI

struct HermesStatusPanelView: View {
    @Environment(StatusStore.self) private var store
    @Environment(\.refreshHermesStatus) private var refresh
    @Environment(\.quitHermesStatusWidget) private var quit
    @State private var showingSettings = false
    private let menuModelLimit = 5

    var body: some View {
        let snapshot = store.snapshot

        VStack(alignment: .leading, spacing: 14) {
            header(snapshot, showingSettings: showingSettings)

            Divider().opacity(0.45)

            if showingSettings {
                settingsSection()
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        vibeCodingSection(snapshot.vibeCoding)
                        agentSection(snapshot)
                        usageSection(snapshot.tokenUsage)
                        sectionSeparator()
                        cumulativeSection(snapshot.allTimeTokenUsage)
                        footer(snapshot)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.visible)
            }
        }
        .padding(18)
        .frame(width: 440, height: 680, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
    }

    private func header(_ snapshot: HermesSnapshot, showingSettings: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: snapshot.gateway.isRunning ? "bolt.horizontal.fill" : "bolt.slash")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(snapshot.gateway.isRunning ? .green : .secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(showingSettings ? "设置" : "Hermes 状态")
                    .font(.system(size: 16, weight: .semibold))
                Text(showingSettings ? "调整统计口径" : (snapshot.gateway.isRunning ? stateLabel(snapshot.gateway.state) : "离线"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 8) {
                    Button(action: { self.showingSettings.toggle() }) {
                        Image(systemName: showingSettings ? "chevron.left" : "gearshape")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help(showingSettings ? "返回状态" : "设置")

                    Button(action: quit) {
                        Image(systemName: "power")
                            .foregroundStyle(.red)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("退出 Hermes 状态小组件")
                }

                if !showingSettings {
                    Text(formatBytes(snapshot.memory.rssBytes))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func vibeCodingSection(_ vibe: VibeCodingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Agent 服务时长", systemImage: "clock.badge.checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatDuration(vibe.todaySeconds))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.secondary.opacity(0.16))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(LinearGradient(colors: [.green, .cyan], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, proxy.size.width * CGFloat(vibe.dayRatio)))
                }
            }
            .frame(height: 8)

            HStack(spacing: 10) {
                Text("占 24 小时 \(formatPercent(vibe.dayRatio))")
                Text("\(vibe.sessionCount) 个会话")
                if vibe.activeSessionCount > 0 {
                    Text("进行中 \(formatDuration(vibe.activeSessionSeconds))")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    private func agentSection(_ snapshot: HermesSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("当前活跃 Agent", systemImage: "person.wave.2")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if let session = snapshot.activeSession {
                HStack(spacing: 8) {
                    Text(session.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(session.isLive ? "进行中" : "最近活跃")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(session.isLive ? Color.green.opacity(0.16) : Color.secondary.opacity(0.14))
                        .clipShape(Capsule())
                }
                HStack(spacing: 8) {
                    Text(session.source)
                    Text(session.model)
                    Text("\(formatTokenCount(session.inputTokens + session.outputTokens)) token")
                    Text(relativeTime(session.lastActive))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            } else {
                Text("空闲")
                    .font(.system(size: 15, weight: .medium))
                Text(snapshot.gateway.activeAgents > 0 ? "\(snapshot.gateway.activeAgents) 个网关 agent 活跃" : "最近 5 分钟没有活跃 session")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func usageSection(_ usage: TokenUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("近 24 小时 Token", systemImage: "chart.bar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatTokenCount(usage.total))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }

            if usage.byModel.isEmpty {
                Text("近 24 小时没有 token 记录")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    metric("总量", usage.total)
                    metric("总量输入", usage.input)
                    metric("总量输出", usage.output)
                    metric("命中率", formatCacheHitRate(usage.cacheHitRate))
                }

                VStack(spacing: 6) {
                    ForEach(usage.byModel.prefix(menuModelLimit)) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(row.model)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                                Text(formatTokenCount(row.total))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 10) {
                                modelMetric("总量", row.total)
                                modelMetric("输入", row.input)
                                modelMetric("输出", row.output)
                                modelMetric("命中率", formatCacheHitRate(row.cacheHitRate))
                            }
                        }
                    }
                }
            }
        }
    }

    private func cumulativeSection(_ usage: TokenUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label("累计 Token（\(store.cumulativeRange.label)）", systemImage: "sum")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(formatTokenCount(usage.total))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                metric("总量", usage.total)
                metric("总量输入", usage.input)
                metric("总量输出", usage.output)
                metric("命中率", formatCacheHitRate(usage.cacheHitRate))
            }

            ForEach(usage.byModel.prefix(menuModelLimit)) { row in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(row.model)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Text(formatTokenCount(row.total))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        modelMetric("总量", row.total)
                        modelMetric("输入", row.input)
                        modelMetric("输出", row.output)
                        modelMetric("命中率", formatCacheHitRate(row.cacheHitRate))
                    }
                }
            }
        }
    }

    private func sectionSeparator() -> some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(.secondary.opacity(0.22))
                .frame(height: 1)
            Text("累计统计")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle()
                .fill(.secondary.opacity(0.22))
                .frame(height: 1)
        }
        .padding(.vertical, 2)
    }

    private func settingsSection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("累计 token 时间跨度")
                    .font(.system(size: 13, weight: .semibold))
                Text("只影响“累计 Token”区域，不影响近 24 小时统计。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Picker("累计范围", selection: Binding(
                    get: { store.cumulativeRange },
                    set: { store.setCumulativeRange($0) }
                )) {
                    ForEach(CumulativeRange.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Divider().opacity(0.45)

            VStack(alignment: .leading, spacing: 6) {
                Text("统计说明")
                    .font(.system(size: 13, weight: .semibold))
                Text("总量 = 输入 + 输出 + 缓存读取 + 缓存写入 + 推理。")
                Text("缓存命中率 = 缓存读取 /（输入 + 缓存读取 + 缓存写入）。")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Spacer()

            Button(action: { showingSettings = false }) {
                Label("返回状态", systemImage: "chevron.left")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func footer(_ snapshot: HermesSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if snapshot.gateway.platforms.isEmpty {
                    Text("暂无平台状态")
                } else {
                    Text(snapshot.gateway.platforms.map { "\($0.name): \(stateLabel($0.state))" }.joined(separator: "  "))
                        .lineLimit(1)
                }

                Spacer()

                Text(snapshot.refreshedAt, style: .time)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(action: refresh) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: quit) {
                    Label("退出", systemImage: "power")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func metric(_ label: String, _ value: Int) -> some View {
        metric(label, formatTokenCount(value))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func modelMetric(_ label: String, _ value: Int) -> some View {
        modelMetric(label, formatTokenCount(value))
    }

    private func modelMetric(_ label: String, _ value: String) -> some View {
        Text("\(label) \(value)")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func formatTokenCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private func formatBytes(_ value: Int?) -> String {
        guard let value else { return "--" }
        let mb = Double(value) / 1_048_576
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }

    private func formatCacheHitRate(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f%%", value * 100)
    }

    private func formatPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)小时\(minutes)分"
        }
        return "\(minutes)分"
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 {
            return "\(seconds) 秒前"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) 分钟前"
        }
        return "\(minutes / 60) 小时前"
    }

    private func stateLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "running":
            return "运行中"
        case "connected":
            return "已连接"
        case "starting":
            return "启动中"
        case "stopped", "offline":
            return "离线"
        case "error", "startup_failed":
            return "异常"
        default:
            return value
        }
    }
}
