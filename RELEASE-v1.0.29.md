# v1.0.29 — SimNet 每 TCP 独立连接、UDP 按关联复用

本版发布 Node 两个 Linux GNU 架构，内部版本 **0.4.28**；配套客户端 SDK 为
**0.4.28**，本批重编 Android 与 macOS。Node 包不包含 SDK 或 Android App。

## 配套升级要求

本版改变 SimNet TCP 连接模型，**不能与旧共享 TCP 客户端混用**。新 SDK 与新 Node
通过已认证 capability bit3 确认独立 TCP；新 SDK 连接不支持 bit3 的旧 Node 时，在
业务 Open 前失败。新 Node 的 Datagram 会话只接受 UDP，不接受旧 TCP mux Open。
没有 shared 配置、旧池旋钮或自动回退；旧 `session_pool_size` JSON 键明确拒绝。

请将 Node 与嵌入 SDK 0.4.28 的客户端配套切换。旧发布中的「新旧任意组合互通」
不适用于本版。本次只重编 Android/macOS SDK，其余平台的旧库不能标为支持新模型。
普通 VLESS 的协议路径没有因此改成 SimNet；本次升级要求针对 SimNet TCP。

## 主要变化

- 每条 TCP 业务重新建立独立 TCP/TLS/carrier 和认证会话，最多一个 TCP Open。
  Raw、H2、WebSocket 和已有 XHTTP 分支都经过同一实际拨号路径，不共享父 TCP。
  TCP 专用 IO 使用实际缓冲和背压，不使用旧应用信用、WU 或通用 TCP mux actor。
- UDP 同一入口关联共用一条 Datagram 会话，关联内各目标分别开流；不同关联、
  节点配置或授权域不共享会话。保留原 Datagram 帧、认证和数据报边界。
- 配套有界资源账本、认证拨号门、取消与真实关闭屏障。SDK 的 64 MiB 是自管
  backing 额度，256 是 owner 总上限；不能解释成进程 RSS 或 256 个 UDP 会话保证。
  TLS/H2/WS、relay、内核与 TUN 缓冲另计。
- 初始准入/首 Open 为 30 秒；已交付业务空闲或写出无进展为 300 秒；单向 FIN
  后按 30 秒无业务进展收尾，正常 full Drop 以同一个 30 秒绝对期限覆盖主任务和
  载体后代。已开始的系统 DNS 不能靠 abort 强停，真实 join/stop 可能超过 30 秒。
  更短调用方期限仍优先；撤权和 stop 立即取消，不继续排空禁止的字节。
- 防重放记录覆盖原 30 秒槽、±2 槽的完整 150 秒跨度，进程内共享，不随短 TCP
  或监听重建清空。没有重新分配历史 bit2、修改旧固定认证向量或增加未分配 TLV。
- 用户速率桶继续由同 key 的全部会话、两个方向共享。无 producer 时仍保留未补满
  的桶债务，重连不能白领满桶；仅无 producer 且桶已补满或原 rate=0 才回收。
  原速率、桶深、IP 设备去重、read 字节计费算法保持。
- SDK `session=null`，新增 `outbound_connections` 表示同寿资源账本；保留原
  `connections.*` 业务路由计数。探测成功不代表持续 established，也不是单独的 VPN
  健康判据。C ABI 未改。

## 本地验证与性能边界

本次功能验收来自指定单元/文件及先前阶段证据，未重新执行完整 workspace/CI。
Raw 8 个并行 TCP 对应 8 carrier/8 Open；同关联两目标为 1 carrier/2 Open，另一
关联使总数成为 2 carrier/4 Open。四份回显及真实收尾后的 owner/dial/backing 均核验。
此前 Raw/H2/WS/XHTTP 的 90 秒停读恢复证据保留；256 idle 仅验证了 Raw。
限速债务先 RED，修改文件 6/6 与维护单元 2/2 GREEN；SDK DNS 业务边界 3/3、
FFI JSON 4/4、实际 FFI 入口 1/1，以及修改范围的 lint/格式/实际 AST 核验通过。

本机性能采集五组×0/10/25/100 ms，共 **20 例结束，不是 20 例全通过**。
新 Single 与实际普通 VLESS/REALITY 各 4/4 成功；变更前 913 项 dirty 输入的冻结
旧构建，以及同旧信用引擎 shared/independent 两组，共 12 例在慢消费者恢复时截断，
旧 executable exit=101、运行器 exit=1 均保留。该旧快照不是 v1.0.28 发布包。
新成功组实际停读至少 90 秒后完整校验 64 MiB，再完成双向各 8 MiB；Single 的
Node 根关闭四例观察完成，外部 Xray 的该字段为 null。

