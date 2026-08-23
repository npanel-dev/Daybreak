#!/usr/bin/env bash
#
# Daybreak SimnetV2 Node —— 一键安装
#
#   # 首次安装
#   wget -N https://raw.githubusercontent.com/npanel-dev/Daybreak/main/install.sh \
#     && bash install.sh --api-host https://panel.example.com \
#                        --server-id 1 --secret-key <密钥>
#
#   # 之后再跑一次就是升级：自动取 Releases 里的最新版并重启，配置原样保留
#   bash install.sh
#
# 面板下发模式：端口、安全层、REALITY 密钥、carrier、path **全部来自面板**，
# 本机只需要知道「面板在哪、我是几号、密钥是什么」。所以这三个参数就够了。
#
# 全部参数：
#   --api-host URL          面板地址（必填）
#   --server-id N           节点 ID（必填）
#   --secret-key KEY        面板通信密钥（必填；或用 --secret-key-file）
#   --secret-key-file PATH  从文件读密钥（避免密钥进 shell 历史与 ps）
#   --port N                认领面板上哪条协议（缺省 443）
#   --bind IP               绑定网卡（缺省 0.0.0.0；**只填 IP，端口由面板给**）
#   --tls-cert PATH         TLS 模式的证书链（面板下发 tls 时需要）
#   --tls-key PATH          TLS 模式的私钥
#   --acme-email MAIL       没有证书时用它自动签发（HTTP-01，需要 80 端口空闲）
#   --report-online         上报在线用户（面板据此数设备；缺省关）
#   --enforce-device-limit  执行面板下发的设备数上限（缺省关）
#   --tarball PATH          用本地包装，不下载
#   --version TAG           指定版本（缺省取最新 Release）
#   --download-base URL     自定义下载源（私有仓库或自建分发时用）
#   --skip-service          只装文件与配置，不碰 systemd
#   --uninstall             卸载（保留 /etc/daybreak 与流量账本）
#
# ── 三处与 OmnXT 的 install.sh 有意不同 ────────────────────────────────
#
# 1. **密钥绝不写进 node.toml。** 节点在配置层就拒绝明文 token（只认
#    token_env / token_file）。这里写进 0600 的 node.env，由 systemd 的
#    EnvironmentFile 注入。配置文件常被纳入版本管理或配置分发系统，
#    明文写进去等于把面板凭据散出去。
#
# 2. **不问安全层 / SNI / carrier。** 那些是面板的字段，本地再问一遍就会出现
#    「面板配了 tls、本机填了 reality」这种没有正确答案的组合。
#
# 3. **不装 xray。** REALITY 密钥由面板下发，本机不需要 keygen。
#
set -euo pipefail

readonly REPO="npanel-dev/Daybreak"
readonly BIN_DIR="/usr/local/bin"
readonly CONFIG_DIR="/etc/daybreak"
readonly CONFIG_FILE="${CONFIG_DIR}/node.toml"
readonly ENV_FILE="${CONFIG_DIR}/node.env"
readonly SERVICE_FILE="/etc/systemd/system/dbk-node.service"
readonly RUN_USER="daybreak"

red=$'\e[31m'; green=$'\e[32m'; yellow=$'\e[33m'; cyan=$'\e[36m'; plain=$'\e[0m'
info() { printf '%s[INFO]%s  %s\n'  "${green}"  "${plain}" "$*"; }
warn() { printf '%s[WARN]%s  %s\n'  "${yellow}" "${plain}" "$*"; }
fail() { printf '%s[ERROR]%s %s\n'  "${red}"    "${plain}" "$*" >&2; exit 1; }
step() { printf '\n%s══ %s ══%s\n'   "${cyan}"   "$*" "${plain}"; }

