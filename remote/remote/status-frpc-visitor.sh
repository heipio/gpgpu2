#!/bin/bash
# ============================================
# 查看 frpc-visitor 运行状态
# ============================================

FRP_DIR="/share/home/yangfan/frp"
PIDFILE="$FRP_DIR/frpc-visitor.pid"
LOGFILE="$FRP_DIR/frpc-visitor.log"

if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "frpc-visitor 正在运行，PID: $PID"
        echo ""
        echo "=== 最近 20 行日志 ==="
        tail -n 20 "$LOGFILE" 2>/dev/null
    else
        echo "frpc-visitor 未运行（PID 文件残留）"
    fi
else
    echo "frpc-visitor 未运行"
fi
