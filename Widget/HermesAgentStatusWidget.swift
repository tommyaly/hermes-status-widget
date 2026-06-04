import SwiftUI
import WidgetKit

struct HermesWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: HermesSnapshot
}

struct HermesWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HermesWidgetEntry {
        HermesWidgetEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (HermesWidgetEntry) -> Void) {
        completion(HermesWidgetEntry(date: Date(), snapshot: WidgetSnapshotStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HermesWidgetEntry>) -> Void) {
        let entry = HermesWidgetEntry(date: Date(), snapshot: WidgetSnapshotStore.read())
        let next = Date().addingTimeInterval(30)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct HermesAgentStatusWidget: Widget {
    let kind = "HermesAgentStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HermesWidgetProvider()) { entry in
            HermesWidgetView(entry: entry)
        }
        .configurationDisplayName("Hermes 状态")
        .description("显示本地 Hermes Agent 状态、Token 和缓存命中率。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct HermesAgentWidgetBundle: WidgetBundle {
    var body: some Widget {
        HermesAgentStatusWidget()
    }
}

struct HermesWidgetView: View {
    let entry: HermesWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let snapshot = entry.snapshot
        let usage = snapshot.tokenUsage

        switch family {
        case .systemSmall:
            small(snapshot: snapshot, usage: usage)
                .containerBackground(for: .widget) { widgetBackground }
        case .systemLarge:
            large(snapshot: snapshot, usage: usage)
                .containerBackground(for: .widget) { widgetBackground }
        default:
            medium(snapshot: snapshot, usage: usage)
                .containerBackground(for: .widget) { widgetBackground }
        }
    }

    private var widgetBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.07, green: 0.10, blue: 0.12),
                Color(red: 0.05, green: 0.16, blue: 0.15),
                Color(red: 0.18, green: 0.08, blue: 0.13)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func small(snapshot: HermesSnapshot, usage: TokenUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                statusDot(snapshot)
                Spacer()
                Text(snapshot.gateway.isRunning ? "在线" : "离线")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(snapshot.gateway.isRunning ? .green.opacity(0.88) : .white.opacity(0.58))
            }

            Text("24 小时 Token")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))

            Text(formatTokenCount(usage.total))
                .font(.system(size: 25, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            Text("Agent 今日服务时长")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))

            Text(formatDuration(snapshot.vibeCoding.todaySeconds))
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(formatPercent(snapshot.vibeCoding.dayRatio))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(14)
    }

    private func medium(snapshot: HermesSnapshot, usage: TokenUsageSnapshot) -> some View {
        HStack(spacing: 12) {
            vibeRing(snapshot.vibeCoding, size: 72, lineWidth: 7)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Agent 服务时长")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        Text(statusText(snapshot))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.70))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    statusDot(snapshot)
                }

                HStack(spacing: 7) {
                    widgetMetric("时长", formatDuration(snapshot.vibeCoding.todaySeconds))
                    widgetMetric("输入", formatTokenCount(usage.input))
                    widgetMetric("输出", formatTokenCount(usage.output))
                    widgetMetric("命中", formatCacheHitRate(usage.cacheHitRate))
                }

                modelLine(usage.byModel.first)
            }
        }
        .padding(14)
    }

    private func large(snapshot: HermesSnapshot, usage: TokenUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statusDot(snapshot)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hermes 状态")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(statusText(snapshot))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.70))
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatBytes(snapshot.memory.rssBytes))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.70))
                    Text(snapshot.refreshedAt, style: .time)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.50))
                }
            }

            vibeHero(snapshot.vibeCoding)

            HStack(alignment: .top, spacing: 10) {
                agentSummaryCard(snapshot)
                tokenSummaryCard(usage)
            }

            modelSummary(usage)
        }
        .padding(12)
    }

    private func vibeHero(_ vibe: VibeCodingSnapshot) -> some View {
        HStack(spacing: 10) {
            vibeRing(vibe, size: 62, lineWidth: 7)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Agent 服务时长")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.66))
                    Spacer()
                    Text(formatPercent(vibe.dayRatio))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                }

                Text(formatDuration(vibe.todaySeconds))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule()
                            .fill(LinearGradient(colors: [.green, .cyan], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, proxy.size.width * CGFloat(vibe.dayRatio)))
                    }
                }
                .frame(height: 7)

                HStack(spacing: 10) {
                    Text("占 24 小时")
                    Text("\(vibe.sessionCount) 个会话")
                    if vibe.activeSessionCount > 0 {
                        Text("进行中 \(formatDuration(vibe.activeSessionSeconds))")
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(1)
            }
        }
    }

    private func agentSummaryCard(_ snapshot: HermesSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("当前 Agent")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))

            if let session = snapshot.activeSession {
                Text(session.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(minHeight: 26, alignment: .topLeading)
                Text("\(session.source) · \(session.model)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
                Text(session.isLive ? "进行中 · \(relativeTime(session.lastActive))" : "最近活跃 · \(relativeTime(session.lastActive))")
                    .font(.system(size: 10))
                    .foregroundStyle(session.isLive ? .green.opacity(0.85) : .white.opacity(0.52))
                    .lineLimit(1)
            } else {
                Text(snapshot.gateway.activeAgents > 0 ? "\(snapshot.gateway.activeAgents) 个网关 agent 活跃" : "空闲")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.84))
                    .frame(minHeight: 46, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func tokenSummaryCard(_ usage: TokenUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("近 24 小时 Token")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
            HStack(alignment: .firstTextBaseline) {
                Text(formatTokenCount(usage.total))
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer()
                Text(formatCacheHitRate(usage.cacheHitRate))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.green.opacity(0.86))
            }
            HStack(spacing: 8) {
                widgetMetric("输入", formatTokenCount(usage.input))
                widgetMetric("输出", formatTokenCount(usage.output))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func modelSummary(_ usage: TokenUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("模型消耗")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))

            if usage.byModel.isEmpty {
                Text("没有 token 记录")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.52))
            } else {
                VStack(spacing: 5) {
                    ForEach(usage.byModel.prefix(2)) { row in
                        modelBar(row, maxTotal: max(usage.byModel.map(\.total).max() ?? 1, 1))
                    }
                }
            }
        }
    }

    private func statusDot(_ snapshot: HermesSnapshot) -> some View {
        Circle()
            .fill(snapshot.gateway.isRunning ? Color.green : Color.gray)
            .frame(width: 11, height: 11)
            .shadow(color: snapshot.gateway.isRunning ? .green.opacity(0.75) : .clear, radius: 5)
    }

    private func vibeRing(_ vibe: VibeCodingSnapshot, size: CGFloat = 82, lineWidth: CGFloat = 8) -> some View {
        let percent = max(0, min(1, vibe.dayRatio))
        return ZStack {
            Circle().stroke(.white.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: percent)
                .stroke(
                    AngularGradient(colors: [.green, .cyan, .mint], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(formatPercent(percent))
                    .font(.system(size: size > 70 ? 14 : 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("24h")
                    .font(.system(size: size > 70 ? 9 : 8))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .frame(width: size, height: size)
    }

    private func widgetMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.60))
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.64)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func modelLine(_ row: ModelTokenUsage?) -> some View {
        HStack {
            Text(row?.model ?? "暂无模型")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
            Spacer()
            Text(formatTokenCount(row?.total ?? 0))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.70))
        }
    }

    private func modelBar(_ row: ModelTokenUsage, maxTotal: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.model)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.80))
                    .lineLimit(1)
                Spacer()
                Text(formatTokenCount(row.total))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.68))
            }
            GeometryReader { proxy in
                let width = proxy.size.width * CGFloat(row.total) / CGFloat(maxTotal)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(LinearGradient(colors: [.green, .cyan], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, width))
                }
            }
            .frame(height: 6)
        }
    }

    private func statusText(_ snapshot: HermesSnapshot) -> String {
        guard snapshot.gateway.isRunning else { return "网关离线" }
        if let session = snapshot.activeSession {
            return session.isLive ? "Agent 进行中 · \(session.source)" : "最近活跃 · \(session.source)"
        }
        return "网关运行中"
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

    private func formatCacheHitRate(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.0f%%", value * 100)
    }

    private func formatPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatBytes(_ value: Int?) -> String {
        guard let value else { return "--" }
        let mb = Double(value) / 1_048_576
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
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
