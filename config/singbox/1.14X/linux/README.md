# Linux 单核心运行方案

目标是在 headless Linux 上只运行一个 sing-box 核心，由 systemd 管理 TUN，
并让 macOS 通过 Tailscale 访问本地 WebUI。不要同时让 Linux GUI 和 systemd
实例管理 TUN。

```text
Sub-Store (macOS 或 NAS)
        |
        | HTTPS / Tailscale
        v
systemd timer -> /var/lib/sing-box/config.json
        |
        v
systemd sing-box.service -> TUN + DNS + API
        |
        | 127.0.0.1:9090 / 127.0.0.1:9095
        v
tailscale serve -> macOS 浏览器
```

## 为什么使用这个方案

- `/etc/sing-box` 只放 root 只读的 unit 和环境变量；sing-box 的配置、UI、
  cache 全部放在运行用户可写的 `/var/lib/sing-box`。
- `services.api` 和 Clash API 只监听回环地址。Tailscale Serve 负责 TLS 和
  tailnet 访问控制，不需要在公网防火墙开放 9090/9095。
- Sub-Store 更新由 systemd timer 下载、`sing-box check`、原子替换并重启，
  不依赖 Linux GUI 的 profile/cache 权限。
- Linux TUN 使用 `gvisor`、排除 `tailscale0` 和 Tailscale 地址，并在
  `auto_redirect` 的 pre-match 中 bypass Tailscale 流量。

## 文件

- `sing-box.service`: 唯一的 sing-box 系统服务。
- `sing-box-update.service` / `sing-box-update.timer`: 定时拉取 Sub-Store。
- `update-config.sh`: 下载、校验、原子替换并在启动失败时回滚。

## 安装

以下命令假设 Arch Linux 的 sing-box 已安装到 `/usr/bin/sing-box`，并且仓库
已检出到当前目录。

```bash
sudo useradd --system --home-dir /var/lib/sing-box \
  --shell /usr/sbin/nologin sing-box 2>/dev/null || true

sudo install -d -o sing-box -g sing-box -m 0700 \
  /var/lib/sing-box \
  /var/lib/sing-box/dashboard \
  /var/lib/sing-box/ui
sudo install -d -m 0755 /etc/sing-box
sudo install -d -m 0755 /usr/local/libexec

sudo install -m 0755 update-config.sh \
  /usr/local/libexec/sing-box-update-config
sudo install -m 0644 sing-box.service \
  sing-box-update.service \
  sing-box-update.timer \
  /etc/systemd/system/
```

创建 `/etc/sing-box/substore.env`，URL 必须使用 Sub-Store 输出的 sing-box
订阅地址：

```bash
SUB_STORE_URL='https://你的-sub-store-地址/你的订阅'
SING_BOX_CONFIG=/var/lib/sing-box/config.json
```

设置权限并执行首次更新：

```bash
sudo chmod 0600 /etc/sing-box/substore.env
sudo systemctl daemon-reload
sudo systemctl start sing-box-update.service
sudo systemctl enable --now sing-box.service sing-box-update.timer
```

首次拉取失败时不要启用服务，先检查：

```bash
sudo journalctl -u sing-box-update.service -b --no-pager
sudo /usr/bin/sing-box check -c /var/lib/sing-box/config.json
```

## macOS 远程 WebUI

先确认 Linux 主机已加入 tailnet，然后只发布回环端口：

```bash
sudo tailscale serve --bg --https=9095 http://127.0.0.1:9095
sudo tailscale serve --bg --https=9090 http://127.0.0.1:9090
sudo tailscale serve status
```

在 macOS 打开：

```text
Clash API / Zashboard:
https://<linux-host>.<tailnet>.ts.net:9095/ui/

sing-box dashboard:
https://<linux-host>.<tailnet>.ts.net:9090/dashboard/
```

当前模板中的管理 secret 是 `passwd`，两个 API 保持一致。部署前应同时修改
`linux.json` 或 `linux_mini.json` 里的两处 `secret`，重新由 Sub-Store 渲染，
再在 Zashboard 中填写同一个 Bearer secret。

日常操作可以全部在 Zashboard 中完成：

- `Proxies`：切换默认代理、地区手动组和地区自动组。
- `Connections`：查看连接命中的规则和 outbound。
- `Logs`：查看运行日志；需要定位规则时临时把模板的 `log.level` 改为 `debug`。
- `Config`：确认当前配置；实际配置仍以 Sub-Store 定时更新结果为准。

## Tailscale 与 SSH 行为

1.14X Linux 模板包含三层 Tailscale 保护：

```text
DNS: .ts.net -> local（避免 MagicDNS 被 FakeIP 接管）
TUN: route_exclude_address + exclude_interface tailscale0
Route: 100.64.0.0/10 和 fd7a:115c:a1e0::/48 在 pre-match bypass
```

如果 Tailscale 接口不是 `tailscale0`，修改模板中的 `exclude_interface`。
如果使用了自定义 MagicDNS 后缀，把该后缀加入 DNS 规则的 `domain_suffix`。

Linux 模板还会对 TCP 22 在 `auto_redirect` 的 pre-match 阶段直接 bypass。
这样 SSH 不经过 sing-box 的 TUN/direct 用户态路径，避免 banner 交换阶段被
重置；通过 mixed inbound 主动使用代理的 SSH 不会被这条 bypass 规则截获。

如果某些 SSH 必须经过代理，删除下面这条宽规则，并改用明确的 `ip_cidr`
管理网段：

```json
{"network": "tcp", "port": 22, "action": "bypass"}
```

`stack: gvisor` 是 sing-box 1.14 的 SSH 兼容性保险。sing-box 1.15 起
`stack` 已弃用，升级到 1.15 后应删除该字段并使用内核内置 stack。

## 更新与排障

手动触发一次更新：

```bash
sudo systemctl start sing-box-update.service
sudo journalctl -u sing-box-update.service -n 100 --no-pager
```

查看 sing-box 状态和日志：

```bash
systemctl status sing-box.service
sudo journalctl -u sing-box.service -f
ss -lntp | grep -E '9090|9095'
```

确认 Tailscale Serve 没有把端口暴露到公网：

```bash
tailscale serve status
```

如果 WebUI 能打开但无法读取数据，先检查浏览器里填写的 controller 地址和
secret，不要先用 `0.0.0.0` 绑定 API。Tailscale Serve 已经能提供远程访问，
公开监听只会扩大攻击面。

NixOS 可以用 `systemd.services.sing-box`、`systemd.timers.sing-box-update`
和 `systemd.tmpfiles.rules` 表达同一结构；关键约束仍是单核心、
`/var/lib/sing-box` 可写、API 只监听回环地址。
