# Mihomo SDK 接入指南（Android / iOS / macOS / Windows）

> 本文是 **mihomo SDK**（不是 Node，也不是 Rust 的 `dbk-sdk`）的接入指南。文中的 `Bin/` 目录与 Release 资产的对应关系：
> `android/` → `mihomo-sdk-vX.Y.Z-android.zip`，`ios/` → `-ios.zip`，`macos/` → `-macos.zip`，`windows/amd64/`、`windows/arm64/` → `-windows-amd64.zip`、`-windows-arm64.zip`，`flutter/` → `-flutter.zip`，`SHA256SUMS.txt` → `-SHA256SUMS.txt`。

| 项目 | 值 |
|---|---|
| 版本（`Version()` / `getVersion` 返回值） | `9781cd6`，main 分支提交，**所有平台一致**。包含 `97d7ce9` 的 SimNet 连接突发修复（见 5.1 节）和 Windows 服务修复（见 9.1 节） |
| 构建时间（UTC） | 2026-10-17：Android 20:03，macOS 框架 20:42、内核 20:42，Windows 20:42，iOS 20:44 |
| 工具链 | Go 1.27.1，gomobile（sagernet），Android NDK 28.2，Xcode 26.6（iOS SDK 26.5） |
| 构建标签 | Android：`with_gvisor,cmfa`；iOS / macOS / Windows：`with_gvisor`；Windows 另加链接参数 `-H windowsgui`（不显示控制台窗口） |
| 最低系统 | Android 5.0（API 21）；iOS 15.0；macOS 11；Windows 10（x64 / ARM64） |
| 重新构建 | `mobile/` 下：`build-android-multi-arch.sh`、`build-ios.sh`、`build-macos.sh`、`build-macos-core.sh`、`build-windows-core.sh` |

## 0. 平台一览

| 平台 | 产物 | 运行形态 | Dart 端传输方式 | TUN | 需要的权限 |
|---|---|---|---|---|---|
| Android | `android/*.aar` | App 进程内（gomobile） | `ChannelTransport`（默认） | ✅ VpnService fd → `startTun` | VPN 授权（系统弹窗） |
| iOS | `ios/Mihomo.xcframework` | App 或 NetworkExtension 进程内 | `ChannelTransport` | ✅ 仅限 NetworkExtension 扩展内 `startTun` | NetworkExtension 权限（Apple 开发者账号） |
| macOS | `macos/MihomoCore` | 独立内核进程 | `CoreTransport.launchUnix` | ✅ 配置 `tun:` | 一次管理员密码（setuid） |
| macOS | `macos/Mihomo.xcframework` | App 进程内 | `ChannelTransport` | ❌ | 无 |
| Windows | `windows/<arch>/MihomoCore.exe` | SYSTEM 系统服务 | `CoreTransport.connectService` | ✅ 配置 `tun:`（内置 wintun） | 安装服务时一次 UAC |
| Windows | 同上 | 普通用户进程（`serve`） | `CoreTransport.launchTcp` | ❌ | 无 |

所有平台使用**同一套 JSON 方法**（第 3 节），Dart 端的 `MihomoService` 接口完全一样，只是构造时传入的传输方式不同。

## 1. 目录内容

```
Bin/
├── 交付说明.md
├── SHA256SUMS.txt                    所有产物的校验和
├── android/
│   ├── mihomo-arm64-v8a.aar          64 位 ARM（主流手机，推荐）
│   ├── mihomo-armeabi-v7a.aar        32 位 ARM（旧设备）
│   ├── mihomo-x86_64.aar / -x86.aar  模拟器
│   ├── mihomo-universal.aar          四个架构合一
│   └── mihomo-sources.jar            Java 绑定源码
├── ios/
│   └── Mihomo.xcframework            真机 arm64 + 模拟器 arm64/x86_64
├── macos/
│   ├── MihomoCore                    内核进程（arm64 + x86_64），支持 TUN
│   └── Mihomo.xcframework            进程内框架（arm64 + x86_64），不支持 TUN
├── windows/
│   ├── amd64/MihomoCore.exe          x64
│   └── arm64/MihomoCore.exe          ARM64
└── flutter/
    ├── mihomo_service.dart           Dart 封装（类型化方法 + 事件流），各平台通用
    ├── mihomo_transport.dart         传输接口 + ChannelTransport（Android / iOS / macOS 框架）
    ├── MihomoPlugin.java             Android 端 Flutter 插件（纯转发）
    └── desktop/
        ├── core_transport.dart       桌面：与 MihomoCore 的连接（Unix socket / TCP+令牌 / Windows 服务）
        ├── macos.dart                macOS：TUN 授权、系统代理、系统 DNS
        └── windows.dart              Windows：安装/卸载服务、系统代理
```

**Android 选包：** 只用一个 AAR。上架用 `universal`，配合 Gradle `abiFilters`；或者只用 `arm64-v8a`。不要同时放多个 AAR，它们的类名相同，会冲突。

