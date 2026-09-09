# SOCKS5 节点搭建脚本

使用 Dante 在 Linux 服务器上搭建带用户名和密码认证的 SOCKS5 代理。默认随机生成端口、用户名和密码，也支持通过参数自定义。

脚本通过 `apt-get`、`dnf` 或 `yum` 安装 `dante-server`，要求系统使用 systemd，且软件源提供该软件包。尚未在真实 Linux 服务器上完成安装验证。

## 一键安装

在服务器上执行以下命令，从 GitHub 下载脚本并以 root 权限运行：

```bash
curl -fsSL https://raw.githubusercontent.com/deeeeeeeeap/sock5/main/setup-socks5-dante.sh | sudo bash
```

默认监听端口随机取自 `20000-60000`，用户名和密码分别随机生成。安装成功后，终端会显示连接地址、端口和认证信息。

如果已下载 [setup-socks5-dante.sh](./setup-socks5-dante.sh)，在文件所在目录运行：

```bash
sudo bash setup-socks5-dante.sh
```

## 自定义选项

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `--port PORT` | 指定监听端口 | 随机生成 |
| `--username NAME` | 指定代理用户名 | 随机生成 |
| `--password PASSWORD` | 指定代理密码 | 随机生成 |
| `--allow CIDR` | 限制客户端来源 IPv4 网段 | `0.0.0.0/0` |
| `--no-firewall` | 跳过本机防火墙配置 | 尝试添加放行规则 |
| `--help` | 显示帮助 | — |

指定端口和用户名，密码仍随机生成：

```bash
curl -fsSL https://raw.githubusercontent.com/deeeeeeeeap/sock5/main/setup-socks5-dante.sh | sudo bash -s -- --port 31288 --username myproxy
```

使用本地脚本指定密码：

```bash
sudo bash setup-socks5-dante.sh --port 31288 --username myproxy --password '请替换为强密码'
```

通过 `--password` 传入的密码可能保留在 shell 历史中。

限制客户端来源地址（将示例地址替换为客户端实际公网 IP；单个 IPv4 地址使用 `/32`）：

```bash
sudo bash setup-socks5-dante.sh --allow 203.0.113.10/32
```

跳过本机防火墙配置：

```bash
sudo bash setup-socks5-dante.sh --no-firewall
```

## 连接说明

在客户端选择 SOCKS5，填写服务器公网 IP、脚本输出的端口、用户名和密码。脚本显示的地址可能是服务器内网 IP，请以实际可访问的公网地址为准。

在云厂商安全组中放行对应 TCP 端口；本机防火墙也需要允许该端口。`--allow` 控制 Dante 的客户端访问范围，不会修改云厂商安全组。

当前配置仅允许 TCP CONNECT。SOCKS5 用户名和密码认证本身不提供传输加密。

## 停止和卸载

停止服务并取消开机启动：

```bash
sudo systemctl disable --now danted
```

卸载 Dante 软件包（Debian/Ubuntu）：

```bash
sudo apt-get remove dante-server
```

使用 `dnf` 或 `yum` 的系统，请通过对应包管理器卸载 `dante-server`。卸载软件包后，脚本创建的用户、防火墙规则和配置文件可能仍然保留，需要根据实际安装情况单独处理。
