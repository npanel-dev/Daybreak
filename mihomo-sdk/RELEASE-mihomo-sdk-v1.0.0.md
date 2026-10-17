# mihomo-sdk-v1.0.0 — mihomo 内核客户端 SDK 首个发布（Android / iOS / macOS / Windows）

> **这是客户端 SDK，不是 Node。** 标签 `mihomo-sdk-v1.0.0` 与 Node 的 `vX.Y.Z` 相互独立。本 Release **没有标为 Latest**，`install.sh` 仍然安装和升级 Node，不受影响。
> 它也不是 Rust 的 `dbk-sdk`：本 SDK 基于 mihomo（Clash.Meta）内核，内置 SimnetV2 出站，供 Flutter / Dart 客户端集成。

## 配套要求

- **Node：v1.0.29 及以上**（内部 0.4.28）。SimNet 每条 TCP 独立建连（capability bit3），UDP 按入口关联复用 Datagram 载体。连接 ≤ v1.0.28 的旧共享复用 Node 会在业务开流前失败，没有回退。
- **建议节点升级到 v1.0.31**。v1.0.29 / v1.0.30 在多用户同时建连时会出现最长 30 秒的监听自锁。本 SDK 把握手许可持有到 ServerAccept，单个客户端自己不会触发这个问题，但多用户场景仍需要节点升级。

## 内容

| 平台 | 资产 | 形态 | TUN |
|---|---|---|---|
| Android | `mihomo-sdk-v1.0.0-android.zip` | gomobile AAR（arm64-v8a / armeabi-v7a / x86 / x86_64 / universal） | VpnService fd → `startTun` |
| iOS | `mihomo-sdk-v1.0.0-ios.zip` | `Mihomo.xcframework`（真机 + 模拟器） | NetworkExtension 内 `startTun`（未验证） |
| macOS | `mihomo-sdk-v1.0.0-macos.zip` | `MihomoCore` 内核进程 + `Mihomo.xcframework` | `MihomoCore`：一次管理员授权（setuid）后用配置开启 `tun:` |
| Windows | `mihomo-sdk-v1.0.0-windows-amd64.zip` / `-arm64.zip` | `MihomoCore.exe` | 安装为 SYSTEM 服务（一次 UAC）后用配置开启 `tun:`，wintun 已内置 |
| Flutter | `mihomo-sdk-v1.0.0-flutter.zip` | Dart 封装、桌面传输层、Android 插件 | — |

## 主要能力

- **统一 JSON 接口**：各平台都是 `invokeMethod` 一个入口，20 个方法，包括初始化、配置热重载、关闭、节点列表与切换、并发测延迟、流量、连接、模式、日志事件、系统 DNS。Dart 端 `MihomoService` 在各平台用法一致。
- **SimNet 提速**：
  - 预建载体：近 60 秒内有新连接时，保持最多 2 条已认证载体备用；
  - 冷建连时 ClientOpen 和 Open 一次发出；
  - S5 握手一次发完，遇到不兼容的服务器自动回退；
  - 实测（SDK → SimNet → Node → S5 链路）：新连接首包延迟从 415ms 降到 151ms，6 连接突发与 VLESS 持平。
- **连接突发**：每个出站最多 256 条载体，满了改为排队等待，并回收空闲超过 30 秒的流，不再直接拒绝（`97d7ce9`）。
- **桌面 TUN**：参考 FlClash 的做法。macOS 内核进程通过 Unix socket 通信，并校验 socket 属主；Windows 系统服务通过回环 TCP + 令牌通信，令牌目录受权限保护，`homeDir` 限定在用户个人目录内，内核崩溃后自动重启。会话结束时内核会关闭 TUN、恢复路由。

接入方法见 [GUIDE.md](GUIDE.md)。

## 本地验证

- `go test -race ./mobile/... ./transport/simnet/ ./adapter/...` 通过。
- 五个平台二进制内的版本字符串均为 `9781cd6`；架构齐全；Windows 为 GUI 子系统 PE。
- **macOS**：Dart 集成测试用真实 MihomoCore 跑 3 项（Unix socket、TCP + 令牌、错误令牌被拒绝），全部通过；框架实际调用通过。root 实测 TUN：utun 接管默认路由，经 TUN 出网，关闭后路由恢复。
- **iOS**：iPhone 16 Pro 模拟器内实际调用通过；真机 arm64 链接通过；文档中的 NetworkExtension 示例能编译。
- **未做**：
  - Android 真机或模拟器运行，以及 VpnService TUN；
  - iOS NetworkExtension TUN，以及扩展的内存实测；
  - **Windows 上的任何运行**：服务安装、卸载，wintun TUN，PowerShell 和注册表脚本。只做了交叉编译、vet 和代码审查；
  - 客户设备验收。

## 产物身份

- 源码：`vfawn/mihomo` main 分支，提交 `9781cd60dc310dfd77e228863ec876698bcb1c39`，构建前工作区干净。
- 工具链：Go 1.27.1，gomobile（sagernet v0.1.13），Android NDK 28.2，Xcode 26.6（iOS SDK 26.5）。
- 构建标签：Android `with_gvisor,cmfa`；其余平台 `with_gvisor`；Windows 另加 `-H windowsgui`。
- 构建时间（UTC，2026-10-17）：Android 20:03，macOS 框架 20:42、内核 20:42，Windows 20:42，iOS 20:44。

| 资产 | SHA256 |
|---|---|
| `mihomo-sdk-v1.0.0-android.zip` | `1f975b6e067d057bc268aefbcad1c2071fced3b0b0b247c3af0ac3f80cf0745d` |
| `mihomo-sdk-v1.0.0-ios.zip` | `433b35554232f0ac619ed3e7e5277196b548f77951e2fc96f6c4f52a8667284e` |
| `mihomo-sdk-v1.0.0-macos.zip` | `bd418b33a31978ecad285b70d4afe21701de8eb3791c1cfb07a64d29bad56376` |
| `mihomo-sdk-v1.0.0-windows-amd64.zip` | `ab82c7296fec0f04fb0343f1f4148e5f96aa1379bf21d0ba84030e51f3966269` |
| `mihomo-sdk-v1.0.0-windows-arm64.zip` | `fedbe8e091b4f23e42c31c367d6ef0b1c2f649c67956fa40eca98907ac34d74f` |
| `mihomo-sdk-v1.0.0-flutter.zip` | `52ba788254bfd8c878b801be3004a5878537d411a4661661bc01765eb6559a87` |

包内每个二进制的 SHA256 见 `mihomo-sdk-v1.0.0-SHA256SUMS.txt`。
