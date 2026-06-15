#!/usr/bin/env bash
#
# git_push.sh — 一键把当前项目推送到 GitHub（通用版）
#
# 用 SSH 协议（你需要先把 ~/.ssh/id_ed25519 公钥加到 GitHub），不需要 token/密码。
# 脚本是幂等的：再次运行是安全的（remote 已配好就跳过，commit 已存在就跳过）。
#
# 用法：
#   GITHUB_USER=adaidi01 GITHUB_REPO=my-repo bash git_push.sh
#   或者直接跑，缺参数会问你
#
# 前置：远端仓库要在 https://github.com/new 先建空（Public，不勾任何初始化）

set -euo pipefail

# ─── 0. 拿参数 ─────────────────────────────────
REPO_USER="${GITHUB_USER:-${1:-}}"
REPO_NAME="${GITHUB_REPO:-${2:-}}"

# 如果还是空，尝试从当前 git remote 推断
if [[ -z "$REPO_USER" || -z "$REPO_NAME" ]] && git remote get-url origin >/dev/null 2>&1; then
  origin_url=$(git remote get-url origin)
  if [[ "$origin_url" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
    : "${REPO_USER:=${BASH_REMATCH[1]}}"
    : "${REPO_NAME:=${BASH_REMATCH[2]}}"
  fi
fi

# 还是空？问用户
if [[ -z "$REPO_USER" ]]; then
  read -rp "GitHub 用户名: " REPO_USER
fi
if [[ -z "$REPO_NAME" ]]; then
  read -rp "仓库名（GitHub 上已建好的空仓库）: " REPO_NAME
fi

if [[ -z "$REPO_USER" || -z "$REPO_NAME" ]]; then
  echo "✗ 缺参数：需要 GitHub 用户名 + 仓库名" >&2
  exit 1
fi

REPO_URL="git@github.com:${REPO_USER}/${REPO_NAME}.git"
BRANCH="${BRANCH:-main}"

BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

step() { echo -e "\n${BOLD}${GREEN}>>> $1${RESET}"; }
warn() { echo -e "${YELLOW}⚠ $1${RESET}"; }
err()  { echo -e "${RED}✗ $1${RESET}" >&2; }
ok()   { echo -e "${GREEN}✓ $1${RESET}"; }

# ─── 0. 隐私审计 ──────────────────────────────
step "隐私审计：扫描 /Users/、硬编码 token、绝对路径"
leaks=0

# 检查源码里的绝对路径（macOS 用户目录）
if grep -rn "/Users/[a-z]" --include="*.py" --include="*.sh" --include="*.json" --include="*.md" --include="*.txt" . 2>/dev/null \
     | grep -v "^./\.git/" | grep -v "/listen-to-claude/" | grep -v "/push-to-github/" > /tmp/leaks.txt; then
  warn "发现可能的用户名/绝对路径泄露："
  head -10 /tmp/leaks.txt
  leaks=1
fi

# 检查硬编码 token / API key
if grep -rEn "(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})" --include="*.py" --include="*.sh" --include="*.json" --include="*.md" --include="*.txt" . 2>/dev/null > /tmp/tokens.txt; then
  err "发现硬编码 token / API key："
  cat /tmp/tokens.txt
  err "已中止。先把这些挪到环境变量或 .gitignore 的文件里。"
  exit 1
fi

if [[ $leaks -eq 0 ]]; then
  ok "无个人信息 / token 泄露"
fi

# ─── 0.5 删录音文件（避免真实语音泄露） ──────
step "清理录音文件（避免真实语音泄露）"
if [[ -d recordings ]]; then
  rm -rf recordings/
  ok "recordings/ 已删除"
else
  ok "没有 recordings/，跳过"
fi

# ─── 1. 验证 git ──────────────────────────────
step "检查 git"
if ! command -v git >/dev/null 2>&1; then
  err "git 没装：brew install git"
  exit 1
fi
ok "git $(git --version | awk '{print $3}')"

# ─── 2. 验证 SSH 连通性 ───────────────────────
step "验证 SSH 能否连到 GitHub"
# GitHub SSH 服务器对没 shell 的用户会返回 exit code 1
# 所以我们必须单独看 stdout 内容，不管退出码
ssh_output=$(ssh -T -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new git@github.com 2>&1 || true)
if ! echo "$ssh_output" | grep -qE "successfully authenticated|Hi "; then
  err "SSH 连不上 GitHub。请确认："
  echo "  1) ~/.ssh/id_ed25519（或 id_rsa）存在"
  echo "  2) 公钥已加到 https://github.com/settings/keys"
  echo "  3) ssh -T git@github.com 能看到 Hi ${REPO_USER}!"
  echo ""
  echo "实际 SSH 输出："
  echo "$ssh_output"
  exit 1
fi
authed_user=$(echo "$ssh_output" | grep -oE "Hi [^!]+" | awk '{print $2}' || echo "?")
ok "SSH 已认证为 ${authed_user}（输出: $(echo "$ssh_output" | head -1)）"

if [[ "$authed_user" != "$REPO_USER" && "$authed_user" != "?" ]]; then
  warn "你给的 REPO_USER=${REPO_USER} 但 SSH 登录的是 ${authed_user}。确认没填错？"
fi

# ─── 3. git init（如未初始化） ─────────────────
step "初始化 git 仓库"
if [[ -d .git ]]; then
  ok ".git 已存在"
else
  git init --initial-branch="$BRANCH"
  ok "已 init，分支：$BRANCH"
fi

# 确保分支名是 main
current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
if [[ "$current_branch" != "$BRANCH" ]]; then
  git checkout -b "$BRANCH" 2>/dev/null || git branch -M "$BRANCH"
  ok "切换到 $BRANCH"
fi

# ─── 4. 配置 .gitignore 不会漏出不该传的 ─────
step "检查 .gitignore（只 warn，不会强制退出）"
recommended=(
  '.venv/' 'venv/' 'env/'
  '__pycache__/' '*.pyc'
  '.DS_Store' 'Thumbs.db'
  '*.log'
  'recordings/'
  'config.json' '.env' '.env.local'
  'whisper.cpp/' 'build/' 'dist/'
  '*.bin' '*.gguf' '*.ggml' '*.safetensors'
  'node_modules/'
  '.vscode/' '.idea/'
  '*.swp' '*.swo'
)
if [[ ! -f .gitignore ]]; then
  warn "没找到 .gitignore —— 强烈建议先建一个（脚本会继续，但可能漏出文件）"
  for pat in "${recommended[@]}"; do
    echo "  $pat"
  done
else
  missing=0
  for pat in "${recommended[@]}"; do
    if ! grep -qF "$pat" .gitignore; then
      warn "  $pat  不在 .gitignore 里（如果项目里没这种文件可忽略）"
    fi
  done
  ok ".gitignore 存在（已扫常见模式）"
fi

# ─── 5. 显式 add 文件（用 git add . 配合 .gitignore 兜底） ─
step "加入文件（git add . —— 靠 .gitignore 兜底）"
# 用 git add . + git status 检查，比逐个 add 更不易漏
# 但前提是 .gitignore 必须正确
if [[ ! -f .gitignore ]]; then
  err "没有 .gitignore 就 git add . 太危险了。先建 .gitignore 再跑脚本。"
  exit 1
fi

git add .

# ─── 6. 验证清单 ──────────────────────────────
step "即将提交的文件清单（请人工检查！）"
git status --short

# 二次确认：没有本应忽略的文件意外进入
problem_patterns='whisper\.cpp/|\.venv/|venv/|recordings/|xiaohongshu|config\.json$|\.env$|\.env\.local$|\.bin$|\.gguf$|\.ggml$'
problem=$(git status --short | grep -E "$problem_patterns" || true)
if [[ -n "$problem" ]]; then
  err "⚠⚠⚠ 下面这些文件不应该被提交："
  echo "$problem"
  err "已中止。检查 .gitignore 是否正确，或者把不想传的文件用 'git rm --cached' 取消跟踪。"
  exit 1
fi
ok "清单干净，没有意外文件"

# ─── 7. 提交 ─────────────────────────────────
step "本地提交"
if git rev-parse HEAD >/dev/null 2>&1; then
  # 已有提交，看有没有未提交的改动
  if [[ -z "$(git status --short)" ]]; then
    ok "没有新改动，跳过 commit"
  else
    warn "有未提交改动，下面会继续 add + commit"
    if ! git config user.email >/dev/null; then
      warn "没设置 git user.email，用 noreply 兜底"
      git config user.email "${REPO_USER}@users.noreply.github.com"
    fi
    if ! git config user.name >/dev/null; then
      warn "没设置 git user.name，用 ${REPO_USER} 兜底"
      git config user.name "${REPO_USER}"
    fi
    git commit -m "Update"
    ok "已 commit"
  fi
else
  if ! git config user.email >/dev/null; then
    warn "没设置 git user.email，用 ${REPO_USER}@users.noreply.github.com"
    git config user.email "${REPO_USER}@users.noreply.github.com"
  fi
  if ! git config user.name >/dev/null; then
    warn "没设置 git user.name，用 ${REPO_USER} 兜底"
    git config user.name "${REPO_USER}"
  fi
  # 推断一个合理的初版 commit message
  project_name=$(basename "$(pwd)")
  git commit -m "Initial commit: ${project_name}"
  ok "本地提交完成"
fi

# ─── 8. 配远程仓库 ───────────────────────────
step "配置远程仓库"
if git remote get-url origin >/dev/null 2>&1; then
  current_url=$(git remote get-url origin)
  if [[ "$current_url" != "$REPO_URL" ]]; then
    warn "origin 已存在但 URL 不对：$current_url"
    warn "改成 $REPO_URL"
    git remote set-url origin "$REPO_URL"
  fi
  ok "origin = $current_url"
else
  git remote add origin "$REPO_URL"
  ok "已加 origin = $REPO_URL"
fi

# ─── 9. 推送 ─────────────────────────────────
step "推送到 GitHub（用 SSH，不需要密码）"
echo ""
echo "如果远端仓库还没建，会推送失败。"
echo "确认在 https://github.com/${REPO_USER}/${REPO_NAME} 仓库已建好（Public，不勾任何初始化）。"
echo ""

# 探测远端是否有内容
remote_has_content=0
if git ls-remote --heads origin "$BRANCH" 2>/dev/null | grep -q "$BRANCH"; then
  remote_has_content=1
  warn "远端 ${BRANCH} 分支已有内容。普通 push 可能被拒绝。"
fi

read -p "按回车继续推送（Ctrl+C 取消）…"
echo ""

if [[ $remote_has_content -eq 1 ]]; then
  warn "远端有内容，尝试 git pull --rebase 后再 push（不会强推）"
  git pull --rebase origin "$BRANCH" || {
    err "git pull --rebase 失败。可能需要手动解决冲突，或用 --force-with-lease（不推荐）。"
    exit 1
  }
fi

git push -u origin "$BRANCH"

ok "🎉 推送完成！"
echo ""
echo "仓库地址：https://github.com/${REPO_USER}/${REPO_NAME}"
