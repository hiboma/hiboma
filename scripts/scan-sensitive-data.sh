#!/bin/bash
#
# scan-sensitive-data.sh — git diff の差分から秘匿情報・個人特定情報を検出する
#
# 用途:
#   - git pre-commit hook から呼ばれる
#   - Claude Code の hook から呼ばれる
#   - 手動実行: scripts/scan-sensitive-data.sh [--staged | --file <path>]
#
# 終了コード:
#   0 — 検出なし
#   1 — 秘匿情報を検出（commit をブロックすべき）
#   2 — スクリプトのエラー

set -euo pipefail

# --- 検出パターン定義 ---

# ホームディレクトリパス（ユーザー名を含む）
# /Users/<username>/ や /home/<username>/ を検出する
# ただし /Users/hito/src/github.com/hiboma/hiboma は除外（リポジトリパス自体の参照は許容）
PATTERN_HOME_DIR='(/Users/[a-zA-Z0-9._-]+/|/home/[a-zA-Z0-9._-]+/)'

# API キー・トークン
PATTERN_API_KEYS='(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36,}|ghs_[a-zA-Z0-9]{36,}|AKIA[0-9A-Z]{16}|xoxb-[0-9a-zA-Z-]+|xoxp-[0-9a-zA-Z-]+)'

# Bearer トークン
PATTERN_BEARER='Bearer\s+[a-zA-Z0-9._\-]+'

# パスワード・シークレットの代入パターン
PATTERN_PASSWORD='(password|passwd|secret|token|api_key|apikey|access_key|secret_key)\s*[=:]\s*["\x27][^"\x27]{8,}'

# SSH 秘密鍵ヘッダ
PATTERN_SSH_KEY='BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY'

# AWS アカウント ID（12桁数字）
PATTERN_AWS_ACCOUNT='[0-9]{12}\.dkr\.ecr\.|arn:aws:[a-z0-9-]+:[a-z0-9-]*:[0-9]{12}:'

# メールアドレス（コード中のリテラル）
# @example.com, @example.org, noreply 系は除外
PATTERN_EMAIL='[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'
PATTERN_EMAIL_EXCLUDE='(@example\.(com|org|net)|@localhost|noreply@|@users\.noreply\.github\.com)'

# --- 除外パターン ---

# このリポジトリ自体のパスは許容する（git リポジトリルートを動的に取得）
EXCLUDE_REPO_PATH="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# --- 関数 ---

red() { printf '\033[0;31m%s\033[0m\n' "$1"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$1"; }

scan_content() {
    local content="$1"
    local source_label="${2:-stdin}"
    local found=0

    # ホームディレクトリパス
    while IFS= read -r line; do
        # リポジトリパスの参照は除外
        if [[ "$line" == *"$EXCLUDE_REPO_PATH"* ]]; then
            continue
        fi
        red "[BLOCK] ホームディレクトリパスを検出: $source_label"
        yellow "  $line"
        found=1
    done < <(echo "$content" | grep -nE "$PATTERN_HOME_DIR" || true)

    # API キー・トークン
    while IFS= read -r line; do
        red "[BLOCK] API キー/トークンを検出: $source_label"
        yellow "  $line"
        found=1
    done < <(echo "$content" | grep -nE "$PATTERN_API_KEYS" || true)

    # Bearer トークン
    while IFS= read -r line; do
        red "[BLOCK] Bearer トークンを検出: $source_label"
        yellow "  $line"
        found=1
    done < <(echo "$content" | grep -nE "$PATTERN_BEARER" || true)

    # パスワード・シークレット代入
    while IFS= read -r line; do
        red "[BLOCK] パスワード/シークレットの代入を検出: $source_label"
        yellow "  $line"
        found=1
    done < <(echo "$content" | grep -nEi "$PATTERN_PASSWORD" || true)

    # SSH 秘密鍵
    while IFS= read -r line; do
        red "[BLOCK] SSH 秘密鍵ヘッダを検出: $source_label"
        yellow "  $line"
        found=1
    done < <(echo "$content" | grep -nE -e "$PATTERN_SSH_KEY" || true)

    # AWS アカウント ID
    while IFS= read -r line; do
        red "[BLOCK] AWS アカウント ID を検出: $source_label"
        yellow "  $line"
        found=1
    done < <(echo "$content" | grep -nE "$PATTERN_AWS_ACCOUNT" || true)

    # メールアドレス（除外パターンを適用）
    while IFS= read -r line; do
        if echo "$line" | grep -qE "$PATTERN_EMAIL_EXCLUDE"; then
            continue
        fi
        red "[BLOCK] メールアドレスを検出: $source_label"
        yellow "  $line"
        found=1
    done < <(echo "$content" | grep -nE "$PATTERN_EMAIL" || true)

    return $found
}

# --- メイン ---

mode="staged"
target_file=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --staged)
            mode="staged"
            shift
            ;;
        --file)
            mode="file"
            target_file="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--staged | --file <path>]"
            echo "  --staged  git diff --staged の差分をスキャン (デフォルト)"
            echo "  --file    指定ファイルの内容をスキャン"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

exit_code=0

case "$mode" in
    staged)
        # ステージされた差分の追加行のみをスキャン
        diff_content=$(git diff --staged --diff-filter=ACMR --no-color -U0 2>/dev/null || true)
        if [[ -z "$diff_content" ]]; then
            exit 0
        fi

        # 追加行のみ抽出（+で始まる行、ただし +++ は除く）
        added_lines=$(echo "$diff_content" | grep -E '^\+[^+]' | sed 's/^\+//' || true)
        if [[ -z "$added_lines" ]]; then
            exit 0
        fi

        scan_content "$added_lines" "staged changes" || exit_code=1
        ;;
    file)
        if [[ ! -f "$target_file" ]]; then
            echo "File not found: $target_file" >&2
            exit 2
        fi
        file_content=$(cat "$target_file")
        scan_content "$file_content" "$target_file" || exit_code=1
        ;;
esac

if [[ $exit_code -eq 0 ]]; then
    echo "秘匿情報は検出されませんでした。"
fi

exit $exit_code
