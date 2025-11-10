#!/usr/bin/env bash
set -euo pipefail

: <<'DOC'
  スクリプト名: bump-and-release.sh
  目的:
    コミット内容から自動的に SemVer (major / minor / patch) を判定し、タグと GitHub Release を作成する軽量スクリプト。
  前提条件:
    - 環境変数: GITHUB_REPOSITORY (owner/repo), GITHUB_TOKEN
    - ツール: git(履歴+タグ取得), jq, curl
  判定規則 (優先度順):
    1. コミット本文に `BREAKING CHANGE` を含む または 先頭型名/スコープ直後に `!` が付く → major
    2. 件名が `feat:` / `feat(scope):` で始まる → minor
    3. 上記以外 → patch
  処理フロー (手順):
    1. 必須環境変数検証
    2. タグ取得 (保険的 fetch)
    3. 最新タグ決定 (無い場合は 0.0.0)
    4. コミット本文/件名収集
    5. バージョン種別判定
    6. 次バージョン計算
    7. 既存タグ衝突チェック
    8. 注釈付きタグ作成 & push
    9. CHANGELOG 生成
   10. Release API 呼び出し
   11. 結果出力
DOC

REPO="${GITHUB_REPOSITORY:-}"
TOKEN="${GITHUB_TOKEN:-}"
REMOTE="origin"

# Step 1: Validate environment / 必須環境変数確認
if [ -z "$REPO" ] || [ -z "$TOKEN" ]; then
  echo "ERROR: GITHUB_REPOSITORY and GITHUB_TOKEN must be set in the environment"
  exit 1
fi

# Step 2: Fetch tags / タグ最新化 (冪等)
git fetch --tags ${REMOTE} || true

# Step 3: Determine last tag / 最新タグ取得 (無ければ初期値)
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0")
echo "last tag: ${LAST_TAG}"

# Step 4: Collect commit bodies / コミット本文収集
COMMIT_BODIES=$(git log "${LAST_TAG}"..HEAD --pretty=format:'%B%n<<ENDCOMMIT>>%n')

# Step 5: Decide bump kind / バージョン種別判定
BUMP="patch"
if echo "$COMMIT_BODIES" | grep -q "BREAKING CHANGE"; then
  BUMP="major"
elif git log "${LAST_TAG}"..HEAD --pretty=format:'%s' | grep -E -i '^[a-z]+(\([^)]+\))?!:' >/dev/null; then
  BUMP="major"
elif git log "${LAST_TAG}"..HEAD --pretty=format:'%s' | grep -Ei '^feat(\:|\()' >/dev/null; then
  BUMP="minor"
else
  BUMP="patch"
fi
echo "detected bump: ${BUMP}"

# Step 6: Compute next version / 次バージョン計算
VER="${LAST_TAG#v}"
IFS='.' read -r MA MI PA <<< "${VER}"
MA=${MA:-0}; MI=${MI:-0}; PA=${PA:-0}
case "${BUMP}" in
  major) MA=$((MA+1)); MI=0; PA=0 ;;
  minor) MI=$((MI+1)); PA=0 ;;
  patch) PA=$((PA+1)) ;;
esac
NEW_TAG="${MA}.${MI}.${PA}"
echo "new tag: ${NEW_TAG}"

# Step 7: Check remote collision / 重複タグ存在確認
if git ls-remote --tags ${REMOTE} | grep -q "refs/tags/${NEW_TAG}$"; then
  echo "Tag ${NEW_TAG} already exists on remote — aborting tag creation."
  exit 0
fi

# Step 8: Create & push annotated tag / タグ作成 & push
git tag -a "${NEW_TAG}" -m "Release ${NEW_TAG}"
echo "pushing tag ${NEW_TAG} ..."
git push ${REMOTE} "refs/tags/${NEW_TAG}"

# Step 9: Build CHANGELOG / CHANGELOG 生成
CHANGELOG=$(git --no-pager log "${LAST_TAG}"..HEAD --pretty=format:'- %h %s (%an)' | sed 's/"/\\"/g')
if [ -z "$CHANGELOG" ]; then
  CHANGELOG="(no changes listed)"
fi

# Step 10: Call Release API / GitHub Release 作成
JSON=$(jq -nc --arg tag "${NEW_TAG}" --arg name "${NEW_TAG}" --arg body "${CHANGELOG}" \
  '{ tag_name: $tag, name: $name, body: $body, draft: false, prerelease: false }')
echo "creating GitHub Release for ${NEW_TAG} ..."
RELEASE_URL=$(curl -s -H "Authorization: token ${TOKEN}" -H "Content-Type: application/json" \
  -d "${JSON}" "https://api.github.com/repos/${REPO}/releases" | jq -r '.html_url // empty')

# Step 11: Output result / 結果出力
if [ -n "$RELEASE_URL" ]; then
  echo "Release created: ${RELEASE_URL}"
else
  echo "Warning: Release creation may have failed or returned no URL."
fi

# (出力例)
# last tag: 1.2.2
# detected bump: minor
# new tag: 1.3.0
# pushing tag 1.3.0 ...
# Release created: https://github.com/owner/repo/releases/tag/1.3.0

exit 0
