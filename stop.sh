#!/bin/sh
pids=$(lsof -ti tcp:4770 2>/dev/null)
[ -n "$pids" ] && kill $pids && echo "已停止 FizzDeck" || echo "未在运行"
