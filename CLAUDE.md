# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## リポジトリの概要

Linux カーネル、システムプログラミング、インフラ技術に関する技術ノート・知識ベースです。ビルド対象のコードプロジェクトではなく、マークダウン文書の集合体です。

著者は GMO ペパボの Senior Principal Engineer で、トラブルシューティング、カーネルソースコードリーディング、CVE の PoC 検証、セキュリティ対策などを専門としています。

## 構造

- `kernel/` — Linux カーネル関連（サブディレクトリ: mm, net, fs, proc, block, ftrace, kvm, perf, sys）
- `tcp/` — TCP/IP スタックの詳細な技術ノート
- `auditd/` — Linux audit サブシステムの調査
- `books/` — 技術書の読書・学習記録
- `mysql/`, `httpd/`, `ruby/`, `jruby/` — ミドルウェア関連の調査
- `Linuxカーネル解読室/`, `CodeReading/`, `Linux_Kernel_Architecture/` — ソースコードリーディング記録
- `slides/` — 発表スライドの原稿
- `security/` — セキュリティ関連の調査
- ルート直下の `.md` ファイル — 個別のトピックごとの技術ノート

## 文書の特徴

- 日本語で記述されています
- カーネルソースコードの引用と解説が多く含まれます
- 実験手順と観察結果がセットで記録されています
- CVE の PoC 検証やバグレポートの記録も含まれます

## 秘匿情報スキャン

コマンド実行の履歴や出力をマークダウンに記録する際、秘匿情報や個人を特定できるディレクトリパスの漏洩を防止する仕組みがあります。

### 構成

| ファイル | 役割 |
|---|---|
| `scripts/scan-sensitive-data.sh` | 共通スキャンスクリプト。差分・ファイルから秘匿情報を検出します |
| `.claude/rules/sensitive-data-check.md` | Claude Code のルール。commit 前のスキャン実行を指示します |
| `.claude/skills/sensitive-data-guard.md` | Claude Code のスキル。マスク対象パターンとマスク手順を定義します |
| `.githooks/pre-commit` | git pre-commit hook。手動 commit でもスキャンを実行します |

### git hooks の有効化

```bash
git config core.hooksPath .githooks
```

### 手動スキャン

```bash
# ステージ済みの差分をスキャン
scripts/scan-sensitive-data.sh --staged

# 特定ファイルをスキャン
scripts/scan-sensitive-data.sh --file <path>
```
