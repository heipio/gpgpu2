#!/bin/bash
# ============================================
# 手动停止 frpc-visitor
# ============================================

FRP_DIR="/share/home/yangfan/frp"
PIDFILE="$FRP_DIR/frpc-visitor.pid"

if [ ! -f "$PIDFILE" ]; then
    echo "frpc-visitor 未运行（找不到 PID 文件）"
    exit 0
fi

PID=$(cat "$PIDFILE")

if kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    echo "frpc-visitor 已停止，PID: $PID"
else
    echo "frpc-visitor 进程已不存在，清理残留 PID 文件"
fi

rm -f "$PIDFILE"
