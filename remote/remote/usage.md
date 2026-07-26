# 访问端使用指�?
访问端是你用来连接内�?SSH 的设备，比如笔记本、台式机或手机（推荐电脑）�?
本方案提供两种连接方式：

| 方式 | 特点 | 访问端操�?|
|------|------|------------|
| **P2P 模式（推荐）** | SSH 数据不经过公网服务器，更安全 | 在访问端运行 `frpc-visitor.toml`，然�?`ssh -p 2222 用户@127.0.0.1` |
| **TCP 模式（备用）** | 数据经过公网服务�?6000 端口转发 | 直接 `ssh -p 6000 用户@<FRP_SERVER_ADDR>` |

> **建议**：优先使�?P2P 模式，TCP 模式仅在 P2P 打洞失败或临时需要时使用�?
---

## 1. 下载 frpc

访问端只需�?`frpc` 客户端程序（不需�?`frps`）�?
### 根据你的系统选择版本

| 系统 | 架构 | 下载链接 |
|------|------|----------|
| Linux | x86_64 | `frp_0.70.0_linux_amd64.tar.gz` |
| Linux | ARM64 | `frp_0.70.0_linux_arm64.tar.gz` |
| macOS | Intel | `frp_0.70.0_darwin_amd64.tar.gz` |
| macOS | Apple Silicon | `frp_0.70.0_darwin_arm64.tar.gz` |
| Windows | x86_64 | `frp_0.70.0_windows_amd64.zip` |
| Windows | ARM64 | `frp_0.70.0_windows_arm64.zip` |

下载地址模板�?
```text
https://github.com/fatedier/frp/releases/download/v0.70.0/<文件�?
```

### Linux / macOS 下载示例

```bash
# 创建目录
mkdir -p ~/frp-visitor
cd ~/frp-visitor

# 根据你的系统选择下面其中一条命�?
# macOS Apple Silicon
wget https://github.com/fatedier/frp/releases/download/v0.70.0/frp_0.70.0_darwin_arm64.tar.gz

# macOS Intel
# wget https://github.com/fatedier/frp/releases/download/v0.70.0/frp_0.70.0_darwin_amd64.tar.gz

# Linux x86_64
# wget https://github.com/fatedier/frp/releases/download/v0.70.0/frp_0.70.0_linux_amd64.tar.gz

# Linux ARM64
# wget https://github.com/fatedier/frp/releases/download/v0.70.0/frp_0.70.0_linux_arm64.tar.gz

# 解压
tar -xzf frp_0.70.0_*.tar.gz

# 只保�?frpc
cp frp_0.70.0_*/frpc ./
rm -rf frp_0.70.0_*
```

### Windows 下载示例

使用 PowerShell�?
```powershell
# 创建目录
New-Item -ItemType Directory -Path "$env:USERPROFILE\frp-visitor" -Force
Set-Location "$env:USERPROFILE\frp-visitor"

# 下载 Windows x86_64 版本
curl -L -o frp.zip https://github.com/fatedier/frp/releases/download/v0.70.0/frp_0.70.0_windows_amd64.zip

# 解压
Expand-Archive -Path frp.zip -DestinationPath .

# �?frpc.exe 放到当前目录
Move-Item frp_0.70.0_windows_amd64\frpc.exe .\frpc.exe
Remove-Item -Recurse frp_0.70.0_windows_amd64
```

---

## 2. 准备配置文件

把内网机器上�?`frpc-visitor.toml` 复制到访问端�?
```bash
# 从内网机器复制（示例�?scp 内网机器用户名@内网IP:/share/home/yangfan/frp/frpc-visitor.toml ~/frp-visitor/
```

或者手动创�?`~/frp-visitor/frpc-visitor.toml`�?
```toml
serverAddr = "<FRP_SERVER_ADDR>"
serverPort = 7000

auth.method = "token"
auth.token = "<FRP_AUTH_TOKEN>"

transport.tls.enable = true

[[visitors]]
name = "ssh-p2p-visitor"
type = "xtcp"
serverName = "ssh-p2p"
secretKey = "<FRP_SECRET_KEY>"
bindAddr = "127.0.0.1"
bindPort = 2222
keepTunnelOpen = false
```

> **注意**：`auth.token` �?`secretKey` 必须与公网服务器和内网机器上的配置完全一致�?
---

## 3. P2P 模式连接

### 3.1 启动访问�?frpc

**Linux / macOS�?*

```bash
cd ~/frp-visitor
./frpc -c ./frpc-visitor.toml
```

看到类似以下日志说明连接成功�?
```text
xtcp proxy started successfully
nat hole connection make success
```

如果打洞失败，日志会提示连接失败，此时请切到 TCP 模式�?
**后台运行（Linux / macOS）：**