## 2. 调用模型

SDK 对外只有一个 JSON 入口，再加上几个无法用 JSON 表达的平台钩子：

| 导出函数 | 说明 |
|---|---|
| `invokeMethod(json, handler)` | 调用任意方法。立即返回，结果异步回调 `handler.onResult(json)` |
| `setEventListener(handler)` | 设置事件接收者，传 `null` 取消 |
| `startTun(fd, optionsJson, tunHandler)` | Android（VpnService）/ iOS（NetworkExtension）：接管 TUN fd |
| `stopTun()` | 关闭 TUN |
| `updateDns("1.1.1.1,8.8.8.8")` | Android：告诉内核底层网络的 DNS，供 `system` 解析器使用 |
| `version()` | 版本号 |

**请求和响应格式**

```jsonc
// 请求
{"id": "42", "method": "testDelay", "arguments": {"proxy": "s5-via-simnet"}}
// 成功
{"id": "42", "result": {"delay": 151}}
// 失败
{"id": "42", "result": null, "error": {"code": "timeout", "message": "delay test timed out"}}
```

- `id` 由调用方生成，响应原样带回，用来对应请求和响应。
- 回调在 Go 线程上执行。Android 需要 `post` 到主线程再交给 Flutter，iOS / macOS 需要 `DispatchQueue.main.async`。
- 桌面内核进程（macOS `MihomoCore`、Windows `MihomoCore.exe`）通过 socket 传输同样的 JSON：每条消息是“4 字节小端长度 + JSON”。响应是带 `id` 的对象，事件批是数组。这些细节已经封装在 `CoreTransport` 里。
- `initialize`、`setupConfig`、`shutdown` 按调用顺序依次执行，其余方法同时执行，比如可以同时给多个节点测延迟。
- 新增能力只需要改 Go 和 Dart，原生插件不用动。

## 3. 方法参考

| 方法 | 参数 | 返回 | 说明 |
|---|---|---|---|
| `initialize` | `{"homeDir": "/data/.../mihomo"}` | `true` | 必须最先调用；目录不存在时自动创建 |
| `validateConfig` | `{"config": "<yaml>"}` 或 `{"path": "config.yaml"}` | `true` | 只解析配置，不应用 |
| `setupConfig` | 同上 | `true` | 第一次调用即启动，之后再调用就是热重载 |
| `shutdown` | 无 | `true` | 关闭监听端口、TUN、所有连接和出站，隧道在 Node 上的会话立即释放 |
| `isRunning` | 无 | `bool` | |
| `getVersion` | 无 | `string` | |
| `getProxies` | 无 | `{name: proxy}` | 与 RESTful API `/proxies` 格式一致，包含 `type`、`now`、`all`、`history` |
| `changeProxy` | `{"group": "PROXY", "proxy": "simnet-node"}` | `true` | 只对 select 组有效；选择会持久化 |
| `testDelay` | `{"proxy", "url"?, "timeout"?, "expected"?}` | `{"delay": ms}` | 发一次 HTTP 请求测往返；`timeout` 单位 ms，默认 5000；`url` 默认 `https://www.gstatic.com/generate_204`；`expected` 是期望的状态码，如 `"204"` 或 `"200-299"` |
| `getTraffic` | 无 | `{"up", "down"}` | 最近 1 秒的速率，单位：字节/秒 |
| `getTotalTraffic` | 无 | `{"up", "down"}` | 累计字节数 |
| `resetTraffic` | 无 | `true` | 累计流量清零 |
| `getConnections` | 无 | 连接快照 | 与 RESTful API `/connections` 格式一致 |
| `closeConnection` | `{"id": "<连接 id>"}` | `bool` | 返回 `false` 表示连接不存在 |
| `closeConnections` | 无 | `true` | |
| `setMode` | `{"mode": "rule"}` | `true` | 可选 `rule` / `global` / `direct` |
| `setLogLevel` | `{"level": "info"}` | `true` | 可选 `debug` / `info` / `warning` / `error` / `silent` |
| `startLog` / `stopLog` | 无 | `true` | 开启后日志以 `log` 事件推送 |
| `updateDns` | `"1.1.1.1,8.8.8.8"` | `true` | 等同于导出函数 `updateDns` |

**错误码**

| code | 含义 |
|---|---|
| `invalid_method_call` | 请求 JSON 无法解析 |
| `not_implemented` | 方法不存在 |
| `invalid_arguments` | 缺少参数或参数值不合法 |
| `not_initialized` | 还没调用 `initialize` |
| `invalid_config` | 配置解析失败，`message` 里有原因 |
| `not_found` / `not_selectable` | 节点或组不存在 / 该组不是 select 类型 |
| `timeout` / `unavailable` | 测延迟超时 / 测延迟失败 |
| `forbidden` | Windows 服务：`homeDir` 不在安装用户的个人目录内 |
| `core_error` / `internal_error` | 其他内核错误 / 内核内部 panic（已被拦截，不会闪退） |

