# Hermes Status Widget

本地 Hermes Agent 的只读 macOS 菜单栏状态组件。

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

应用会常驻菜单栏。点击菜单栏里的 Hermes 项，会展开一个中文状态面板。

## Build a Double-Clickable App / 构建可双击 App

```sh
chmod +x Scripts/build-app.sh
Scripts/build-app.sh
open dist
```

## Notes

- 启动前设置 `HERMES_HOME`，可以读取非默认 Hermes profile 目录。
- 组件优先展示最近一个 `ended_at IS NULL` 的 session；最近 5 分钟内有活动时标记为“进行中”，否则标记为“最近活跃”。
- Token 面板显示近 24 小时用量和可配置时间跨度的累计用量，包含输入、输出、缓存读取、缓存写入和 reasoning token。
- 缓存命中率 = 缓存读取 /（输入 + 缓存读取 + 缓存写入）。
