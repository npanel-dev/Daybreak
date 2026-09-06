#!/usr/bin/env bash
#
# Daybreak SimnetV2 Node —— 卸载
#
#   wget -N https://raw.githubusercontent.com/npanel-dev/Daybreak/main/uninstall.sh \
#     && bash uninstall.sh
#
#   bash uninstall.sh --purge   # 连配置、密钥、流量账本、运行用户一起删
#
# 缺省**保留** /etc/daybreak 与 /var/lib/daybreak：
#
# - `/etc/daybreak` 含面板通信密钥，删了重装要重新配；
# - `/var/lib/daybreak` 含**尚未上报的流量账本**，删了就是丢掉一段计费数据。
#
# 想彻底清干净用 `--purge`，但请先确认这台节点不会再起来。
#
set -euo pipefail

readonly BIN_DIR="/usr/local/bin"
readonly CONFIG_DIR="/etc/daybreak"
readonly STATE_DIR="/var/lib/daybreak"
readonly SERVICE_FILE="/etc/systemd/system/dbk-node.service"
readonly RUN_USER="daybreak"

red=$'\e[31m'; green=$'\e[32m'; yellow=$'\e[33m'; cyan=$'\e[36m'; plain=$'\e[0m'
info() { printf '%s[INFO]%s  %s\n' "${green}"  "${plain}" "$*"; }
warn() { printf '%s[WARN]%s  %s\n' "${yellow}" "${plain}" "$*"; }
fail() { printf '%s[ERROR]%s %s\n' "${red}"    "${plain}" "$*" >&2; exit 1; }
step() { printf '\n%s══ %s ══%s\n'  "${cyan}"   "$*" "${plain}"; }

PURGE="false"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --purge)   PURGE="true"; shift ;;
        --help|-h) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) fail "未知参数：$1（--help 看用法）" ;;
    esac
done

[[ "${EUID}" -eq 0 ]] || fail "需要 root"

step "停止服务"
systemctl disable --now dbk-node 2>/dev/null || true
rm -f "${SERVICE_FILE}"
systemctl daemon-reload 2>/dev/null || true
info "服务已停止并移除"

step "移除文件"
rm -f "${BIN_DIR}/dbk-node"
info "已删除 ${BIN_DIR}/dbk-node"

# install.sh 下发的网络内核调优（BBR + fq + TCP 缓冲）：还原系统默认。
# 只删我们自己的片段，不动系统其它 sysctl 配置。
if [[ -f /etc/sysctl.d/99-daybreak-node.conf ]]; then
    rm -f /etc/sysctl.d/99-daybreak-node.conf /etc/modules-load.d/daybreak-bbr.conf
    sysctl --system >/dev/null 2>&1 || true
    info "已移除网络调优片段（BBR/fq/缓冲将在重载或重启后回落系统默认）"
fi

if [[ "${PURGE}" == "true" ]]; then
    step "清除配置与数据（--purge）"
    # 有未上报的流量就说一声再删——那是钱。
    if [[ -d "${STATE_DIR}/usage-spool" ]]; then
        pending="$(find "${STATE_DIR}/usage-spool" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
        [[ "${pending}" != "0" ]] && warn "丢弃 ${pending} 批尚未上报的流量记录"
    fi
    rm -rf "${CONFIG_DIR}" "${STATE_DIR}"
    userdel "${RUN_USER}" 2>/dev/null || true
    info "已删除 ${CONFIG_DIR}、${STATE_DIR} 与运行用户 ${RUN_USER}"
else
    cat <<EOF

${yellow}以下内容已保留：${plain}
  ${CONFIG_DIR}     配置与面板通信密钥
  ${STATE_DIR}   尚未上报的流量账本

重装时会直接沿用，不必重新配置。要彻底清除：bash uninstall.sh --purge
EOF
fi

step "完成"