## 4. 事件

事件按批推送：攒满 64 条或距第一条满 16ms 就发一批。每批是一个 JSON 数组：

```json
[{"type": "log", "data": {"level": "warning", "payload": "...", "time": 1760566000000}}]
```

目前只有 `log` 一种事件，要先调用 `startLog` 才会推送。队列满时新的事件会被丢弃，不会拖慢内核。

## 5. 业务用法：SimNet 隧道 + S5 出口

配置示例：

```yaml
mode: rule
log-level: warning
dns: {enable: false}
proxies:
  - name: simnet-node
    type: simnetv2
    server: node.example.com
    port: 443
    carrier: raw
    security: tls
    sni: node.example.com
    key-id: 1
    psk: "<16 字节 base64url>"
    udp: true
  - name: s5-via-simnet              # 先走 SimNet 隧道，再从 S5 出口出去
    type: socks5
    server: <S5 出口地址>
    port: 1080
    username: <用户名>
    password: <密码>
    dialer-proxy: simnet-node
proxy-groups:
  - {name: PROXY, type: select, proxies: [s5-via-simnet, simnet-node, DIRECT]}
rules:
  - "MATCH,PROXY"
```

Dart 调用：

```dart
final mihomo = MihomoService();
await mihomo.initialize('${(await getApplicationSupportDirectory()).path}/mihomo');
await mihomo.setupConfig(yaml);

// 整条链路的延迟：SDK → SimNet → Node → S5 → 目标
final chain = await mihomo.testDelay('s5-via-simnet');
// 只测隧道这一段
final tunnel = await mihomo.testDelay('simnet-node');

// 测速时每秒轮询一次，得到实时速度
Timer.periodic(const Duration(seconds: 1), (_) async {
  final t = await mihomo.getTraffic();          // 单位：字节/秒
  print('↓ ${t.down * 8 / 1e6} Mbps  ↑ ${t.up * 8 / 1e6} Mbps');
});
```

已默认开启的优化，不需要额外配置：
- SimNet 预建连接：近 60 秒内有新 TCP 连接时，保持最多 2 条已认证的连接备用。
- 冷建连时认证请求和开流请求一起发出。
- S5 握手一次发完，遇到不兼容的服务器会自动回退，并记住这个服务器。

如需关闭，在出站上分别加 `disable-prewarm: true` 或 `disable-handshake-pipelining: true`。

### 5.1 连接突发与载体上限（`97d7ce9` 起）

每条 TCP 连接独占一条 SimNet 载体（协议规定一条载体只承载一条 TCP，Node 不支持多路复用）。每个 `simnetv2` 出站最多同时保持 **256** 条载体，所有出站合计最多 **16** 个握手同时进行。

| 情况 | 旧行为 | 新行为 |
|---|---|---|
| 256 条已占满，又来新连接 | 立即失败：`simnet: carrier admission capacity exhausted` | **排队等待**，有载体释放就按先来先到放行 |
| 排队时有连接 ≥30 秒没有收发数据 | 一直占着名额，直到 Node 300 秒空闲超时 | 关闭其中最久没动的一条，名额给排队的连接。有数据流动的连接不会被关 |
| 等到拨号超时仍没有名额 | — | 失败。错误同时包含 `carrier admission capacity exhausted` 和 `context deadline exceeded`。内核默认拨号超时 5 秒，SimNet 自身上限 30 秒 |
| 预建连接遇到名额已满 | 失败 | 直接放弃，不排队 |

边界：
- 256 没有放宽。Node 没有按用户限制连接数，但每个监听端口的 4096 个连接名额由所有用户共享，满了会直接丢弃新连接，所以单个用户不应占得更多。
- 被回收的空闲连接一般是浏览器 keep-alive 的空闲 HTTP 连接，浏览器会自动重连。长时间不发数据的长连接（例如 30 秒以上没有消息的长轮询）在名额紧张时也可能被关闭，需要应用自己重连。
- 突发比每秒释放速度大太多时，超过 5 秒还没排到的连接仍会失败，日志里能看到上面的错误。这时应在客户端拦截广告/追踪域名，减少连接数。
- 本节新行为在 `97d7ce9` 之后构建的产物里。本次交付全部平台都由 `9781cd6` 构建，都已包含。

## 6. Android 接入

### 6.1 依赖

```gradle
// app/build.gradle
android { defaultConfig { ndk { abiFilters 'arm64-v8a', 'armeabi-v7a' } } }
dependencies { implementation files('libs/mihomo-universal.aar') }
```

需要的权限：`INTERNET`、`ACCESS_NETWORK_STATE`；VPN 服务需要声明 `android.permission.BIND_VPN_SERVICE`。

### 6.2 Flutter 插件

把 `flutter/MihomoPlugin.java` 放进工程，在 `MainActivity.configureFlutterEngine` 里 `flutterEngine.getPlugins().add(new MihomoPlugin())`。Dart 端使用 `flutter/mihomo_service.dart`。插件使用两个通道：
- `MethodChannel("com.mihomo/core")`：只有一个方法 `invoke`，参数是请求 JSON 字符串；
- `EventChannel("com.mihomo/events")`：推送事件批。

