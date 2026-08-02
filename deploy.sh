#!/usr/bin/env bash
# GitHub Pages への公開スクリプト（匿名運用前提）
#
# 使い方:  ./deploy.sh <新規GitHubユーザー名> <ユーザーID>
#   例:    ./deploy.sh cryptotaxlab 123456789
#
# ユーザーIDは https://api.github.com/users/<ユーザー名> の "id" の値。
# noreply メール <ID>+<ユーザー名>@users.noreply.github.com を
# コミットのauthorに使うことで、本物のメールアドレスの露出を防ぐ。

set -euo pipefail

USER_NAME="${1:?第1引数に新規GitHubユーザー名を指定してください}"
USER_ID="${2:?第2引数にGitHubユーザーIDを指定してください}"

REPO="${USER_NAME}.github.io"
SITE_URL="https://${USER_NAME}.github.io"
NOREPLY="${USER_ID}+${USER_NAME}@users.noreply.github.com"

cd "$(dirname "$0")"

echo "==> 公開先: ${SITE_URL}"
echo "==> コミットauthor: ${NOREPLY}"
echo

# --- 1. 認証確認（既存アカウントで公開する事故を防ぐ） ---
ACTIVE=$(gh api user --jq .login 2>/dev/null || echo "")
if [ -z "$ACTIVE" ]; then
  echo "!! gh が認証されていません。先に  gh auth login  を実行してください。" >&2
  exit 1
fi
if [ "$ACTIVE" != "$USER_NAME" ]; then
  echo "!! 中断：gh は '${ACTIVE}' で認証されています（指定は '${USER_NAME}'）。" >&2
  echo "   別アカウントで公開すると匿名性が失われます。認証を切り替えてください。" >&2
  exit 1
fi
echo "==> 認証OK: ${ACTIVE}"

# --- 2. 内部メモ(.todoブロック)の残存検出 ---
#     実測データが空のまま、あるいは編集用メモが見えたまま公開されるのを防ぐ
if grep -q 'class="todo"' index.html; then
  echo
  echo "!! 中断：index.html に内部メモ（赤い点線ブロック）が残っています。" >&2
  grep -n 'class="todo"' index.html | sed 's/^/   行/' >&2
  echo "   実測データを記入し、該当の <div class=\"todo\"> ... </div> を削除してから再実行してください。" >&2
  exit 1
fi

# --- 3. プレースホルダURLの置換 ---
for f in index.html robots.txt sitemap.xml; do
  perl -pi -e "s|__SITE_URL__|${SITE_URL}|g" "$f"
done
echo "==> URLを ${SITE_URL} に置換しました"

if grep -rq "__SITE_URL__" . --include="*.html" --include="*.txt" --include="*.xml"; then
  echo "!! 置換漏れがあります" >&2; exit 1
fi

# --- 4. git リポジトリ初期化（identityはリポジトリ内のみに設定） ---
if [ ! -d .git ]; then
  git init -q -b main
fi
git config user.name "$USER_NAME"
git config user.email "$NOREPLY"

git add -A
git commit -q -m "Publish: Triaカード税務ガイド" || echo "==> 変更なし（コミットをスキップ）"

# --- 5. コミットにメールが漏れていないか最終確認 ---
LEAK=$(git log --format='%ae' | grep -v "users.noreply.github.com" || true)
if [ -n "$LEAK" ]; then
  echo "!! 中断：コミットに noreply 以外のメールが含まれています:" >&2
  echo "$LEAK" >&2
  exit 1
fi
echo "==> コミットauthorの確認OK（noreplyのみ）"

# --- 6. リポジトリ作成とpush ---
if ! gh repo view "${USER_NAME}/${REPO}" >/dev/null 2>&1; then
  gh repo create "${REPO}" --public --source=. --remote=origin --push
else
  git remote get-url origin >/dev/null 2>&1 || \
    git remote add origin "https://github.com/${USER_NAME}/${REPO}.git"
  git push -u origin main
fi

echo
echo "==> 完了。数分後に公開されます: ${SITE_URL}/"
echo "    Pagesの状態: gh api repos/${USER_NAME}/${REPO}/pages --jq .status"
