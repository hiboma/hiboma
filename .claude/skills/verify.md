---
name: verify
description: スクリプトやコードをコンパイル・実行して技術的な検証を行う
user_invocable: true
---

# 検証スキル

技術ノートに関連するコード・スクリプトを実行して検証します。

## 方針

`.claude/rules/verification-policy.md` に従います。

## 手順

### 1. 検証対象の把握

- ユーザーの指示または対象ドキュメントから、何を検証するかを特定します
- 検証に必要な言語・ツール・カーネルバージョンなどの前提条件を整理します

### 2. 検証環境の選択

#### Linux 環境の場合 → Docker コンテナ

```bash
# 例: C プログラムの検証
docker run --rm -v "$(pwd)/tmp:/work" -w /work gcc:latest bash -c "gcc -o test test.c && ./test"

# 例: 特定のディストリビューションでの検証
docker run --rm -v "$(pwd)/tmp:/work" -w /work ubuntu:22.04 bash -c "apt-get update && apt-get install -y <pkg> && ..."
```

- 検証内容に適した Docker イメージを選択します
- カーネル機能の検証で特権が必要な場合は `--privileged` や `--cap-add` を使用します
- ネットワーク検証が必要な場合は適切なネットワーク設定を行います

#### macOS 固有の場合 → ホストで直接実行

```bash
# プロジェクト配下の tmp/ を作業ディレクトリとして使用
cd tmp/
# 検証コードの作成と実行
```

- macOS 固有の API やシステムコールの検証に限定します
- 一時ファイルは `tmp/` 配下に配置します

### 3. 検証コードの作成

- `tmp/` 配下に検証用のソースコードやスクリプトを配置します
- ファイル名は検証内容がわかる名前にします（例: `verify-epoll-edge-trigger.c`）

### 4. 実行と結果の記録

- 実行結果をユーザーに提示します
- 検証が成功した場合、必要に応じて対象ドキュメントに結果を反映します

### 5. 後片付け

- Docker コンテナは `--rm` で自動削除します
- `tmp/` 配下の一時ファイルはユーザーの指示がない限り残しておきます