### 6.3 TUN（VpnService）

```java
ParcelFileDescriptor tun = new Builder()
        .setSession("Mihomo")
        .addAddress("172.19.0.1", 30)
        .addRoute("0.0.0.0", 0)
        .addDnsServer("172.19.0.2")
        .setMtu(9000)
        .establish();

Mobile.startTun(tun.getFd(),
        "{\"stack\":\"mixed\",\"inet4-address\":[\"172.19.0.1/30\"],"
                + "\"dns-hijack\":[\"172.19.0.2:53\"],\"mtu\":9000}",
        new TunHandler() {
            @Override public boolean protect(int fd) { return MyVpnService.this.protect(fd); }
            @Override public String resolveProcess(int protocol, String src, String dst) {
                return ""; // 需要按应用分流时：API 29+ 用 getConnectionOwnerUid 查 uid，再取包名
            }
        });
// 撤销 VPN 或停止服务时：
Mobile.stopTun();
tun.close();
```

| options 字段 | 默认值 | 说明 |
|---|---|---|
| `stack` | `mixed` | `system` / `gvisor` / `mixed`。`mixed` 的 TCP 走系统协议栈，吞吐最高 |
| `inet4-address` / `inet6-address` | 无 | 必须与 `Builder.addAddress` 一致 |
| `dns-hijack` | 无 | 被劫持交给内核处理的 DNS 地址，如 `172.19.0.2:53` 或 `any:53` |
| `mtu` | 9000 | 与 `Builder.setMtu` 一致 |

要点：
- 内核会复制一份 fd 自己用，原 fd 仍由 App 持有，最后由 App 关闭。
- `protect` 一定要接 `VpnService.protect`，否则内核自己的出站流量会再进 VPN，形成回环。
- 配置 YAML 里**不要**再写 `tun:` 段；TUN 由 `startTun` 单独管理，热重载配置不会影响它。
- 网络切换时，把 `ConnectivityManager` 拿到的底层网络 DNS 通过 `updateDns` 传给内核。
- 不用 TUN 时，也可以在配置里写 `mixed-port`，以本地代理端口的方式使用。

## 7. iOS 接入

1. 把 `ios/Mihomo.xcframework` 拖进 Xcode 工程（Flutter 工程是 `ios/Runner`），选 **Embed & Sign**。
2. Flutter 插件的写法和第 8.2 节 macOS 的 Swift 插件相同，只需把 `import FlutterMacOS` 换成 `import Flutter`，`registrar.messenger` 换成 `registrar.messenger()`。Dart 端使用默认的 `MihomoService()`，也就是 `ChannelTransport`。
3. **不用 TUN 时：** 在配置里写 `mixed-port`，App 内的请求可以走这个本地代理。iOS 不允许普通 App 设置系统代理。
4. **TUN 只能在 NetworkExtension 里做：** 新建一个 *Network Extension* target，在 `NEPacketTunnelProvider` 中嵌入同一个框架：

```swift
import NetworkExtension
import Mihomo

final class PacketTunnelProvider: NEPacketTunnelProvider {
    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.ipv4Settings = NEIPv4Settings(addresses: ["172.19.0.1"], subnetMasks: ["255.255.255.252"])
        settings.ipv4Settings?.includedRoutes = [NEIPv4Route.default()]
        settings.dnsSettings = NEDNSSettings(servers: ["172.19.0.2"])
        settings.mtu = 9000
        setTunnelNetworkSettings(settings) { error in
            if let error { return completionHandler(error) }
            // 1. 用 MobileInvokeMethod 依次调用 initialize（App Group 容器目录）和 setupConfig（不要写 tun: 段）
            // 2. 找到 utun 的 fd 交给内核（tunFileDescriptor 的实现见下方说明）
            var error: NSError?
            MobileStartTun(self.tunFileDescriptor(),
                           "{\"stack\":\"mixed\",\"inet4-address\":[\"172.19.0.1/30\"],\"dns-hijack\":[\"172.19.0.2:53\"],\"mtu\":9000}",
                           nil, &error)
            completionHandler(error)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        MobileStopTun()
        completionHandler()
    }
}
```

要点：
- `tunFileDescriptor()` 的写法是遍历进程的 fd，用 `getsockopt(fd, SYSPROTO_CONTROL, UTUN_OPT_IFNAME)` 找出名字以 `utun` 开头的那个。这是 iOS 上 sing-box、Clash 类客户端的通用做法。
- iOS 不需要 `protect`，扩展自己的流量本来就不进隧道，所以 `TunHandler` 传 `nil`。
- **扩展进程有约 50MB 的内存上限。** 请精简规则和节点，关闭不需要的功能，并在真机上用 Instruments 实测内存占用。
- App 和扩展通过 App Group 共享配置文件；扩展里的调用方式与 App 内相同。
- **本次交付只在模拟器里验证了框架的方法调用，NetworkExtension 隧道没有验证**，需要在真机和开发者账号下联调。

