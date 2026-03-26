---
description: "コマンド出力や実行履歴を含む markdown を commit する前に秘匿情報をスキャンする"
globs: "**/*.md"
---

# 秘匿情報スキャンルール

## 適用タイミング

以下のいずれかに該当する場合、commit 前に必ず `scripts/scan-sensitive-data.sh` を実行します。

- コマンドの実行結果・出力をマークダウンに記録した場合
- 環境変数、設定ファイルの内容を引用した場合
- ログ出力を貼り付けた場合
- strace, ltrace, tcpdump 等のトレース出力を記録した場合

## 検出対象

| カテゴリ | 例 |
|---|---|
| ホームディレクトリパス | `/Users/<username>/`, `/home/<username>/` |
| API キー・トークン | `sk-*`, `ghp_*`, `ghs_*`, `AKIA*`, `xoxb-*`, `xoxp-*` |
| Bearer トークン | `Bearer <token>` |
| パスワード・シークレット代入 | `password=`, `secret:`, `token=` |
| SSH 秘密鍵 | `-----BEGIN * PRIVATE KEY-----` |
| AWS アカウント ID | ARN, ECR URL に含まれる 12桁数字 |
| メールアドレス | `user@domain.tld` (example.com, noreply 系を除く) |

## 検出時の対応

1. **ブロック**: commit を中止し、該当箇所をユーザーに報告します
2. **マスク提案**: 以下のマスク表記を提案します
   - ホームディレクトリパス → `/Users/<USER>/` または `/home/<USER>/`
   - API キー・トークン → `sk-****`, `ghp_****`
   - メールアドレス → `user@example.com`
   - AWS アカウント ID → `123456789012`
   - IP アドレス → `x.x.x.x`
3. **ユーザー確認**: マスク適用の可否をユーザーに確認してから修正します

## 除外

- リポジトリパス自体への参照（`git rev-parse --show-toplevel` で得られるパス）は許容します
- `@example.com`, `@example.org`, `noreply@` 等のダミーアドレスは除外します
- カーネルソースコードの引用に含まれるコード上のパターンは文脈で判断します