API_HOST=""; SERVER_ID=""; SECRET_KEY=""; SECRET_KEY_FILE=""
CLAIM_PORT="443"; BIND_IP="0.0.0.0"
TLS_CERT=""; TLS_KEY=""; ACME_EMAIL=""
REPORT_ONLINE="false"; ENFORCE_DEVICE_LIMIT="false"
TARBALL=""; VERSION=""; DOWNLOAD_BASE=""
SKIP_SERVICE="false"; DO_UNINSTALL="false"

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        # `--panel-url` 是旧名，保留：批量部署的脚本里可能已经写死了。
        --api-host|--panel-url)  API_HOST="${2:-}"; shift 2 ;;
        --server-id)             SERVER_ID="${2:-}"; shift 2 ;;
        --secret-key)            SECRET_KEY="${2:-}"; shift 2 ;;
        --secret-key-file)       SECRET_KEY_FILE="${2:-}"; shift 2 ;;
        --port)                  CLAIM_PORT="${2:-}"; shift 2 ;;
        --bind)                  BIND_IP="${2:-}"; shift 2 ;;
        --tls-cert)              TLS_CERT="${2:-}"; shift 2 ;;
        --tls-key)               TLS_KEY="${2:-}"; shift 2 ;;
        --acme-email)            ACME_EMAIL="${2:-}"; shift 2 ;;
        --report-online)         REPORT_ONLINE="true"; shift ;;
        --enforce-device-limit)  ENFORCE_DEVICE_LIMIT="true"; shift ;;
        --tarball)               TARBALL="${2:-}"; shift 2 ;;
        --version)               VERSION="${2:-}"; shift 2 ;;
        --download-base)         DOWNLOAD_BASE="${2:-}"; shift 2 ;;
        --skip-service)          SKIP_SERVICE="true"; shift ;;
        --uninstall)             DO_UNINSTALL="true"; shift ;;
        --help|-h)               usage ;;
        *) fail "未知参数：$1（--help 看用法）" ;;
    esac
done

[[ "${EUID}" -eq 0 ]] || fail "需要 root（安装到 ${BIN_DIR} 与 ${CONFIG_DIR}）"

# ── 卸载 ───────────────────────────────────────────────────────────────
#
# **保留 /etc/daybreak 与 /var/lib/daybreak**：前者含面板密钥，后者含尚未
# 上报的流量账本。卸载顺手删掉它们意味着重装要重新配、且丢掉一段计费数据。
if [[ "${DO_UNINSTALL}" == "true" ]]; then
    step "卸载"
    systemctl disable --now dbk-node 2>/dev/null || true
    rm -f "${SERVICE_FILE}"
    systemctl daemon-reload 2>/dev/null || true
    rm -f "${BIN_DIR}/dbk-node"
    info "已移除二进制与 systemd 单元"
    info "保留：${CONFIG_DIR}（含面板密钥）、/var/lib/daybreak（含未上报的流量账本）"
    info "确认不再需要后手动删除即可"
    exit 0
fi

# ── 参数校验 ───────────────────────────────────────────────────────────
if [[ -n "${SECRET_KEY_FILE}" ]]; then
    [[ -f "${SECRET_KEY_FILE}" ]] || fail "找不到密钥文件：${SECRET_KEY_FILE}"
    SECRET_KEY="$(tr -d '\r\n' < "${SECRET_KEY_FILE}")"
fi

