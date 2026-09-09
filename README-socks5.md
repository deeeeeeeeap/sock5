# SOCKS5 节点搭建脚本

脚本 [setup-socks5-dante.sh](./setup-socks5-dante.sh) 面向 Debian/Ubuntu（`apt-get`）以及 RHEL/Fedora（`dnf`/`yum`）服务器，使用 Dante 提供带用户名密码认证的 SOCKS5 服务。

```bash
chmod +x setup-socks5-dante.sh
sudo ./setup-socks5-dante.sh
```

不传参数时，脚本会随机生成 `20000-60000` 之间的监听端口、用户名和密码。也可以自定义：

```bash
sudo ./setup-socks5-dante.sh --port 31288 --username myproxy --password '请替换为强密码'
```

如果不希望脚本操作本机防火墙：

```bash
sudo ./setup-socks5-dante.sh --no-firewall
```

运行结束会打印连接地址和认证信息。还需要在云厂商安全组放行对应 TCP 端口，并限制来源 IP；不要把代理暴露给不受信任的公网用户。

卸载服务可执行（会移除 Dante 和配置，请先确认）：

```bash
sudo systemctl disable --now danted 2>/dev/null || sudo systemctl disable --now danted.service
sudo apt-get remove dante-server   # Debian/Ubuntu；RHEL/Fedora 请改用 dnf/yum
```
