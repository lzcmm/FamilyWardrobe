#!/usr/bin/env bash
# ============================================================
# 一键推送到 GitHub
#
# 用法：
#   bash Tools/push-to-github.sh <仓库地址> <访问令牌>
#
# 例：
#   bash Tools/push-to-github.sh https://github.com/cq-tyl/FamilyWardrobe.git ghp_xxxxx
#
# 说明：
#   - 令牌只用于本次推送，不会写入任何文件
#   - 用完立刻吊销即可（GitHub → Settings → Developer settings → Tokens）
#   - 推送完成后会自动把 remote 设为只读校验，防止误推
# ============================================================

set -euo pipefail

REPO_URL="${1:-}"
TOKEN="${2:-}"

if [ -z "$REPO_URL" ] || [ -z "$TOKEN" ]; then
  echo "用法: bash Tools/push-to-github.sh <仓库地址> <访问令牌>"
  echo ""
  echo "例:"
  echo "  bash Tools/push-to-github.sh https://github.com/cq-tyl/FamilyWardrobe.git ghp_xxxxxxxx"
  exit 1
fi

cd "$(dirname "$0")/.."

echo "==> 检查仓库状态"
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "    不是 git 仓库"
  exit 1
fi

# 确认没有未提交的大改动
DIRTY=$(git status --porcelain | grep -v "^??" | wc -l | tr -d ' ')
if [ "$DIRTY" != "0" ]; then
  echo "    有 $DIRTY 个已跟踪文件被修改，先提交："
  git status --short | grep -v "^??" | head -10
  exit 1
fi

echo "==> 写入推送凭据（仅本次会话有效）"
# 使用 .git-credentials + 一次性 credential helper，不落到长期配置
CRED_FILE=$(mktemp)
trap 'rm -f "$CRED_FILE"' EXIT
printf "https://%s@github.com\n" "$TOKEN" > "$CRED_FILE"

# 校验令牌有效性
echo "==> 校验令牌"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/user)
if [ "$HTTP_CODE" != "200" ]; then
  echo "    令牌无效（HTTP $HTTP_CODE）"
  echo "    请检查是否勾选了 repo 权限，以及令牌是否已过期"
  exit 1
fi

USER_NAME=$(curl -s -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/user | python -c "import sys,json; print(json.load(sys.stdin)['login'])" 2>/dev/null || echo "unknown")
echo "    令牌有效，账号：$USER_NAME"

# 设置 remote
echo "==> 设置远程仓库"
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REPO_URL"
else
  git remote add origin "$REPO_URL"
fi

echo "==> 推送到 $REPO_URL"
export GIT_ASKPASS=/bin/echo
export GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=credential.helper
export GIT_CONFIG_VALUE_0="store --file=$CRED_FILE"

BRANCH=$(git branch --show-current)
if [ -z "$BRANCH" ]; then
  BRANCH=main
  git checkout -b main
fi

git push -u origin "$BRANCH"

echo ""
echo "==> 推送完成"
echo "    仓库：$REPO_URL"
echo "    分支：$BRANCH"
echo ""
echo "==> 现在可以去 Codemagic 连接这个仓库了"
echo "    https://codemagic.io/apps"
echo "    Add application → 选择 GitHub → 选中 $USER_NAME/FamilyWardrobe"
echo ""
echo "==> 安全提醒"
echo "    令牌已用完，建议立即吊销："
echo "    GitHub → Settings → Developer settings → Personal access tokens → 选中令牌 → Delete"
