# Hermes Status Widget

本地 Hermes Agent 的只读 macOS 状态组件。应用包含两个入口：

- 系统 WidgetKit 小组件：主 App 写快照，Widget Extension 显示快照，可从 macOS 小组件库添加到桌面。
- 菜单栏下拉详情面板：点击菜单栏 Hermes 项展开详细数据与设置。

This first version does not call the Hermes dashboard and does not write to
Hermes files. It reads:

- `~/.hermes/gateway_state.json`
- `~/.hermes/gateway.pid`
- `~/.hermes/state.db` through `sqlite3 -readonly` and `mode=ro`
- `ps` for gateway RSS memory

## Run

```sh
swift run HermesStatusWidget
```

应用会常驻菜单栏。点击菜单栏里的 Hermes 项，会展开一个中文状态面板。主 App 每次刷新会写入快照，系统 WidgetKit 小组件读取这个快照显示。

## Build a Double-Clickable App / 构建可双击 App

```sh
chmod +x Scripts/build-app.sh
Scripts/build-app.sh
cp -R "dist/Hermes Status Widget.app" /Applications/
open "/Applications/Hermes Status Widget.app"
```

构建出的 `dist/Hermes Status Widget.app` 内嵌 `HermesStatusWidgetExtension.appex`。把 App 放到 `/Applications` 并运行后，可在 macOS 小组件库里搜索 “Hermes 状态” 并添加到桌面。

如果小组件库没有立刻出现，可以重新打开 App，或重启一次通知中心：

```sh
killall NotificationCenter
open "/Applications/Hermes Status Widget.app"
```

## Notes

- 启动前设置 `HERMES_HOME`，可以读取非默认 Hermes profile 目录。
- 组件优先展示最近一个 `ended_at IS NULL` 的 session；最近 5 分钟内有活动时标记为“进行中”，否则标记为“最近活跃”。
- Token 面板显示近 24 小时用量和可配置时间跨度的累计用量，包含输入、输出、缓存读取、缓存写入和 reasoning token。
- 缓存命中率 = 缓存读取 /（输入 + 缓存读取 + 缓存写入）。
- Agent 服务时长按当天 Hermes 会话消息活动计算，长时间无消息的空档会被截断，避免把闲置时间算成 Agent 工作时间。
- 主 App 每 30 秒刷新一次 Hermes 状态，并把快照同时写入主 App 支持目录和 Widget 扩展容器，避免桌面小组件读到空数据。
- WidgetKit 由系统调度刷新，代码请求 30 秒刷新一次；需要立刻更新时看菜单栏下拉，或点击菜单栏里的“刷新”让主 App 立刻写入最新快照。

## License

MIT
