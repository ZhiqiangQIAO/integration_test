#!/bin/bash
# ============================================================
# biz-test curl 执行脚本
# 用法: ./curl-exec.sh <method> <url> <timeout_ms> <retry_max> [headers...] [-d <body>]
# 输出: 三行 —— HTTP_CODE, DURATION_SEC, BODY
# ============================================================
set -e

METHOD="$1"
URL="$2"
TIMEOUT_MS="$3"
RETRY_MAX="$4"
shift 4

# 分离请求头和请求体
HEADERS=()
BODY=""
while [ $# -gt 0 ]; do
  case "$1" in
    -d) BODY="$2"; shift 2 ;;
    *)  HEADERS+=("$1"); shift ;;
  esac
done

TIMEOUT_SEC=$((TIMEOUT_MS / 1000))
RETRY_COUNT=0

while [ $RETRY_COUNT -le $RETRY_MAX ]; do
  START=$(date +%s%N)

  # 构造 curl 参数
  CURL_ARGS=(-s -w "\n%{http_code}" --max-time "$TIMEOUT_SEC" -X "$METHOD")
  for h in "${HEADERS[@]}"; do
    CURL_ARGS+=(-H "$h")
  done
  if [ -n "$BODY" ]; then
    CURL_ARGS+=(-d "$BODY")
  fi
  CURL_ARGS+=("$URL")

  RESPONSE=$(curl "${CURL_ARGS[@]}" 2>/dev/null) || true
  END=$(date +%s%N)

  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  BODY_RESP=$(echo "$RESPONSE" | sed '$d')
  DURATION=$(echo "scale=3; ($END - $START) / 1000000000" | bc)

  # 非 5xx 或已达重试上限，直接返回
  if [ "$HTTP_CODE" -lt 500 ] 2>/dev/null || [ $RETRY_COUNT -ge $RETRY_MAX ]; then
    echo "$HTTP_CODE"
    echo "$DURATION"
    echo "$BODY_RESP"
    exit 0
  fi

  RETRY_COUNT=$((RETRY_COUNT + 1))
  sleep $((RETRY_COUNT * 2))
done