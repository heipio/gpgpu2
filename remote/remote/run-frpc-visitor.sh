#!/bin/bash
# ============================================
# 手动启动 frpc-visitor（不使用 systemd）
# 适用于访问端：笔记本、台式机、办公电脑等
# P2P 模式：启动后通过 ssh -p 2222 用户@127.0.0.1 连接内网
# ============================================

FRP_DIR="/home/yangfan/frp_remote/frp"
PIDFILE="$FRP_DIR/frpc-visitor.pid"
LOGFILE="$FRP_DIR/frpc-visitor.log"
CONFIG="$FRP_DIR/frpc-visitor.toml"

cd "$FRP_DIR" || exit 1

# 检查配置文件是否存在
if [ ! -f "$CONFIG" ]; then
    echo "配置文件不存在: $CONFIG"
    echo "请从内网机器复制 frpc-visitor.toml 到该目录"
    exit 1
fi

# 检查是否已经在运行
if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "frpc-visitor 已经在运行，PID: $OLD_PID"
        echo "查看日志: tail -f $LOGFILE"
        exit 0
    else
        echo "发现残留 PID 文件，清理..."
        rm -f "$PIDFILE"
    fi
fi

# 启动 frpc-visitor
nohup ./frpc -c ./frpc-visitor.toml >> "$LOGFILE" 2>&1 &
NEW_PID=$!
echo "$NEW_PID" > "$PIDFILE"

echo "frpc-visitor 已启动，PID: $NEW_PID"
echo "日志文件: $LOGFILE"
echo "停止命令: ./stop-frpc-visitor.sh"
echo ""
echo "连接命令示例:"
echo "  ssh -p 2222 内网用户名@127.0.0.1"
