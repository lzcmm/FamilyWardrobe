#!/usr/bin/env bash
# 监听一次 GitHub Actions 构建直到结束，结束后打印各步骤状态。
# 用法: bash Tools/watch-build.sh <token> <run-id>
set -u
TOKEN="${1:-}"
RUNID="${2:-}"
REPO="lzcmm/FamilyWardrobe"

if [ -z "$TOKEN" ] || [ -z "$RUNID" ]; then
  echo "用法: bash Tools/watch-build.sh <token> <run-id>"
  exit 1
fi

API="https://api.github.com/repos/$REPO/actions/runs/$RUNID"
AUTH="Authorization: Bearer $TOKEN"

echo "开始监听 run $RUNID（每 60 秒一次，最多 25 分钟）"
for i in $(seq 1 25); do
  R=$(curl -s -m 30 -H "$AUTH" "$API")
  STATUS=$(printf '%s' "$R" | python -c "import json,sys; print(json.load(sys.stdin).get('status','?'))" 2>/dev/null || echo "?")
  CONC=$(printf '%s' "$R" | python -c "import json,sys; print(json.load(sys.stdin).get('conclusion') or '-')" 2>/dev/null || echo "-")
  echo "[$(date +%H:%M:%S)] $RUNID  status=$STATUS  conclusion=$CONC"

  if [ "$STATUS" = "completed" ]; then
    echo ""
    echo "=== 构建结束: $CONC ==="
    echo "=== 步骤明细 ==="
    curl -s -m 30 -H "$AUTH" "$API/jobs" | python -c "
import json,sys
d=json.load(sys.stdin)
for j in d.get('jobs',[]):
    print('JOB:', j['name'], '|', j.get('conclusion'))
    for s in j.get('steps',[]):
        print('  %-32s %s' % (s['name'][:32], s.get('conclusion') or '-'))
" 2>&1
    echo ""
    echo "日志下载端点: $API/logs"
    exit 0
  fi
  sleep 60
done
echo "超时：25 分钟内未结束，请到 Actions 页面查看"
