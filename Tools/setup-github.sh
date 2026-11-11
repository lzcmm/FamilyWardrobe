#!/usr/bin/env bash
# ==============================================================
# 一键接入 GitHub（只需要一个 Personal Access Token）
#
#   bash Tools/setup-github.sh ghp_xxxxxxxxxxxxxxxxxxxx
#
# 自动完成：
#   1. 校验令牌 + 取你的 GitHub 用户名（不用手动告诉我）
#   2. 创建公开仓库 FamilyWardrobe（已存在则复用）
#   3. 本地分支 master → main，与 GitHub 默认分支对齐
#   4. 推送全部提交
#   5. remote 写成不带令牌的干净地址（令牌绝不落盘）
#
# 安全说明：令牌只作为命令行参数参与本次推送，不写入任何文件、
#           不写入 .git/config、不写入 git remote。推完请到
#           GitHub → Settings → Developer settings 吊销该令牌。
# ==============================================================
set -euo pipefail

TOKEN="${1:-}"
REPO_NAME="${2:-FamilyWardrobe}"

if [ -z "$TOKEN" ]; then
  echo "用法: bash Tools/setup-github.sh <访问令牌> [仓库名]"
  echo ""
  echo "令牌申请页（已预填权限）:"
  echo "  https://github.com/settings/tokens/new?scopes=repo,workflow&description=FamilyWardrobe"
  exit 1
fi

API="https://api.github.com"
AUTH="Authorization: Bearer $TOKEN"

echo "==> 1/5 校验令牌..."
HTTP=$(curl -s -o /tmp/gh-user.json -w "%{http_code}" \
  -H "$AUTH" -H "Accept: application/vnd.github+json" "$API/user")
if [ "$HTTP" != "200" ]; then
  echo "❌ 令牌无效（HTTP $HTTP）。请确认："
  echo "   - 复制完整，没有多余空格"
  echo "   - 是 Tokens (classic) 且勾选了 repo 权限"
  echo "   - 没有过期"
  cat /tmp/gh-user.json 2>/dev/null | head -c 300; echo
  exit 1
fi
USER_NAME=$(python -c "import json,io; print(json.load(io.open('/tmp/gh-user.json',encoding='utf-8'))['login'])")
echo "    ✓ 已登录账号: $USER_NAME"

echo "==> 2/5 创建公开仓库 $REPO_NAME ..."
HTTP=$(curl -s -o /tmp/gh-repo.json -w "%{http_code}" -X POST \
  -H "$AUTH" -H "Accept: application/vnd.github+json" \
  "$API/user/repos" \
  -d "{\"name\":\"$REPO_NAME\",\"description\":\"家庭衣橱 · 离线 iOS App\",\"private\":false,\"auto_init\":false,\"has_issues\":false,\"has_wiki\":false,\"has_projects\":false}")
case "$HTTP" in
  201) echo "    ✓ 仓库已创建（Public）" ;;
  422) echo "    ✓ 仓库已存在，直接复用" ;;
  *)   echo "❌ 创建失败（HTTP $HTTP）"; head -c 400 /tmp/gh-repo.json; echo; exit 1 ;;
esac

CLEAN_URL="https://github.com/$USER_NAME/$REPO_NAME.git"
PUSH_URL="https://$TOKEN@github.com/$USER_NAME/$REPO_NAME.git"

echo "==> 3/5 对齐分支名 (master → main)..."
git branch -M main
echo "    ✓ 当前分支: $(git branch --show-current)"

echo "==> 4/5 推送 $(git rev-list --count HEAD) 个提交..."
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$CLEAN_URL"
else
  git remote add origin "$CLEAN_URL"
fi
# 用带令牌的一次性 URL 推送，不经过 remote，令牌不落盘
git push "$PUSH_URL" main
# 建立干净的 upstream
git fetch -q "$CLEAN_URL" main 2>/dev/null || true
git branch --set-upstream-to=origin/main main 2>/dev/null || true

echo "==> 5/5 校验..."
echo "    remote: $(git remote get-url origin)"
echo "    令牌是否出现在配置中: $(git remote -v | grep -c "$TOKEN" || true) 处（应为 0）"

echo ""
echo "✅ 完成！"
echo ""
echo "   仓库:      https://github.com/$USER_NAME/$REPO_NAME"
echo "   Actions:   https://github.com/$USER_NAME/$REPO_NAME/actions"
echo ""
echo "下一步：打开 Actions → iOS Unsigned Build → Run workflow"
echo "        10–15 分钟后下载 FamilyWardrobe-unsigned-ipa 里的 .ipa"
echo ""
echo "⚠️  推送完成后请吊销令牌："
echo "    https://github.com/settings/tokens"
