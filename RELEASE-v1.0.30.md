# v1.0.30 — Node 独立 TCP 中继降 CPU（wire 不变）

本版发布 Node 两个 Linux GNU 架构，内部版本仍为 **0.4.28**（Cargo 版本未变）。相对 v1.0.29
只改 Node 中继的写出与读缓冲路径，**线上协议与配置不变**。Node 包不包含 SDK 或 Android App。

## 配套升级要求

与 v1.0.29 相同：SimNet 每条 TCP 独立建连（capability bit3），须与嵌入 SDK **0.4.28** 的客户端配套，
旧共享 TCP 客户端仍不能混用。从 v1.0.29 升到 v1.0.30 **不需要**换客户端，也不需要改配置；
`node.toml` 样例与 systemd 单元与 v1.0.29 逐字节相同。

## 主要变化

- **Single writer 批量写出**（`dbk-proto-simnet`）：已排队的 Data 至多 4 帧合并为一次写出、
  一次 flush；每帧仍各自独立 nonce/HMAC，帧格式不变。
- **ByteBridge 合并读**（`dbk-mux`）：Bytes 模式 `poll_read` 一次取走已排队的多个块，少一轮唤醒。
- **relay 缓冲自适应**（`dbk-node-state`）：中继读缓冲从 16 KiB 起，读满后扩至 64 KiB。
- 提交说明记录的实测：下行每 GB Node CPU **-28%**、上行 **-12%**。本次发布没有在节点上重新跑分，
  该数字不代表现场吞吐提升。

## 本地验证

- 与 v1.0.29 的源码输入清单（SHA256 `fe7c3374…`）逐文件对比：构建输入只差上述 9 个源文件；
  包内 `dbk-node.service`、`node.toml.example` 与 v1.0.29 逐字节相同。
- 改动范围测试：`dbk-node-state` `tcp_relay` 8 项、`dbk-mux` `byte_bridge` 19 项、
  `dbk-proto-simnet` `single` 29 项全部通过。
- 静态包校验：两架构 `VERSION` 为 `dirty=false`，ELF 依赖 GLIBC 最高 2.28。
- 隔离加载冒烟：ARM64 Debian 10 与 AMD64 Ubuntu 20.04 容器内 `--network none --read-only`
  执行 `dbk-node --check`，均 **exit 0**（配置校验通过），未启动监听或业务流量。
- **未做**：完整 workspace 测试 / CI、节点部署与现场吞吐对比、客户设备验收。

## 产物身份

- GitHub 安装仓库标签：`npanel-dev/Daybreak v1.0.30`；该 tag 的提交只标识脚本/文档，不是 Rust 实现源码。
- Rust 分支：`dev/simnet-session-isolation`；源码提交 `d500a8480be0e2abcd9aa90f4ce4ddcc6affc573`，
  **构建前工作区干净**（`dirty=false`）；内部版本 `0.4.28`。
- Cargo.lock SHA256：`52492e560c95c88234dfb97d6983393f5106bd4431cf0e0d7e253d888442df1e`。
- 工具链：`rustc 1.94.1 (e408947bf 2026-03-25)`；Node 构建时间（UTC）：x86_64
  `2026-10-15T20:42:33Z`，aarch64 `2026-10-15T20:42:44Z`。

| 产物 | SHA256 |
|---|---|
| `dbk-node-x86_64-unknown-linux-gnu.tar.gz` | `59f0e552048c04e57c71a4dac92c072db21574ff873e6ea419dd3032fa42cd23` |
| 包内 `dbk-node`（x86_64） | `b7f8f041c06a903f2451bd61ca6ef689bef8246c5caba3ce93d54df7e271b830` |
| `dbk-node-aarch64-unknown-linux-gnu.tar.gz` | `43f705ac61c7f5b13c84353f65b1bea60f3e50bb8343655b356540c9e52bedbf` |
| 包内 `dbk-node`（aarch64） | `792167b467ba0b76292ecb21e2581004ce22125b1823929df56341cb66d44323` |

四个 release 资产为两架构 tar.gz 及各自同名 `.sha256`；包内保留可执行文件、
systemd 单元、配置样例与 `VERSION`。

## 升级

已装机器重跑 `install.sh` 即升级到本版（自动取 Releases latest、只换二进制、保留配置）。
升级前先确认 `/etc/daybreak/node.toml` 里的 `report_online`：为 `false` 时须带 `--no-report-online`。