## 8. macOS 接入

macOS 提供两种方式，Dart 层的 `MihomoService` 接口完全相同，只是构造时传入的传输方式不同：

| 方式 | 产物 | 权限 | 能力 | 适用 |
|---|---|---|---|---|
| **A. 内核进程（推荐，参考 FlClash）** | `macos/MihomoCore` | 一次性管理员授权 | 系统代理 + **TUN** | 官网下载分发（Developer ID） |
| B. 进程内框架 | `macos/Mihomo.xcframework` | 无 | 仅本地代理端口 / 系统代理 | 不需要 TUN；或要上 Mac App Store |

### 8.1 方式 A：MihomoCore 内核进程（支持 TUN）

**原理**

1. App 在一个只有自己能进入的临时目录（权限 0700）里开 Unix socket，然后启动 `MihomoCore <socket 路径>`，内核主动连上来。
2. 双方用“4 字节小端长度 + JSON”传消息，方法和参数与 Android 完全一样。
3. 创建 utun 需要 root。第一次开启 TUN 时弹出一次管理员密码框，把 MihomoCore 设为 `root:admin`、权限 `4750`（setuid）。之后 App 正常启动它，它自动以 root 运行。App 本身始终是普通用户。
4. App 关闭 socket、退出或崩溃时，内核会先关闭 TUN、恢复路由，然后退出，不会把网络留在异常状态。
5. 内核以 root 身份在 home 目录里创建的文件，会自动改回当前用户所有。
6. 内核拒绝连接不属于启动用户的 socket，也就是说，内核只为启动它的那个 App 服务。

**集成步骤**

1. **打包：** 在 Xcode 的 Runner target 加一个 *Copy Files* 阶段（Destination 选 *Executables*），把 `MihomoCore` 拷进 `<App>.app/Contents/MacOS/`，并勾选 *Code Sign On Copy*。
2. **关闭 App Sandbox：** 沙盒内无法启动 setuid 程序，也不能运行 `osascript` 提权和 `networksetup`。
3. **Dart 代码：** 用 `flutter/desktop/core_transport.dart`、`flutter/desktop/macos.dart`、`flutter/mihomo_transport.dart`、`flutter/mihomo_service.dart`：

```dart
import 'dart:io';
import 'desktop/core_transport.dart';
import 'desktop/macos.dart';
import 'mihomo_service.dart';

final corePath = '${File(Platform.resolvedExecutable).parent.path}/MihomoCore';

// 开启 TUN 前确保已授权（只在第一次或 App 更新后弹密码框）
final auth = MacCoreAuthorization(corePath);
if (!await auth.isAuthorized) {
  await auth.authorize();          // 拒绝或输错密码会抛异常 → 提示用户，保持非 TUN 模式
}

final transport = await CoreTransport.launchUnix(corePath);     // 授权后再启动
final mihomo = MihomoService(transport);
await mihomo.initialize('${(await getApplicationSupportDirectory()).path}/mihomo');
await mihomo.setupConfig(yamlWithTun);                         // 见下面的 TUN 配置

final dns = MacSystemDns();
await dns.apply();                 // 让系统 DNS 走进 TUN（见下文说明）

// 退出或关闭 TUN 时
await dns.restore();
await transport.stop();            // 内核关闭 TUN、恢复路由后退出
```

注意：
- 授权**之后**启动的进程才有 root 权限。如果内核已经在运行，授权完成后要先 `stop()` 再 `start()`。
- App 更新会替换 MihomoCore，setuid 标记随之丢失，`isAuthorized` 会返回 false，需要重新授权一次。

**TUN 配置**（直接写进 YAML，由 mihomo 自己创建 utun、加路由）：

```yaml
tun:
  enable: true
  stack: mixed                 # TCP 走系统协议栈，吞吐最高
  auto-route: true             # 接管默认路由
  auto-detect-interface: true  # 内核出站自动绑定物理网卡，避免回环
  dns-hijack: ["any:53"]
  route-exclude-address: [10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 224.0.0.0/4, fc00::/7, fe80::/10]
dns:
  enable: true
  enhanced-mode: fake-ip
  nameserver: [https://223.5.5.5/dns-query]
```

关闭 TUN 时，再调用一次 `setupConfig`，把 `tun.enable` 改成 false 即可，属于热更新，不用重启内核。

**为什么需要 `MacSystemDns`：** 系统 DNS 通常是路由器（比如 192.168.1.1）。发往局域网的流量走的是更具体的局域网路由，不进 TUN，mihomo 就看不到这些 DNS 查询，也就无法按域名分流。`apply()` 把系统 DNS 临时改成 `223.5.5.5`，让 DNS 进入 TUN、被 `dns-hijack` 接管；`restore()` 恢复原来的设置。FlClash 也是这么做的。