# 缺参数就报缺哪个，不进入交互——一键安装的前提是无人值守。
missing=()
[[ -n "${API_HOST}"   ]] || missing+=("--api-host")
[[ -n "${SERVER_ID}"  ]] || missing+=("--server-id")
[[ -n "${SECRET_KEY}" ]] || missing+=("--secret-key（或 --secret-key-file）")
if [[ ${#missing[@]} -gt 0 && ! -f "${CONFIG_FILE}" ]]; then
    fail "缺少必填参数：${missing[*]}
用法：bash install.sh --api-host https://panel.example.com --server-id 1 --secret-key <密钥>"
fi

# **地址必须是 https 或回环 http。** 明文 http 到公网面板意味着密钥在链路上
# 可见，而节点自己也会拒绝这种 base_url——在这里先说清楚，比让它启动失败强。
if [[ -n "${API_HOST}" ]]; then
    case "${API_HOST}" in
        https://*) ;;
        http://127.0.0.1*|http://localhost*) warn "面板地址是明文 http 回环，仅用于本机调试" ;;
        *) fail "面板地址必须是 https://（回环调试可用 http://127.0.0.1）：${API_HOST}" ;;
    esac
    API_HOST="${API_HOST%/}"
fi
[[ "${SERVER_ID}" =~ ^[0-9]+$ ]] || [[ -z "${SERVER_ID}" ]] \
    || fail "--server-id 必须是数字：${SERVER_ID}"

if [[ -n "${SECRET_KEY}" && -z "${SECRET_KEY_FILE}" ]]; then
    warn "密钥出现在命令行上：它会进 shell 历史，也能被同机的 ps 看到。"
    warn "批量部署建议改用 --secret-key-file。"
fi

# ── 依赖 ───────────────────────────────────────────────────────────────
#
# `ca-certificates` **是必需的，不是可选的**：节点连面板走 HTTPS，系统没有
# 信任锚时连接器在**构造期**就失败。实测（debian:12 最小镜像）的症状是
# `--check` 通过、端口也监听上了，随后一行「面板连接器构造失败」退出
# ——那条消息刻意低基数，看不出缺的是 CA。
install_dependencies() {
    local missing=()
    compgen -G "/etc/ssl/certs/*.pem" >/dev/null 2>&1 || missing+=("ca-certificates")
    command -v setcap >/dev/null 2>&1 || missing+=("libcap2-bin")
    command -v curl   >/dev/null 2>&1 || missing+=("curl")
    command -v tar    >/dev/null 2>&1 || missing+=("tar")
    [[ ${#missing[@]} -eq 0 ]] && return 0
    info "安装依赖：${missing[*]}"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq >/dev/null 2>&1 || true
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" >/dev/null 2>&1 \
            || warn "依赖安装失败，请手动安装：${missing[*]}"
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y -q "${missing[@]/libcap2-bin/libcap}" >/dev/null 2>&1 \
            || warn "依赖安装失败，请手动安装：${missing[*]}"
    elif command -v yum >/dev/null 2>&1; then
        yum install -y -q "${missing[@]/libcap2-bin/libcap}" >/dev/null 2>&1 \
            || warn "依赖安装失败，请手动安装：${missing[*]}"
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache ca-certificates libcap curl tar >/dev/null 2>&1 \
            || warn "依赖安装失败，请手动安装：${missing[*]}"
    else
        warn "未识别的包管理器；请手动安装：${missing[*]}"
    fi
}

step "环境检查"
if [[ "${SKIP_SERVICE}" != "true" ]] && ! command -v systemctl >/dev/null 2>&1; then
    fail "未找到 systemctl；本脚本只支持 systemd（只装文件用 --skip-service）"
fi
install_dependencies

case "$(uname -m)" in
    x86_64|amd64)  ARCH_TRIPLE="x86_64-unknown-linux-gnu" ;;
    aarch64|arm64) ARCH_TRIPLE="aarch64-unknown-linux-gnu" ;;
    *) fail "不支持的架构：$(uname -m)（支持 x86_64 / aarch64）" ;;
esac
info "架构：$(uname -m) → ${ARCH_TRIPLE}"

# ── 取包 ───────────────────────────────────────────────────────────────
step "获取安装包"
WORK_DIR="$(mktemp -d)"
CONFIG_TMP=""
# 无论成败都清理：失败时留一地临时文件，下次运行会撞上旧内容。
trap 'rm -rf "${WORK_DIR}"; [[ -n "${CONFIG_TMP}" ]] && rm -f "${CONFIG_TMP}"' EXIT

PKG_NAME="dbk-node-${ARCH_TRIPLE}.tar.gz"
# 装之前记下现有版本：升级时要能一眼看出「从哪个换到哪个」。
# 只报「已启动」而不报版本的话，「脚本跑了但其实没换成新的」看不出来。
INSTALLED_VERSION="$(sed -n 's/^commit=//p' "${CONFIG_DIR}/VERSION" 2>/dev/null | cut -c1-7)"
if [[ -n "${TARBALL}" ]]; then
    [[ -f "${TARBALL}" ]] || fail "找不到本地包：${TARBALL}"
    info "使用本地包：${TARBALL}"
    cp "${TARBALL}" "${WORK_DIR}/node.tar.gz"
    if [[ -f "${TARBALL}.sha256" ]]; then
        ( cd "$(dirname "${TARBALL}")" && sha256sum -c "$(basename "${TARBALL}").sha256" >/dev/null ) \
            || fail "本地包校验失败"
        info "校验和通过"
    fi
else
    if [[ -z "${DOWNLOAD_BASE}" ]]; then
        if [[ -z "${VERSION}" ]]; then
            info "查询最新版本…"
            VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
                       | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"//;s/".*//')" || true
            [[ -n "${VERSION}" ]] || fail "取不到最新版本号。
仓库可能是私有的、或还没有 Release。两条出路：
  1. 自建分发：bash install.sh --download-base https://你的域名/dbk ...
  2. 本地包：  bash install.sh --tarball ./${PKG_NAME} ..."
        fi
        DOWNLOAD_BASE="https://github.com/${REPO}/releases/download/${VERSION}"
    fi
    info "下载 ${DOWNLOAD_BASE}/${PKG_NAME}"
    curl -fsSL "${DOWNLOAD_BASE}/${PKG_NAME}" -o "${WORK_DIR}/node.tar.gz" \
        || fail "下载失败：${DOWNLOAD_BASE}/${PKG_NAME}"
    # **校验必须做**：下载路径上任何一环出问题都会得到一个能解压但跑不起来的
    # 包，而症状是 systemd 反复重启，与配置写错不可区分。
    if curl -fsSL "${DOWNLOAD_BASE}/${PKG_NAME}.sha256" -o "${WORK_DIR}/node.sha256" 2>/dev/null; then
        ( cd "${WORK_DIR}" && sed "s#${PKG_NAME}#node.tar.gz#" node.sha256 | sha256sum -c - >/dev/null ) \
            || fail "校验和不匹配——下载可能被篡改或中断"
        info "校验和通过"
    else
        warn "下载源没有 .sha256，跳过校验"
    fi
fi

tar -xzf "${WORK_DIR}/node.tar.gz" -C "${WORK_DIR}"
PKG_DIR="${WORK_DIR}/dbk-node-${ARCH_TRIPLE}"
[[ -x "${PKG_DIR}/dbk-node" ]] || fail "包内容异常：缺少可执行文件 ${PKG_DIR}/dbk-node"

# ── 装文件 ─────────────────────────────────────────────────────────────
step "安装文件"
if [[ "${SKIP_SERVICE}" != "true" ]] && systemctl is-active --quiet dbk-node 2>/dev/null; then
    info "停止运行中的 dbk-node"
    systemctl stop dbk-node
fi
install -m 0755 "${PKG_DIR}/dbk-node" "${BIN_DIR}/dbk-node"

# **先建用户再建目录**：目录要属组给运行用户，而 useradd 必须先跑。顺序反了
# 的话目录是 root:root 0750，服务以 User=daybreak 启动时**连目录都进不去**
# ——实测报的是「读不到配置文件」，而 root 手动 --check 完全正常。
if ! id -u "${RUN_USER}" >/dev/null 2>&1; then
    useradd -r -s /usr/sbin/nologin "${RUN_USER}" 2>/dev/null \
        || useradd -r -s /sbin/nologin "${RUN_USER}"
    info "已创建运行用户 ${RUN_USER}"
fi
install -d -m 0750 -o root -g "${RUN_USER}" "${CONFIG_DIR}"
[[ -f "${PKG_DIR}/VERSION" ]] && install -m 0644 "${PKG_DIR}/VERSION" "${CONFIG_DIR}/VERSION"
NEW_VERSION="$(sed -n 's/^commit=//p' "${PKG_DIR}/VERSION" 2>/dev/null | cut -c1-7)"
if [[ -n "${INSTALLED_VERSION}" && "${INSTALLED_VERSION}" != "${NEW_VERSION}" ]]; then
    info "已安装 ${BIN_DIR}/dbk-node（${INSTALLED_VERSION} → ${NEW_VERSION}）"
elif [[ -n "${INSTALLED_VERSION}" ]]; then
    info "已安装 ${BIN_DIR}/dbk-node（版本未变：${NEW_VERSION}）"
else
    info "已安装 ${BIN_DIR}/dbk-node（${NEW_VERSION:-未知版本}）"
fi

# ── 问面板要画像 ───────────────────────────────────────────────────────
#
# **这一步是建议性的，不是权威。** 节点自己会拉一份画像，那份才作数。
# 这里只用它回答一个本地问题：**要不要准备证书**。
#
# TLS 模式下节点要求本地有证书（面板只下发 `cert_mode` 这类"怎么取证书"的
# 指令，不下发证书内容）；REALITY 模式下本地**不得**有证书。猜错任一边都是
# 启动失败，所以宁可先问一次。查不到就跳过，由节点启动时给出指名字段的错误。
PROFILE_SECURITY=""; PROFILE_SNI=""; PROFILE_PORT=""
probe_profile() {
    local body
    body="$(curl -fsSL --max-time 15 \
        "${API_HOST}/v2/server/${SERVER_ID}?protocols=simnetv2&secret_key=${SECRET_KEY}" \
        2>/dev/null)" || return 1
    command -v python3 >/dev/null 2>&1 || return 1
    local parsed
    parsed="$(printf '%s' "${body}" | python3 -c '
import json, sys
try:
    doc = json.load(sys.stdin)
except Exception:
    sys.exit(1)
node = doc.get("data", doc)
want = str('"${CLAIM_PORT}"')
for proto in node.get("protocols") or []:
    if proto.get("type") != "simnetv2":
        continue
    if str(proto.get("port")) != want:
        continue
    print(proto.get("security") or "", proto.get("sni") or "", proto.get("port") or "")
    break
' 2>/dev/null)" || return 1
    [[ -n "${parsed}" ]] || return 1
    read -r PROFILE_SECURITY PROFILE_SNI PROFILE_PORT <<<"${parsed}"
    return 0
}

if [[ -n "${API_HOST}" ]] && probe_profile; then
    info "面板画像：安全层=${PROFILE_SECURITY} SNI=${PROFILE_SNI} 端口=${PROFILE_PORT}"
else
    warn "取不到面板画像（不影响安装，节点启动时会自己拉）"
fi

# ── 证书 ───────────────────────────────────────────────────────────────
#
# 只有 TLS 模式需要。REALITY 自己合成证书，配了本地证书节点会**直接报错**
# ——不是忽略：「配了却不生效」比启动失败难查得多。
if [[ "${PROFILE_SECURITY}" == "tls" && -z "${TLS_CERT}" ]]; then
    step "准备证书"
    domain="${PROFILE_SNI}"
    guess_cert="/etc/letsencrypt/live/${domain}/fullchain.pem"
    guess_key="/etc/letsencrypt/live/${domain}/privkey.pem"
    if [[ -n "${domain}" && -f "${guess_cert}" && -f "${guess_key}" ]]; then
        TLS_CERT="${guess_cert}"; TLS_KEY="${guess_key}"
        info "沿用已有证书：${TLS_CERT}"
    elif [[ -n "${ACME_EMAIL}" && -n "${domain}" ]]; then
        command -v certbot >/dev/null 2>&1 || {
            info "安装 certbot"
            if command -v apt-get >/dev/null 2>&1; then
                DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot >/dev/null 2>&1 || true
            elif command -v dnf >/dev/null 2>&1; then
                dnf install -y -q certbot >/dev/null 2>&1 || true
            fi
        }
        command -v certbot >/dev/null 2>&1 || fail "certbot 装不上，请手动签发后用 --tls-cert/--tls-key 重跑"
        # HTTP-01 需要 80 端口空闲，且 ${domain} 的 A 记录要指到本机。
        info "为 ${domain} 签发证书（HTTP-01，需要 80 端口空闲）"
        certbot certonly --standalone --non-interactive --agree-tos \
            -m "${ACME_EMAIL}" -d "${domain}" \
            || fail "签发失败：确认 ${domain} 的 DNS 指向本机、且 80 端口没被占用"
        TLS_CERT="${guess_cert}"; TLS_KEY="${guess_key}"
    else
        fail "面板给的是 TLS 模式，但本机没有 ${domain} 的证书。
两条出路：
  1. 已有证书：--tls-cert /path/fullchain.pem --tls-key /path/privkey.pem
  2. 自动签发：--acme-email you@example.com（需要 ${domain} 的 DNS 已指向本机、80 端口空闲）"
    fi
fi
if [[ -n "${TLS_CERT}" ]]; then
    [[ -f "${TLS_CERT}" ]] || fail "证书不存在：${TLS_CERT}"
    [[ -n "${TLS_KEY}" && -f "${TLS_KEY}" ]] || fail "私钥不存在：${TLS_KEY}"
    # 节点以 daybreak 用户运行，要读得到 letsencrypt 目录。
    if [[ "${TLS_CERT}" == /etc/letsencrypt/* ]]; then
        chmod 0755 /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null || true
        setfacl -m "u:${RUN_USER}:rx" /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null || true
    fi
fi

# ── 配置 ───────────────────────────────────────────────────────────────
step "生成配置"
if [[ -f "${CONFIG_FILE}" ]]; then
    info "配置已存在，保留不动：${CONFIG_FILE}"
    info "（这是升级路径：只换二进制。要重新配置请先备份并删除它）"
else
    # **先写临时文件，成功了才落位。** 直接写目标文件的话，中途失败会留下
    # 半份配置——而下次重跑看到「配置已存在」直接跳过生成，节点从此起不来
    # 且没人知道为什么。
    CONFIG_TMP="$(mktemp "${CONFIG_DIR}/.node.toml.XXXXXX")"
    {
        echo "# Daybreak SimnetV2 Node —— 由 install.sh 生成于 $(date -u +%FT%TZ)"
        echo "#"
        echo "# 面板下发模式：端口、安全层、REALITY 密钥、carrier、path 都来自面板。"
        echo "# 本地配 listen 或 [reality] 会被**直接拒绝**——两边都配就没有正确答案。"
        echo
        echo "# 绑哪张网卡是本机的事（面板只给端口）。只接受 IP，不接受带端口的地址。"
        echo "bind = \"${BIND_IP}\""
        echo
        if [[ -n "${TLS_CERT}" ]]; then
            echo "# 面板下发 tls 时本机必须有证书（面板只给\"怎么取证书\"的指令）。"
            echo "# 面板下发 reality 时这一段必须**不存在**。"
            echo "[tls]"
            echo "cert = \"${TLS_CERT}\""
            echo "key  = \"${TLS_KEY}\""
            echo
        fi
        echo "[inbound]"
        echo "kind = \"simnetv2\""
        echo "# carrier 由面板下发；这里是解析期的占位值，运行时以面板为准。"
        echo "carrier = \"h2\""
        echo
        echo "[control]"
        echo "kind      = \"npanel\""
        echo "base_url  = \"${API_HOST}\""
        echo "server_id = ${SERVER_ID}"
        echo "# port 决定认领面板上哪一条协议。**不填就不知道该听哪个端口**，"
        echo "# 填错则拉到别人的用户表——两侧都不报错。"
        echo "port      = ${CLAIM_PORT}"
        echo "# 只写来源不写值：节点在配置层拒绝明文 token。"
        echo "token_env = \"DBK_PANEL_TOKEN\""
        echo "usage_spool_dir   = \"/var/lib/daybreak/usage-spool\""
        echo "profile_cache_dir = \"/var/lib/daybreak\""
        echo "report_online        = ${REPORT_ONLINE}"
        echo "enforce_device_limit = ${ENFORCE_DEVICE_LIMIT}"
    } > "${CONFIG_TMP}"
    chmod 0640 "${CONFIG_TMP}"
    chown root:"${RUN_USER}" "${CONFIG_TMP}" 2>/dev/null || true
    mv -f "${CONFIG_TMP}" "${CONFIG_FILE}"
    CONFIG_TMP=""
    info "已写入 ${CONFIG_FILE}"
fi

# 密钥单独落 0600 文件：它是唯一不能进配置的东西。
# 升级重跑时也刷新——密钥可能在面板上轮换过。
if [[ -n "${SECRET_KEY}" ]]; then
    ( umask 077; printf 'DBK_PANEL_TOKEN=%s\n' "${SECRET_KEY}" > "${ENV_FILE}" )
    chmod 0600 "${ENV_FILE}"
    chown root:"${RUN_USER}" "${ENV_FILE}" 2>/dev/null || true
    info "面板密钥已写入 ${ENV_FILE}（0600，不在 node.toml 里）"
fi

# 校验放在装服务**之前**：配置写错时立刻给出指名字段的错误，
# 而不是让 systemd 反复重启、运维去 journal 里猜。
step "校验配置"
"${BIN_DIR}/dbk-node" --check --config "${CONFIG_FILE}" \
    || fail "配置校验未通过（服务未启动）。修好 ${CONFIG_FILE} 后 systemctl start dbk-node"

# setcap 放在**校验之后**：加上文件 capability 后，在受限环境（容器、挂了
# nosuid 的分区）里 execve 会直接 Operation not permitted。
# 443 是特权端口；不 setcap 就只能以 root 跑，而单元文件里写的是 User=daybreak。
setcap 'cap_net_admin+ep cap_net_bind_service+ep' "${BIN_DIR}/dbk-node" 2>/dev/null \
    || warn "setcap 失败：监听 <1024 端口会启动不了（装 libcap2-bin 后重试）"

# ── 服务 ───────────────────────────────────────────────────────────────
if [[ "${SKIP_SERVICE}" == "true" ]]; then
    warn "--skip-service：未安装也未启动 systemd 服务"
else
    step "安装 systemd 服务"
    install -m 0644 "${PKG_DIR}/dbk-node.service" "${SERVICE_FILE}"
    systemctl daemon-reload
    systemctl enable --now dbk-node
    sleep 3
    if systemctl is-active --quiet dbk-node; then
        info "dbk-node 已启动"
    else
        warn "服务未处于 active，最近日志："
        journalctl -u dbk-node -n 20 --no-pager || true
        exit 1
    fi
fi

# ── 收尾 ───────────────────────────────────────────────────────────────
step "完成"
cat <<EOF
配置：      ${CONFIG_FILE}
面板密钥：  ${ENV_FILE}（0600）
服务：      systemctl {status|restart|reload} dbk-node
日志：      journalctl -u dbk-node -f
卸载：      bash install.sh --uninstall

改用户表用 reload 而不是 restart —— 它热加载且不断开在途连接。
面板上改了画像（端口/安全层/carrier）节点会自己发现并重建监听，不用人工介入。
EOF

if [[ "${REPORT_ONLINE}" != "true" ]]; then
    cat <<EOF

${yellow}在线上报未开启（缺省关）。${plain}
面板 UI 的在线数会是空的，设备数限制也不会生效。
要开启：重跑本脚本加 --report-online，或在 ${CONFIG_FILE} 的 [control] 段
设 report_online = true 后 systemctl reload dbk-node。
开启意味着节点会把客户端 IP 发给面板——面板靠 IP 去重来数设备。
EOF
fi

if [[ -n "${TLS_CERT}" && "${TLS_CERT}" == /etc/letsencrypt/* ]]; then
    cat <<EOF

${cyan}证书续期后执行 systemctl reload dbk-node 即可${plain}——它会重读证书文件，
在途连接不断。可以挂进 certbot 的 deploy-hook：
  echo 'systemctl reload dbk-node' > /etc/letsencrypt/renewal-hooks/deploy/dbk-node.sh
  chmod +x /etc/letsencrypt/renewal-hooks/deploy/dbk-node.sh
EOF
fi
