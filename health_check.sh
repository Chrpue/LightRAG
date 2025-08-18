#!/bin/sh
# 文件名: healthcheck.sh

# 遇到任何错误立即退出
set -e

# 首先，用最简单的方式检查 Web 服务器的端口是否已开始监听。
# netcat(nc) 是一个网络工具，-z 表示扫描模式，-w1 表示1秒超时。
# 如果端口未开放，脚本会以失败状态退出，Docker 会稍后重试。
if ! nc -z -w1 localhost 9621; then
  echo "Healthcheck: Web server on port 9621 is not listening yet."
  exit 1
fi

# 其次，也是最关键的一步：检查 LightRAG 自己的日志文件。
# lightrag.log 的路径是 /app/lightrag.log（在容器内部）。
# 我们使用 grep -q 来静默搜索 "Application startup complete." 这句话。
if grep -q "Application startup complete" /app/lightrag.log; then
  echo "Healthcheck PASSED: Found 'Application startup complete' in logs."
  exit 0 # 找到了！向 Docker 报告健康（退出码 0）。
else
  echo "Healthcheck FAILED: 'Application startup complete' not yet found in logs. Waiting..."
  exit 1 # 还没找到。向 Docker 报告不健康（退出码 1），Docker 会稍后重试。
fi