**不用 TUN 时**也能用这个内核进程：在配置里写 `mixed-port: 7890`，再调用 `MacSystemProxy.enable('127.0.0.1', 7890)` 设置系统代理，退出时调用 `MacSystemProxy.disable()`。这种方式不需要授权。

**安全说明：** 4750 的含义是只有 admin 组成员能执行 MihomoCore，它就以 root 运行。admin 组成员本来就能 `sudo`，所以这不会带来额外的提权，FlClash 也接受了同样的前提。如果对安全要求更高，请走 NetworkExtension 方案（另行开发）。

### 8.2 方式 B：Mihomo.xcframework（进程内，无 TUN）

1. 把 `macos/Mihomo.xcframework` 拖进 Xcode 工程，在 *Frameworks, Libraries, and Embedded Content* 里选 **Embed & Sign**。
2. 如果开启了 App Sandbox，需要打开 *Outgoing Connections (Client)*；监听本地端口还要打开 *Incoming Connections (Server)*。
3. Swift 版 Flutter 插件如下，通道名与 Android 一致，Dart 端用 `ChannelTransport`，也就是默认的 `MihomoService()`：

```swift
import Cocoa
import FlutterMacOS
import Mihomo

final class CallbackHandler: NSObject, MobileResultHandlerProtocol {
    let deliver: (String) -> Void
    init(_ deliver: @escaping (String) -> Void) { self.deliver = deliver }
    func onResult(_ data: String?) throws {
        let json = data ?? ""
        DispatchQueue.main.async { self.deliver(json) }
    }
}

final class MihomoPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = MihomoPlugin()
        FlutterMethodChannel(name: "com.mihomo/core", binaryMessenger: registrar.messenger)
            .setMethodCallHandler(plugin.handle)
        FlutterEventChannel(name: "com.mihomo/events", binaryMessenger: registrar.messenger)
            .setStreamHandler(plugin)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "invoke", let json = call.arguments as? String else {
            return result(FlutterMethodNotImplemented)
        }
        MobileInvokeMethod(json, CallbackHandler { result($0) })
    }

    func onListen(withArguments _: Any?, eventSink sink: @escaping FlutterEventSink) -> FlutterError? {
        MobileSetEventListener(CallbackHandler { sink($0) })
        return nil
    }

    func onCancel(withArguments _: Any?) -> FlutterError? {
        MobileSetEventListener(nil)
        return nil
    }
}
```

在 `MainFlutterWindow.swift` 里注册：`MihomoPlugin.register(with: flutterViewController.registrar(forPlugin: "MihomoPlugin"))`。

### 8.3 和 FlClash 的对照

| | FlClash | 本 SDK |
|---|---|---|
| 内核进程 | FlClashCore，setuid root（osascript 授权，4750） | MihomoCore，做法相同 |
| 通信 | App 开 0600 的 socket，内核连上来，长度前缀 + JSON | App 在 0700 目录里开 socket，内核连上来并校验 socket 属主，长度前缀 + JSON |
| 方法协议 | 和 Android 同一套 | 和 Android 同一套（`mobile` 包的方法分发） |
| TUN | 配置写 `tun:`，由 sing-tun 建 utun 和路由 | 相同 |
| 系统代理 / DNS | `networksetup`；DNS 追加 223.5.5.5 | `networksetup`；DNS 临时替换，退出时恢复 |
| root 创建的文件 | 改回用户所有 | 相同 |
| NetworkExtension | 不使用 | 不使用 |

## 9. Windows 接入

Windows 上创建 wintun 网卡、修改路由需要管理员权限。做法参考 FlClash 的 FlClashHelperService，但用 Go 实现，并且和内核是同一个 `MihomoCore.exe`：

| 方式 | 命令 | 权限 | 能力 |
|---|---|---|---|
| 系统服务（TUN） | `MihomoCore.exe service install --user-sid <SID>` / `uninstall` / `run` | 安装时一次 UAC，之后以 SYSTEM 运行 | 系统代理 + **TUN** |
| 普通进程 | `MihomoCore.exe serve --token-file <文件>` | 无 | 本地代理端口 + 系统代理 |

### 9.1 原理

