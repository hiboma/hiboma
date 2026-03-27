# macOS App Sandbox コンテナ (`~/Library/Containers/`)

App Sandbox 対応アプリは、macOS が `~/Library/Containers/<bundle-id>/` にコンテナを自動作成し、アプリのデータを隔離します。

## containermanagerd デーモン

macOS 11 (Big Sur) で導入されたデーモンで、コンテナのライフサイクルを管理します。

| コンポーネント | パス |
|---|---|
| ユーザ空間デーモン | `/usr/libexec/containermanagerd` |
| システムレベルデーモン | `/usr/libexec/containermanagerd_system` |
| 実装フレームワーク | `/System/Library/PrivateFrameworks/ContainerManagerCommon.framework` |

### 通信アーキテクチャ

- ユーザランドクライアント（`AppSandbox.framework` など）とは **XPC** で通信します
- カーネル（`Sandbox.kext`）とは **Mach ポート** で通信します
- `secinitd` がアプリ起動時に `containermanagerd` へコンテナ作成を要求し、完了後 `Sandbox.kext` へ MACL 属性の適用を要求します

### デーモンのエンタイトルメント

```
com.apple.private.security.appcontainer-authority   = true
com.apple.private.security.storage.containers       = true
com.apple.rootless.datavault.metadata               = true   ← メタデータ plist への排他的アクセス権
com.apple.private.MobileContainerManager.proxy      = true
com.apple.private.MobileContainerManager.repair     = true
```

## `.com.apple.containermanagerd.metadata.plist` の構造

各コンテナディレクトリ直下に配置される隠しファイルで、コンテナの制限事項と許可されたシンボリックリンクのリストを定義します。

### 主要キー

| キー | 内容 |
|---|---|
| `SandboxProfileData` | コンパイル済みサンドボックスプロファイル（バイナリ） |
| `SandboxProfileDataValidationInfo` | バリデーション用メタデータ |
| `MCMMetadataIdentifier` | Team Identifier への参照 |

### `SandboxProfileDataValidationInfo` のサブキー

| サブキー | 内容 |
|---|---|
| `RedirectablePaths` | アプリがアクセス可能なパスのリスト |
| `RedirectedPaths` | 実際にリダイレクトされているパス |
| `Parameters` | ランタイム変数（`_HOME`, `_UID`, `_USER` など） |
| `Entitlements` | キャッシュされたアプリケーションエンタイトルメント |

閲覧には Full Disk Access が必要です。パーミッションは `-rw-r--r--` ですが、TCC レベルで保護されています。

```bash
# 閲覧方法（Full Disk Access が必要）
plutil -convert xml1 .com.apple.containermanagerd.metadata.plist -o -
```

## 多層的な保護の仕組み

コンテナは単一のメカニズムではなく、複数のレイヤで保護されています。

1. **TCC (AppData 保護)** — macOS Sonoma (14) 以降、OS がアプリのコード署名をコンテナに関連付けます。異なるアプリからのアクセスにはユーザ確認が必要です
2. **MACL (Mandatory Access Control List)** — `com.apple.macl` 拡張属性がアクセス許可されたアプリの UUID をホワイトリストとして保持します。SIP と同じメカニズムで保護されます
3. **Sandbox Profile** — `SandboxProfileData` に含まれるコンパイル済みプロファイルが、カーネルレベルでアクセス制御を実施します
4. **macOS Sequoia (15) の強化** — Group Containers にも SIP ベースの保護が拡張されています

## コンテナディレクトリの内部構造

```
~/Library/Containers/com.example.app/
├── .com.apple.containermanagerd.metadata.plist   ← TCC で保護
└── Data/                                         ← 仮想ホームディレクトリ
    ├── .CFUserTextEncoding → ../../../../.CFUserTextEncoding   (symlink)
    ├── Desktop             → ../../../../Desktop              (symlink)
    ├── Downloads           → ../../../../Downloads            (symlink)
    ├── Movies, Music, Pictures                                (symlink)
    ├── Documents/          ← 実ディレクトリ
    ├── SystemData/         ← 実ディレクトリ
    ├── tmp/                ← 実ディレクトリ
    └── Library/
        ├── Application Support/   ← アプリ固有データ
        ├── Caches/
        ├── Logs/
        ├── Preferences/
        │   ├── com.apple.security_common.plist → symlink
        │   └── com.apple.security.plist        → symlink
        ├── Saved Application State/
        ├── Audio       → ../../../../Audio       (symlink)
        ├── Calendars   → ../../../../Calendars   (symlink)
        └── (その他多数の symlink ...)
```

`Data/` はサンドボックス化されたアプリから見た仮想ホームディレクトリです。多くのサブディレクトリは `../../../../` 形式の相対シンボリックリンクで実際のホームに向いており、`RedirectablePaths` で管理されています。

