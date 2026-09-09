#!/usr/bin/env bash
set -Eeuo pipefail

# Install and configure an authenticated SOCKS5 proxy using Dante.
# Supported targets: Debian/Ubuntu (apt) and RHEL/Fedora (dnf/yum).

PORT=""
USERNAME=""
PASSWORD=""
HOST=""
NO_FIREWALL=0
ALLOWED_CIDR="0.0.0.0/0"
SHOW=0
CREDENTIAL_FILE=/root/.config/socks5-node/credentials

proxy_uri() {
  local host="$1"
  [[ "$host" == *:* && "$host" != \[*\] ]] && host="[$host]"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$USERNAME" "$PASSWORD" "$host" "$PORT" <<'PY'
import sys, urllib.parse
u, p, h, port = sys.argv[1:]
print(f"socks5://{urllib.parse.quote(u, safe='')}:{urllib.parse.quote(p, safe='')}@{h}:{port}")
PY
  else
    printf 'socks5://%s:%s@%s:%s\n' "$USERNAME" "$PASSWORD" "$host" "$PORT"
  fi
}

usage() {
  cat <<'EOF'
用法: sudo bash setup-socks5-dante.sh [选项]

选项:
  --port PORT              监听端口（默认随机选择 20000-60000）
  --username NAME          代理用户名（默认随机生成）
  --password PASSWORD      代理密码（默认随机生成；避免出现在 shell 历史中）
  --host HOST              输出连接地址中的公网 IP 或域名
  --show                   显示已保存的现有代理信息（只读）
  --no-firewall            不尝试添加 ufw/firewalld 放行规则
  --allow CIDR             限制客户端来源网段（默认 0.0.0.0/0）
  -h, --help               显示帮助
EOF
}

die() { echo "错误: $*" >&2; exit 1; }
require_root() { [[ ${EUID} -eq 0 ]] || die "请使用 root 或 sudo 运行"; }
random_hex() { od -An -N "$1" -tx1 /dev/urandom | tr -d ' \n'; }
valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && (( 1 <= 10#$1 && 10#$1 <= 65535 )); }
valid_name() { [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]{0,31}$ ]]; }