1. **安装**，由 `WindowsCoreService.install` 发起，弹一次 UAC：
   - 把 exe 复制到 `%ProgramFiles%\MihomoSDK\MihomoCore.exe`。这个目录只有管理员能写，避免普通用户替换以 SYSTEM 身份运行的程序。
   - 创建 `%ProgramData%\MihomoSDK\`，设置受保护的权限：SYSTEM 和管理员完全控制，安装用户只读，其他人无权访问。在里面生成 32 字节的随机令牌，并记下安装用户的 SID。
   - 注册为开机自启的服务 `MihomoSDK`，设置故障恢复（内核崩溃后 5 秒自动重启），然后启动。
   - 重装时，旧程序先改名再放入新版。服务刚停止时进程可能还占着 exe，Windows 不允许覆盖，但允许改名。删除旧服务后如果遇到“已标记为删除”，会重试重建。
2. **运行**：服务在 `127.0.0.1` 的随机端口监听，把端口写进 `%ProgramData%\MihomoSDK\endpoint`。服务停止时、重装开始前都会先删除这个文件，避免 App 按旧端口连到别的本地程序，把令牌发出去。
3. **连接**：App 读取端口和令牌，连上后第一条消息发送令牌。服务回复 `{"ready":true}` 后，双方进入和 macOS 相同的“长度前缀 + JSON”通信；令牌不对，服务直接断开连接。
4. **会话**：同一时间只服务一个 App。新的连接认证通过后会接管旧会话，覆盖 App 崩溃后重启的情况。连接断开时，服务关闭本次会话（包括 TUN 和路由），服务本身继续运行。
5. **加固**：`initialize` 传入的 `homeDir` 必须在安装用户的个人目录内（从注册表 `ProfileList` 读取），否则返回 `forbidden` 错误，防止借 SYSTEM 权限往任意目录写文件。

### 9.2 集成步骤

1. 把对应架构的 `MihomoCore.exe` 放在 App 主程序旁边，即 Flutter Windows 构建输出目录。exe 编译时已经设为不显示控制台窗口。
2. Dart 代码，使用 `flutter/desktop/core_transport.dart`、`flutter/desktop/windows.dart`、`flutter/mihomo_transport.dart`、`flutter/mihomo_service.dart`：

```dart
import 'dart:io';
import 'desktop/core_transport.dart';
import 'desktop/windows.dart';
import 'mihomo_service.dart';

final corePath = '${File(Platform.resolvedExecutable).parent.path}\\MihomoCore.exe';

// TUN：确保服务已安装（只在首次和 App 更新后弹 UAC）
if (!await WindowsCoreService.isInstalled) {
  await WindowsCoreService.install(corePath);     // 用户拒绝 UAC 会抛异常 → 提示用户，退回非 TUN 模式
}
final transport = await CoreTransport.connectService();
final mihomo = MihomoService(transport);
if (await mihomo.getVersion() != bundledVersion) {
  // App 已更新而服务还是旧版：重装服务以替换 %ProgramFiles% 里的程序，然后重新连接
  await transport.stop();
  await WindowsCoreService.install(corePath);
}
await mihomo.initialize('${Platform.environment['LOCALAPPDATA']}\\YourApp\\mihomo'); // 必须在个人目录内
await mihomo.setupConfig(yamlWithTun);
// ...
await transport.stop();                           // 服务关闭本次会话的 TUN，服务继续运行

// 不需要 TUN 时（无需管理员权限）：
final userCore = await CoreTransport.launchTcp(corePath);
await MihomoService(userCore).setupConfig(yamlWithMixedPort);
await WindowsSystemProxy.enable('127.0.0.1', 7890);   // 退出时 WindowsSystemProxy.disable()
```

3. **卸载 App 时**调用 `WindowsCoreService.uninstall(corePath)`（弹 UAC），会删除服务、`%ProgramFiles%\MihomoSDK` 和 `%ProgramData%\MihomoSDK`。

**Windows 的 TUN 配置：**

```yaml
tun:
  enable: true
  stack: mixed
  auto-route: true
  auto-detect-interface: true
  dns-hijack: ["any:53"]
