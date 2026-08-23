# Daybreak Node

SimnetV2 节点的安装与卸载脚本。二进制在 [Releases](https://github.com/npanel-dev/Daybreak/releases)。

本仓库**只有脚本和文档**，不含源码。

---

## 安装

```bash
wget -N https://raw.githubusercontent.com/npanel-dev/Daybreak/main/install.sh \
  && bash install.sh \
     --api-host https://panel.example.com \
     --server-id 1 \
     --secret-key <面板通信密钥>
```

三个参数就够了。**端口、安全层、REALITY 密钥、载体、路径全部来自面板**——
本机只需要知道「面板在哪、我是几号、密钥是什么」。

装完即启动，并设为开机自启。

## 升级

再跑一次，不带任何参数：

```bash
bash install.sh
```

自动取 Releases 里的最新版、替换二进制、重启服务。**配置原样保留**，
输出会告诉你从哪个版本换到了哪个版本。

## 卸载

```bash
bash uninstall.sh            # 保留配置与流量账本
bash uninstall.sh --purge    # 全部删除
```

缺省保留 `/etc/daybreak`（含面板密钥）与 `/var/lib/daybreak`
（含**尚未上报的流量账本**）。重装会直接沿用，不必重新配置。

---

## 环境要求

| 项 | 要求 |
|---|---|
| 系统 | Debian 10+ / Ubuntu 20.04+ / 任何 glibc ≥ 2.28 的发行版 |
| 架构 | x86_64（amd64）、aarch64（arm64） |
| 权限 | root |
| 服务管理 | systemd |

脚本会自动装 `ca-certificates`、`libcap2-bin`、`curl`、`tar`。

> `ca-certificates` **不是可选的**：节点连面板走 HTTPS，系统没有信任锚时
> 连接器在构造期就失败，症状是「端口监听上了但立刻退出」，而错误消息看不出
> 缺的是 CA。

---

## 全部参数

| 参数 | 说明 |
|---|---|
| `--api-host URL` | 面板地址（必填，必须 https） |
| `--server-id N` | 节点 ID（必填） |
| `--secret-key KEY` | 面板通信密钥（必填） |
| `--secret-key-file PATH` | 从文件读密钥，**批量部署用这个** |
| `--port N` | 认领面板上哪条协议，缺省 `443` |
| `--bind IP` | 绑定网卡，缺省 `0.0.0.0`（只填 IP，端口由面板给） |
| `--tls-cert PATH` | TLS 模式的证书链 |
| `--tls-key PATH` | TLS 模式的私钥 |
| `--acme-email MAIL` | 没有证书时自动签发（HTTP-01，需要 80 端口空闲） |
| `--report-online` | 上报在线用户，面板据此数设备（缺省关） |
| `--enforce-device-limit` | 执行面板下发的设备数上限（缺省关） |
| `--version TAG` | 装指定版本，缺省最新 |
| `--tarball PATH` | 用本地包装，不下载 |
| `--download-base URL` | 自定义下载源 |
| `--skip-service` | 只装文件与配置，不碰 systemd |
| `--uninstall` | 卸载（等同 `uninstall.sh`） |

### 密钥不要放命令行

`--secret-key` 会进 shell 历史，也能被同机的其他用户用 `ps` 看到。
批量部署改用：

```bash
install -m 600 /dev/null /root/dbk.key
printf '%s' '<密钥>' > /root/dbk.key
bash install.sh --api-host https://panel.example.com --server-id 1 \
                --secret-key-file /root/dbk.key
```

密钥最终落在 `/etc/daybreak/node.env`（0600），**不会进 `node.toml`**
——配置文件常被纳入版本管理或配置分发系统。

---

## 关于证书

只有面板下发 **TLS 模式**时才需要证书。REALITY 模式自己合成证书，
本机配了反而会**报错**（不是忽略——「配了却不生效」比启动失败难查得多）。

脚本会向面板查一次画像来判断要不要准备证书：

- 已有 `/etc/letsencrypt/live/<SNI>/` 下的证书 → 直接沿用；
- 加 `--acme-email you@example.com` → 用 certbot 签发（需要该域名的 DNS
  已指向本机、80 端口空闲）；
- 都没有 → 明确报错并说明这两条出路，**不会装一个起不来的节点**。

证书续期后 `systemctl reload dbk-node` 即可，在途连接不断。挂进 certbot：

```bash
echo 'systemctl reload dbk-node' > /etc/letsencrypt/renewal-hooks/deploy/dbk-node.sh
chmod +x /etc/letsencrypt/renewal-hooks/deploy/dbk-node.sh
```

---

## 日常运维

```bash
systemctl status dbk-node      # 状态
systemctl reload dbk-node      # 热加载（改用户表用它，不断开在途连接）
systemctl restart dbk-node     # 重启
journalctl -u dbk-node -f      # 日志
```

**面板上改了画像（端口 / 安全层 / 载体 / 路径）节点会自己发现并重建监听**，
不需要人工介入。

### 在线数与设备限制

缺省**不上报**在线用户，所以面板 UI 的在线数会是空的、设备数限制也不生效。
要开启：

```bash
bash install.sh --report-online          # 重跑即可，配置会保留其余部分
```

开启意味着节点会把客户端 IP 发给面板——面板靠 IP 去重来数设备。
同一 NAT 后的多台设备会被算作一台。

---

## 排错

| 现象 | 多半是 |
|---|---|
| `systemctl start` 后立刻退出 | 看 `journalctl -u dbk-node -n 50`，配置错误会指名字段 |
| 日志报「拿不到画像」 | `--port` 与面板上的协议端口对不上 |
| 日志报「用户数=0」 | 面板上这台节点还没挂订阅，属正常 |
| 面板显示节点离线 | 节点到面板的网络不通，或密钥不对 |
| 监听不了 443 | `setcap` 没生效，装 `libcap2-bin` 后重跑脚本 |

干跑校验配置（不启动、不占端口）：

```bash
/usr/local/bin/dbk-node --check --config /etc/daybreak/node.toml
```

---

## 校验和

每个发布包旁边都有 `.sha256`，脚本会自动校验。手工核对：

```bash
sha256sum -c dbk-node-x86_64-unknown-linux-gnu.tar.gz.sha256
```

下载路径上任何一环出问题都会得到一个**能解压但跑不起来**的包，
而症状是 systemd 反复重启，与配置写错不可区分——所以校验不是可选步骤。