while (($#)); do
  case "$1" in
    --port) [[ $# -ge 2 ]] || die "--port 需要参数"; PORT=$2; shift 2 ;;
    --username) [[ $# -ge 2 ]] || die "--username 需要参数"; USERNAME=$2; shift 2 ;;
    --password) [[ $# -ge 2 ]] || die "--password 需要参数"; PASSWORD=$2; shift 2 ;;
    --host) [[ $# -ge 2 ]] || die "--host 需要参数"; HOST=$2; shift 2 ;;
    --show) SHOW=1; shift ;;
    --no-firewall) NO_FIREWALL=1; shift ;;
    --allow) [[ $# -ge 2 ]] || die "--allow 需要参数"; ALLOWED_CIDR=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知选项: $1" ;;
  esac
done

require_root
if (( SHOW )); then
  [[ -r "$CREDENTIAL_FILE" ]] || die "未找到已保存的代理凭据。旧版本安装未保存密码，请重新运行安装。"
  . "$CREDENTIAL_FILE"
  echo "服务状态: $(systemctl is-active danted 2>/dev/null || true)"
  echo "SOCKS5 URI: $(proxy_uri "${PROXY_HOST:-服务器公网 IP}")"
  exit 0
fi
[[ -n "$PORT" ]] || PORT=$((20000 + $(od -An -N2 -tu2 /dev/urandom) % 40001))
[[ -n "$USERNAME" ]] || USERNAME="proxy$(random_hex 3)"
[[ -n "$PASSWORD" ]] || PASSWORD="$(random_hex 12)"
valid_port "$PORT" || die "端口必须是 1-65535 的整数"
valid_name "$USERNAME" || die "用户名格式无效（仅允许字母、数字、_、.、-，且以字母或 _ 开头）"
[[ "$PASSWORD" != *$'\n'* && -n "$PASSWORD" ]] || die "密码不能为空且不能包含换行"
[[ "$ALLOWED_CIDR" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]] || die "--allow 仅支持 IPv4 CIDR，例如 203.0.113.0/24"

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y dante-server
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y dante-server
elif command -v yum >/dev/null 2>&1; then
  yum install -y dante-server
else
  die "未找到 apt-get、dnf 或 yum；请先安装 dante-server"
fi

command -v ip >/dev/null 2>&1 || die "系统缺少 ip 命令"
EXTERNAL_IF=$(ip route show default | awk 'NR==1 {print $5}')
[[ -n "$EXTERNAL_IF" ]] || die "无法检测默认出口网卡，请检查服务器路由"

if id "$USERNAME" >/dev/null 2>&1; then
  usermod --shell /usr/sbin/nologin "$USERNAME" 2>/dev/null || true
else
  useradd --system --no-create-home --shell /usr/sbin/nologin "$USERNAME"
fi
printf '%s:%s\n' "$USERNAME" "$PASSWORD" | chpasswd

if [[ -r /etc/os-release ]] && . /etc/os-release && [[ "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" == *debian* ]]; then
  CONFIG=/etc/danted.conf
else
  CONFIG=/etc/sockd.conf
fi
# Reuse an existing privileged account only when the current Dante config
# explicitly declares one; merely having a system user named "proxy" is not
# sufficient. On a clean install Dante's portable default is root.
DANTE_PRIV_USER=root
if [[ -f "$CONFIG" ]]; then
  EXISTING_PRIV=$(awk -F: '/^[[:space:]]*user\.privileged[[:space:]]*:/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$CONFIG")
  if [[ -n "$EXISTING_PRIV" ]] && id "$EXISTING_PRIV" >/dev/null 2>&1; then
    DANTE_PRIV_USER="$EXISTING_PRIV"
  fi
fi
install -m 0600 /dev/null "$CONFIG"
cat >"$CONFIG" <<EOF
logoutput: syslog
internal: 0.0.0.0 port = $PORT
external: $EXTERNAL_IF
socksmethod: username
# Ubuntu packages create "proxy"; other distributions may use root here.
user.privileged: $DANTE_PRIV_USER
user.notprivileged: nobody
clientmethod: none

client pass {
  from: $ALLOWED_CIDR to: 0.0.0.0/0
}
socks pass {
  from: $ALLOWED_CIDR to: 0.0.0.0/0
  command: connect
  log: connect error
}
EOF

if command -v danted >/dev/null 2>&1; then
  # Dante 1.4.x uses -V for configuration verification (not -t).
  VERIFY_OUTPUT=$(mktemp)
  if ! danted -V -f "$CONFIG" >"$VERIFY_OUTPUT" 2>&1; then
    cat "$VERIFY_OUTPUT" >&2
    rm -f "$VERIFY_OUTPUT"
    die "Dante 配置校验失败，请查看上面的具体错误"
  fi
  rm -f "$VERIFY_OUTPUT"
fi

if (( ! NO_FIREWALL )); then
  if command -v ufw >/dev/null 2>&1; then ufw allow "$PORT/tcp" >/dev/null || true
  elif command -v firewall-cmd >/dev/null 2>&1; then firewall-cmd --permanent --add-port="$PORT/tcp" >/dev/null && firewall-cmd --reload >/dev/null || true
  fi
fi

SYSTEMD_UNIT=$(systemctl cat danted.service >/dev/null 2>&1 && echo danted.service || echo danted)
systemctl enable --now "$SYSTEMD_UNIT"
systemctl restart "$SYSTEMD_UNIT"
sleep 1
systemctl is-active --quiet "$SYSTEMD_UNIT" || { systemctl --no-pager --full status "$SYSTEMD_UNIT"; die "Dante 启动失败"; }

SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
[[ -n "$HOST" ]] || HOST="$SERVER_IP"
mkdir -p "${CREDENTIAL_FILE%/*}"
chmod 700 "${CREDENTIAL_FILE%/*}"
printf 'PORT=%q\nUSERNAME=%q\nPASSWORD=%q\nPROXY_HOST=%q\n' "$PORT" "$USERNAME" "$PASSWORD" "$HOST" > "$CREDENTIAL_FILE"
chmod 600 "$CREDENTIAL_FILE"
echo
echo "SOCKS5 已启动"
echo "地址: ${SERVER_IP:-服务器公网 IP}:$PORT"
echo "用户名: $USERNAME"
echo "密码: $PASSWORD"
echo "SOCKS5 URI: $(proxy_uri "${HOST:-服务器公网 IP}")"
echo "配置文件: $CONFIG"
echo "提示: 请同时在云厂商安全组放行 TCP/$PORT；完成后建议保存并清理终端历史中的密码参数。"
