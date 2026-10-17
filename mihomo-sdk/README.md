# Mihomo SDK（客户端 SDK）

> **这不是 Daybreak Node，也不是 Rust 的 `dbk-sdk`。**
> 本目录发布的是基于 [mihomo](https://github.com/MetaCubeX/mihomo) 内核的客户端 SDK：内置 SimnetV2 出站，供 Android / iOS / macOS / Windows 的 Flutter（Dart）客户端集成。
> - 标签统一为 `mihomo-sdk-vX.Y.Z`，资产统一以 `mihomo-sdk-` 开头。Node 的标签是 `vX.Y.Z`，资产是 `dbk-node-*`，两者互不混用。
> - SDK 的 Release **不会标为 Latest**，`install.sh` 默认安装和升级的仍然是 Node。

## 版本

| SDK 版本 | 内核源码提交 | 要求的 Node | 说明 |
|---|---|---|---|
| [mihomo-sdk-v1.0.0](RELEASE-mihomo-sdk-v1.0.0.md) | `vfawn/mihomo@9781cd6` | **v1.0.29+**（内部 0.4.28），建议 v1.0.31 | 首个发布：四个平台 + 统一 JSON 接口 + 桌面 TUN |

## 下载

从 [Releases](https://github.com/npanel-dev/Daybreak/releases) 中以 `mihomo-sdk-` 开头的版本下载：

| 资产 | 内容 |
|---|---|
| `mihomo-sdk-vX.Y.Z-android.zip` | 四个单架构 AAR + universal 合集 + 源码 jar |
| `mihomo-sdk-vX.Y.Z-ios.zip` | `Mihomo.xcframework`（真机 + 模拟器） |
| `mihomo-sdk-vX.Y.Z-macos.zip` | `MihomoCore`（内核进程，支持 TUN）+ `Mihomo.xcframework`（进程内，不支持 TUN） |
| `mihomo-sdk-vX.Y.Z-windows-amd64.zip` / `-windows-arm64.zip` | `MihomoCore.exe`（系统服务提供 TUN，或普通进程） |
| `mihomo-sdk-vX.Y.Z-flutter.zip` | Dart 封装与桌面传输层、Android 插件 |
| `mihomo-sdk-vX.Y.Z-SHA256SUMS.txt` | 上述资产及包内二进制的校验和 |

## 文档

- [接入指南](GUIDE.md)：调用模型、方法参考、各平台接入、TUN 方案、验证记录。
- 各版本的发布说明：`RELEASE-mihomo-sdk-vX.Y.Z.md`。

## 与 Node 的配套

SimNet 每条 TCP 独立建连（capability bit3），UDP 按入口关联复用 Datagram 载体，与 Node v1.0.29+ 配套。连接 ≤ v1.0.28 的旧共享复用 Node 会在业务开流前失败，没有回退。v1.0.29 / v1.0.30 的节点存在多用户同时建连时的监听自锁问题，**建议先把节点升到 v1.0.31**。SDK 一侧把握手许可一直持有到 ServerAccept，单个客户端自己不会触发这个问题；但多个用户同时建连时，仍需要节点升级到 v1.0.31 才能修复。