```bash
nohup ./frpc -c ./frpc-visitor.toml > ./frpc-visitor.log 2>&1 &
echo $! > ./frpc-visitor.pid
```

停止后台进程�?
```bash
kill $(cat ./frpc-visitor.pid)
```

**Windows�?*

�?PowerShell 中运行：

```powershell
.\frpc.exe -c .\frpc-visitor.toml
```

### 3.2 SSH 连接内网机器

在访问端另开一个终端：

```bash
ssh -p 2222 内网用户名@127.0.0.1
```

**关键理解**�?- 这里连接的是访问端本机的 `127.0.0.1:2222`
- frpc-visitor 会把流量通过 P2P 隧道转发到内网机器的 `127.0.0.1:22`
- `内网用户名` 是内网机器上的用户名，不是公网服务器�?
### 3.3 配置 SSH 快捷登录

编辑访问端的 `~/.ssh/config`�?
```text
Host inner-p2p
    HostName 127.0.0.1
    Port 2222
    User 内网用户�?    IdentityFile ~/.ssh/id_rsa
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

之后直接�?
```bash
ssh inner-p2p
```

---

## 4. TCP 模式连接（备用）

如果 P2P 打洞失败，或者你临时不想运行访问�?frpc，可以使�?TCP 模式�?
### 前提

- 公网服务器部署时启用�?TCP 代理：`./setup-frps.sh --enable-tcp-proxy`
- 内网机器 `frpc.toml` 中启用了 `[[proxies]] name = "ssh-tunnel" type = "tcp" remotePort = 6000`

### 直接 SSH 连接

```bash
ssh -p 6000 内网用户名@<FRP_SERVER_ADDR>
```

配置快捷登录�?
```text
Host inner-tcp
    HostName <FRP_SERVER_ADDR>
    Port 6000
    User 内网用户�?    IdentityFile ~/.ssh/id_rsa
```

之后直接�?
```bash
ssh inner-tcp
```

---

## 5. 文件传输

### P2P 模式下传文件到内网机�?
```bash
scp -P 2222 本地文件 内网用户名@127.0.0.1:/远程路径/
```

### TCP 模式下传文件

```bash
scp -P 6000 本地文件 内网用户名@<FRP_SERVER_ADDR>:/远程路径/
```

---

## 6. 常见问题

### P2P 连接失败

1. 确认内网机器�?frpc 已启�?2. 确认公网服务�?frps 已启动且 `7000/tcp` 端口可达
3. 检查访问端能否访问 STUN 服务器（默认 `stun.easyvoip.com:3478`�?4. 尝试更换 STUN 服务器，�?`frpc-visitor.toml` 添加�?   ```toml
   natHoleStunServer = "stun.l.google.com:19302"
   ```
5. 如果处于对称�?NAT 环境（部分企业网/运营商），P2P 可能无法成功，请使用 TCP 模式

### 访问�?frpc 启动报错

- `auth token error`：token 与服务器不一�?- `proxy not found`：`serverName` 与内网机�?proxy �?`name` 不一�?- `secretKey mismatch`：`secretKey` 与内网机�?proxy �?`secretKey` 不一�?
### Windows 下无法运�?
- 确保下载的是 Windows 版本�?`frpc.exe`
- 首次运行可能提示 Windows 安全警告，点击“更多信息�?-> “仍要运行�?
---

## 7. 安全建议

1. **不要�?`frpc-visitor.toml` 上传到公开地方**，它包含 token �?secretKey
2. **内网机器 SSH 必须禁用密码登录**，仅使用密钥认证
3. **第一次连接时务必校验 SSH 主机密钥指纹**，防止中间人攻击
4. 在不受信任的电脑上不要保存私钥和配置文件
5. 离开电脑时停�?frpc-visitor，避免隧道被他人利用

---

## 8. 快捷命令参�?
| 操作 | P2P 模式 | TCP 模式 |
|------|----------|----------|
| 启动访问�?| `./frpc -c ./frpc-visitor.toml` | 不需�?|
| SSH 登录 | `ssh -p 2222 用户@127.0.0.1` | `ssh -p 6000 用户@<FRP_SERVER_ADDR>` |
| 上传文件 | `scp -P 2222 文件 用户@127.0.0.1:/路径/` | `scp -P 6000 文件 用户@<FRP_SERVER_ADDR>:/路径/` |
| 下载文件 | `scp -P 2222 用户@127.0.0.1:/文件 ./` | `scp -P 6000 用户@<FRP_SERVER_ADDR>:/文件 ./` |
| SFTP | `sftp -P 2222 用户@127.0.0.1` | `sftp -P 6000 用户@<FRP_SERVER_ADDR>` |
