---
description: "秘匿情報のマスク処理を実行する。commit 前のスキャンで検出された秘匿情報をマスクする際に使用する"
---

# sensitive-data-guard

コマンド出力や実行履歴に含まれる秘匿情報をマスクするスキルです。

## 実行手順

### 1. スキャンの実行

```bash
# ステージ済みの差分をスキャン
scripts/scan-sensitive-data.sh --staged

# 特定ファイルをスキャン
scripts/scan-sensitive-data.sh --file <path>
```

### 2. 検出時のマスク置換

検出されたパターンに応じて以下のマスク表記に置換します。

| 検出パターン | マスク表記 | 例 |
|---|---|---|
| `/Users/<username>/...` | `/Users/<USER>/...` | `/Users/<USER>/src/project` |
| `/home/<username>/...` | `/home/<USER>/...` | `/home/<USER>/.config` |
| `sk-abc123...` | `sk-****` | API キー |
| `ghp_abc123...` | `ghp_****` | GitHub PAT |
| `ghs_abc123...` | `ghs_****` | GitHub App トークン |
| `AKIA...` | `AKIA****` | AWS Access Key ID |
| `xoxb-...` | `xoxb-****` | Slack Bot Token |
| `Bearer <token>` | `Bearer ****` | Bearer トークン |
| `password="value"` | `password="****"` | パスワード |
| SSH 秘密鍵 | `(SSH private key omitted)` | 鍵ファイル全体を除去 |
| `user@real-domain.com` | `user@example.com` | メールアドレス |
| AWS アカウント ID | `123456789012` | 12桁のダミー |
| グローバル IP | `x.x.x.x` | IP アドレス |

### 3. マスク後の確認

マスク置換を行った後、再度スキャンを実行して検出がゼロになることを確認します。

```bash
scripts/scan-sensitive-data.sh --staged
# => "秘匿情報は検出されませんでした。" が表示されること
```

### 4. ユーザー確認

- マスク置換の内容をユーザーに提示し、承認を得てから commit します
- 意図的に含めている情報（公開済みの情報等）がある場合はユーザーの判断に従います

## 注意事項

- リポジトリパス（`git rev-parse --show-toplevel` で得られるパス）自体への参照は許容されます
- カーネルソースコードの引用に含まれるパターン（例: 構造体のフィールド名 `password`）は文脈で判断します
- `@example.com` 等のダミーアドレスは検出対象外です