该负荷每方向总限速约 100 Mbps，延迟为用户态字节交付延迟，不能证明真实 TCP
RTT、丢包或最高吞吐。新 Single 没有显示比 VLESS 更快，冷连接 TTFB 较高。
旧引擎改成物理独立仍截断，因此共享不是全部稳定性问题的解释；旧 typed 关闭原因
缺失，不把整套 IO/预算/生命周期变化唯一归因删除信用。性能证据来自优化测试产物，
不能代替以下重新构建的 release 二进制现场跑分。

完整 CI、实际 TUN、同 S5 第二跳、真实丢包、Vision 内层 TLS及部署/真机接受仍
未验收；本次两架构 Node 与 Android/macOS 出包不等于五平台 SDK 全部重新验收。
最终静态包校验与隔离加载冒烟结果：**两个架构静态包/ELF/GLIBC≤2.28校验通过；ARM64 Debian 10 与 AMD64 Ubuntu 20.04 的 --network none / --check 均 exit0，未启动监听或业务流量**。

## 产物身份

- GitHub 安装仓库标签：`npanel-dev/Daybreak v1.0.29`；安装仓库提交：
  以该 tag 的实际 Git 提交为准（安装脚本基线 a16ec844）。该提交只标识脚本/文档，不是 Rust 实现源码。
- Rust 分支：`dev/simnet-session-isolation`；内部版本：`0.4.28`。
- Rust 起点 HEAD：`f4fb96812bd64f9ab5e1a860cf6eb70493e331ea`；构建输入 dirty：`true`。
  若为 dirty，HEAD 只标识起点；完整输入由下面的快照摘要标识，不能称干净提交构建。
- 本批源码输入清单：`本地 target/simnet-isolation-release-20261014/source-inputs.json（只发布二进制包，不上传源码快照）`；SHA256：
  `fe7c3374ace33669718b4d5e4dcc2a6517bf8d6dc4d5ceda72f45652c488d692`；Cargo.lock SHA256：`52492e560c95c88234dfb97d6983393f5106bd4431cf0e0d7e253d888442df1e`。
- 工具链：`rustc 1.94.1 (e408947bf 2026-03-25)`；Node 构建时间（UTC）：x86_64
  `2026-10-13T22:28:22Z`，aarch64 `2026-10-13T22:28:57Z`。

| 产物 | SHA256 |
|---|---|
| `dbk-node-x86_64-unknown-linux-gnu.tar.gz` | `fd3e05dfc83ec59cead1d330e482738b56cde661e8d2aa0de8131829a36cf41c` |
| 包内 `dbk-node`（x86_64） | `1de2650831ad7a193cd91adacc1eebd4d2dd660f70c9e4a5af9e69709a7bdea3` |
| `dbk-node-aarch64-unknown-linux-gnu.tar.gz` | `28128d91784c657b6ebe6821a525831d79489bbb7d9ae7a4dcf765016c1fa2f2` |
| 包内 `dbk-node`（aarch64） | `ab0e830d8e988980a83227cd1c75a7e04016d83059f2187d9f3c7964696b956f` |

四个 release 资产为两架构 tar.gz 及各自同名 `.sha256`；包内保留可执行文件、
systemd 单元、配置样例与 `VERSION`，GNU/glibc 静态核验上限为 2.28。

## 配套 SDK 0.4.28

Android：`bin/android/daybreak.aar`、arm64-v8a/x86_64 JNI/C 库。
macOS：`bin/macos/libdbk_ffi.a` 与 `libdbk_ffi.dylib`，arm64+x86_64 universal，
另有 `bin/macos/daybreak.xcframework` 仅 macOS 新切片。完整旧 `bin/apple` 仍为 0.4.27。
源码输入、每个新产物哈希及实际构建/验证范围记录在更新后的
`bin/sdk-build-manifest.json`、平台 `VERSION` 和校验和清单中。
SDK 交付组包时间（UTC）：`2026-10-13T22:33:31.197611+00:00`。manifest 和各文件的 SHA256 以本地
`bin/SHA256SUMS` 为准；其他保留平台继续标注其原身份，不冒充本批新构建。