dns:
  enable: true
  enhanced-mode: fake-ip
  nameserver: [https://223.5.5.5/dns-query]
```

### 9.3 安全说明

- 能读到令牌的只有 SYSTEM、管理员和安装用户。同一用户下运行的其他程序也能读到，这和 macOS 方案的前提相同，FlClash 也一样：它校验的是调用进程的 SID，同样防不住同一用户下的程序。
- 服务以 SYSTEM 运行，数据目录限定在用户个人目录内。但用户个人目录里的目录联接（junction）理论上仍可能把写入引向别处。所以只建议给本机管理员账户安装，这和 FlClash 的前提一致。

### 9.4 和 FlClash 的对照

| | FlClash | 本 SDK |
|---|---|---|
| 服务程序 | 单独的 Rust 程序 FlClashHelperService | 和内核同一个 `MihomoCore.exe`（`service` 子命令） |
| 服务怎么运行内核 | 服务另外启动 FlClashCore.exe，并校验它的 SHA256 | 服务进程本身就是内核；程序复制到只有管理员能写的 `%ProgramFiles%` |
| 调用方认证 | HTTP `127.0.0.1:47890`，校验调用进程 SID 和安装者是否一致 | 回环 TCP 随机端口 + 令牌，令牌文件受目录权限保护 |
| App 与内核通信 | 命名管道，长度前缀 + JSON | 回环 TCP，长度前缀 + JSON |
| TUN | 配置 `tun:`，sing-tun 内置 wintun | 相同 |

## 10. 验证记录

所有产物都由提交 `9781cd6` 构建（包含 `97d7ce9`），每个二进制里的版本号都已核对为 `9781cd6`。本次重建后重新做了下表的检查。

| 本次（`9781cd6`）重建 | 方法 | 结果 |
|---|---|---|
| SimNet 突发准入（`97d7ce9`） | `go test -race ./transport/simnet/ ./adapter/...` | 在 `9781cd6` 上重跑通过。新增用例：超过 256 的 64 条突发连接，在载体释放后全部成功并能收发数据；`ctx` 超时、取消、`Client.Close` 时如实失败，名额归零；goroutine 回到基线；最久空闲的流被回收，活跃流不被回收 |
| SDK 单元测试 | `go test -race ./mobile/...` | 通过 |
| 产物检查 | 版本字符串、`lipo`、AAR 结构、PE 格式 | 五个平台的版本号都是 `9781cd6`；架构齐全；Windows 为 GUI 子系统 |
| macOS 内核 | Dart `test/core_process_test.dart`，使用真实 MihomoCore | 3 项通过 |
| macOS 框架 / iOS 模拟器 | Swift 链接调用 `initialize` → `setupConfig` → `changeProxy` → `isRunning` → `shutdown` | 全部正确；iOS 真机架构链接成功 |

以下是各平台的完整验证记录（Windows 一行已按本次审查结果更新）：

| 平台 / 项目 | 方法 | 结果 |
|---|---|---|
| Go 单元测试 | `go test -race ./mobile/...` | 通过。`mobile`：调用格式错误、完整生命周期、日志批量推送。`sdkcore`：Unix socket 会话；关闭后用相同配置再次 setup，端口能重开；App 断开后内核退出；TCP 令牌校验（错误令牌、过短令牌）；新连接接管旧会话，旧会话的端口被关闭；`homeDir` 越界返回 `forbidden`；`serve` 拒绝非回环地址 |
| Go 交叉检查 | `go vet`：macOS / Linux / Windows / Android(cmfa) / iOS | 通过 |
| **Android** | AAR 结构检查 | 四个 ABI 的 `libgojni.so` 和 `classes.jar` 齐全，版本号正确。**没有在真机或模拟器上运行**，VpnService TUN 需要接入时联调 |
| **iOS** | 用 Swift 链接框架：真机 arm64 编译链接，模拟器实际运行（iPhone 16 Pro） | 在模拟器里依次调用 `initialize` → `setupConfig` → `changeProxy` → `isRunning` → `shutdown`，全部正确。文档中的 NetworkExtension 示例能编译通过。**扩展内的 TUN 没有验证** |
| **macOS 框架** | Swift 链接后实际调用 | 同上 5 个调用全部正确 |
| **macOS 内核** | Dart `test/core_process_test.dart`，使用真实 MihomoCore | 3 项通过：Unix socket 传输、TCP + 令牌传输（每项都覆盖初始化、应用配置、本地端口可连、3 路并发测延迟、错误码、日志事件、停止后进程退出且端口关闭）、错误令牌被拒绝 |
| **macOS TUN** | root：`sudo MIHOMO_TUN_TEST=1 go test -tags with_gvisor -run TestCoreTunAsRoot -v ./mobile/sdkcore` | 2026-10-16 在本机通过：utun6 接管默认路由，经 TUN 连上 1.1.1.1:443；关闭后网卡被移除，路由恢复到 en0 |
| **Windows** | 交叉编译；Windows 版 `go vet`，以及 amd64 / arm64 的测试程序编译；PE 格式检查（GUI 子系统，x64 / ARM64）；确认 wintun 已内嵌在 exe 里，无需额外 DLL；对服务代码逐行审查，修复了重装覆盖失败、服务已标记删除、同路径自我覆盖、缺少故障恢复、旧端口泄露令牌共 5 个问题；通信层（TCP + 令牌、会话接管、homeDir 限制）已在 macOS 上用同一份代码测过 | **服务的安装、运行、卸载，wintun TUN，以及 PowerShell / 注册表脚本都没有在 Windows 上运行过**（本机没有 Windows 环境），需要在 Windows 10/11 上联调 |

## 11. 与旧版 SDK 的差异

旧版的 `Mobile.getInstance()` 及其方法（`loadConfigFromString`、`start`、`stop` 等）已经删除。迁移对照：

| 旧接口 | 新接口 |
|---|---|
| `initialize(homeDir)` | `initialize {homeDir}` |
| `loadConfigFromString` / `loadConfigFromPath` + `start()` | `setupConfig {config}` / `setupConfig {path}` |
| `stop()` | `shutdown` |
| `testConfig(path)` | `validateConfig {path}` |
| `getTrafficStats()` | `getTraffic` / `getTotalTraffic` |
| `setLogLevel` / `getVersion` / `isRunning` | 同名方法 |
| `writeConfigFile` / `readConfigFile` / `loadConfigFromBase64` | 由 Dart 自己处理（文件读写、Base64 解码） |

旧版还有一个 bug：`applyConfig` 传给内核的是空配置，加载的配置实际没有生效。新版已经修复。
