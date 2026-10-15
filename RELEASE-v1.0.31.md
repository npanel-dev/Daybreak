# v1.0.31 — 修复认证门等待导致的监听自锁

本版发布 Node 两个 Linux GNU 架构，内部版本仍为 **0.4.28**（Cargo 版本未变）。相对 v1.0.30
只改 Node 监听的准入逻辑，**线上协议与配置不变**。Node 包不包含 SDK 或 Android App。

## 配套升级要求

与 v1.0.29 / v1.0.30 相同：SimNet 每条 TCP 独立建连（capability bit3），须与嵌入 SDK **0.4.28**
的客户端配套，旧共享 TCP 客户端仍不能混用。从 v1.0.29 / v1.0.30 升到 v1.0.31 **不需要**换客户端，
也不需要改配置；`node.toml` 样例与 systemd 单元与 v1.0.30 逐字节相同。

**v1.0.29 / v1.0.30 的节点建议尽快升级**：下面这个问题在多用户同时建连时可稳定触发。

## 修复

- **监听自锁**（`apps/dbk-node/src/listener.rs`）：accept 循环在准入时原地等待进程级认证门
  （16 个许可），等待期间不再推进已准入的连接；而许可只在这些连接认证结束时归还。
  第 17 条已接受的连接会让**整个监听停转**，直到 30 秒阶段期限才恢复。客户端连发
  ClientOpen/Open、或多个用户同时建连即可复现，表现为节点间歇性 30 秒连不上。
- 现在等门时与已准入连接的推进同处一个 `select`，许可能被及时归还；worker panic 仍按原合同上报。

## 本地验证

- 新增回归测试 `waiting_for_the_authentication_gate_keeps_admitted_handshakes_running`：
  还原修复后**失败**、修复后通过（发布前实测）。`dbk-node` 监听相关 6 项测试全部通过。
- 静态包校验：两架构 `VERSION` 为 `dirty=false`，ELF 依赖 GLIBC 最高 2.28。
- 隔离加载冒烟：ARM64 Debian 10 与 AMD64 Ubuntu 20.04 容器内 `--network none --read-only`
  执行 `dbk-node --check`，均 **exit 0**（配置校验通过），未启动监听或业务流量。
- **未做**：完整 workspace 测试 / CI、节点部署与现场多用户并发验证、客户设备验收。

## 产物身份

- GitHub 安装仓库标签：`npanel-dev/Daybreak v1.0.31`；该 tag 的提交只标识脚本/文档，不是 Rust 实现源码。
- Rust 分支：`dev/simnet-session-isolation`；源码提交 `0f93c81071c84a472d99cf9a9de6429a47b63adf`，
  **构建前工作区干净**（`dirty=false`）；内部版本 `0.4.28`。
- Cargo.lock SHA256：`52492e560c95c88234dfb97d6983393f5106bd4431cf0e0d7e253d888442df1e`（与 v1.0.30 相同）。
- 工具链：`rustc 1.94.1 (e408947bf 2026-03-25)`；Node 构建时间（UTC）：x86_64
  `2026-10-15T21:43:26Z`，aarch64 `2026-10-15T21:43:36Z`。

| 产物 | SHA256 |
|---|---|
| `dbk-node-x86_64-unknown-linux-gnu.tar.gz` | `b966fca3a9886e7f7894afe2522eb1342db67da9b82a1099d45e38082fc7562f` |
| 包内 `dbk-node`（x86_64） | `a8907fcf7416cdafc59998c3a6e46b352fb7318c1125a66eb792cc6746959131` |
| `dbk-node-aarch64-unknown-linux-gnu.tar.gz` | `0ed0e78dfa194afd4f802fef88adf146f760d8b39602a4ba1761b1658e57a6c6` |
| 包内 `dbk-node`（aarch64） | `c50bec036065733438a62ce366ad9ef0bbb991439a6b4ee4f86e56d27ab40729` |

四个 release 资产为两架构 tar.gz 及各自同名 `.sha256`；包内保留可执行文件、
systemd 单元、配置样例与 `VERSION`。

## 升级

已装机器重跑 `install.sh` 即升级到本版（自动取 Releases latest、只换二进制、保留配置）。
升级前先确认 `/etc/daybreak/node.toml` 里的 `report_online`：为 `false` 时须带 `--no-report-online`。
