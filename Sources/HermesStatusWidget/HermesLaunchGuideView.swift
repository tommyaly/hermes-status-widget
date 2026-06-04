import SwiftUI

struct HermesLaunchGuideView: View {
    @Environment(\.closeHermesLaunchGuide) private var close

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Hermes 状态已启动")
                        .font(.system(size: 20, weight: .semibold))
                    Text("它会常驻菜单栏，并为桌面小组件写入最新快照。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                guideRow("1", "看菜单栏右上角", "点击 Hermes 可以打开状态面板、刷新数据和调整统计跨度。")
                guideRow("2", "添加桌面小组件", "在桌面打开小组件库，搜索“Hermes 状态”，添加到桌面。")
                guideRow("3", "保持主 App 运行", "WidgetKit 只显示快照；主 App 负责只读 Hermes 后台状态。")
            }

            Spacer()

            HStack {
                Text("如果双击后只看到菜单栏变化，这是正常的。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("知道了") {
                    close()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 420, height: 300, alignment: .topLeading)
        .background(.regularMaterial)
    }

    private func guideRow(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.green.opacity(0.78)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