## Sandbox Entitlements との関係

`com.apple.security.app-sandbox` エンタイトルメントが `true` のアプリを初回起動すると、コンテナが自動作成されます。

| エンタイトルメント | 役割 |
|---|---|
| `com.apple.security.app-sandbox` | コンテナ作成のトリガ |
| `com.apple.security.files.user-selected.read-write` | ユーザ選択ファイルへのアクセス |
| `com.apple.security.application-groups` | App Group コンテナの共有 |
| `com.apple.security.temporary-exception.sbpl` | カスタムサンドボックスプロファイル |

`container-migration.plist` をアプリバンドルの `Resources/` に配置すると、非サンドボックス版からの移行時にファイルをコンテナへ移動できます。

## App Groups (`~/Library/Group Containers/`) との違い

| 項目 | Containers | Group Containers |
|---|---|---|
| パス | `~/Library/Containers/{BundleID}/` | `~/Library/Group Containers/{TeamID}.{GroupName}/` |
| 所有者 | 1 つのアプリが排他的に使用 | 同一開発者の複数アプリが共有 |
| 内部構造 | `Data/` + メタデータ（ホームのミラー） | `Library/` + メタデータのみ |
| シンボリックリンク | 実ホームへの多数の symlink を含む | symlink なし |
| エンタイトルメント | `com.apple.security.app-sandbox` | `com.apple.security.application-groups` |
| SIP 保護導入 | macOS Sonoma (14) | macOS Sequoia (15) |

**Daemon Containers** (`~/Library/Daemon Containers/`) という第三の種類も存在し、UUID で命名されます。

## コンテナの作成・削除ライフサイクル

### 作成プロセス

1. サンドボックス化アプリが初回起動されます
2. `secinitd` → `containermanagerd` にコンテナ作成を要求します
3. **ステージングディレクトリ** (`~/Library/ContainerManager/Staging`) に構築します
4. 構築完了後、`~/Library/Containers/{BundleID}/` にリネームで移動します
5. `secinitd` → `Sandbox.kext` に MACL 属性を適用します

### 削除について

- アプリのアンインストール時にコンテナは**自動削除されません**（macOS の既知の仕様）
- `.com.apple.containermanagerd.metadata.plist` は TCC で保護されるため、Full Disk Access が必要な場合があります
- 正しい削除手順: アプリ本体を削除 → 再起動 → `rm -rf` でコンテナを削除します

### セキュリティ上の注意

コンテナ作成と MACL 適用の間にタイミングウィンドウが存在し、symlink 置換によるレースコンディション攻撃が過去に報告されています（パッチ済み）。

## xattr で確認できる保護属性

```bash
$ xattr -l ~/Library/Containers/com.1password.1password/
com.apple.containermanager.identifier: com.1password.1password
com.apple.containermanager.schema-version: 0
com.apple.containermanager.uuid: 8B13E17B-D34B-4305-9267-0006D83D65D3
```

| 拡張属性 | 内容 |
|---|---|
| `com.apple.containermanager.identifier` | コンテナの識別子（BundleID） |
| `com.apple.containermanager.schema-version` | メタデータスキーマバージョン |
| `com.apple.containermanager.uuid` | コンテナの UUID |
| `com.apple.macl` | MACL。許可されたアプリの UUID リスト |
| `com.apple.provenance` | ファイルの出自を記録するバイナリデータ |

containermanagerd バイナリ自体は `restricted,compressed` フラグで SIP 保護されています。

```bash
$ ls -lO /usr/libexec/containermanagerd
-rwxr-xr-x  root  wheel  restricted,compressed  /usr/libexec/containermanagerd
```

## 参考資料

- [What are all those Containers? - The Eclectic Light Company](https://eclecticlight.co/2024/08/05/what-are-all-those-containers/)
- [Snake&Apple VIII - App Sandbox (Karol Mazurek)](https://karol-mazurek.medium.com/snake-apple-viii-app-sandbox-5aff081f07d5)
- [containermanagerd(8) man page](https://keith.github.io/xcode-man-pages/containermanagerd.8.html)
- [macOS Sandbox - HackTricks](https://hacktricks.wiki/en/macos-hardening/macos-security-and-privilege-escalation/macos-security-protections/macos-sandbox/index.html)
- [Quarantine, SIP, and MACL - The Eclectic Light Company](https://eclecticlight.co/2020/01/30/quarantine-sip-and-macl-macos-per-file-security-controls/)
- [Unveiling Mac Security: Sandboxing and AppData TCC](https://imlzq.com/apple/macos/2024/08/24/Unveiling-Mac-Security-A-Comprehensive-Exploration-of-TCC-Sandboxing-and-App-Data-TCC.html)
- [A New Era of macOS Sandbox Escapes](https://jhftss.github.io/A-New-Era-of-macOS-Sandbox-Escapes/)
