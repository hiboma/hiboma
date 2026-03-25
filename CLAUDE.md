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
