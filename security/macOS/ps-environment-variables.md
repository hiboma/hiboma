# macOS で `ps` コマンドによる環境変数の露出を抑制する方法

> This report was generated with [Claude Code](https://claude.ai/code) (Claude Opus 4.6)

## 概要

macOS では `ps` コマンドにより、同一ユーザーや root がプロセスの環境変数を閲覧できます。環境変数にシークレット（API キー、データベースパスワードなど）を格納している場合、意図しない情報漏洩のリスクがあります。

本レポートでは、この問題の技術的背景と緩和策をまとめます。

## `ps` で環境変数を表示するオプション

macOS の `ps` で環境変数を表示する方法を整理します。

### `-E` オプション（推奨）

```bash
ps -E -ww -p $$
```

man ps(1) より:

> **-E** Display the environment as well. This does not reflect changes in the environment after process launch.

`-E` が環境変数を表示するための正式なオプションです。プロセス起動時の環境変数が表示されます。起動後に `unsetenv()` 等で変更しても、`ps -E` の出力には反映されません。

### `-e` オプション（レガシーモードとの差異に注意）

`-e` の挙動は macOS のモードによって異なります。

| モード | `-e` の意味 |
|---|---|
| 現行（POSIX 準拠） | `-A` と同一。全プロセスを表示します。環境変数は表示しません |
| レガシーモード | `-E` と同一。環境変数を表示します |

レガシーモードは `compat(5)` で制御されます。混乱を避けるため、環境変数の表示には明示的に `-E` を使用します。

### `-w` オプション（出力幅の制御）

```bash
ps -E -w      # 132 カラム幅で表示
ps -E -ww     # カラム幅の制限なし（環境変数を全て表示する場合に必要）
```

`-w` を1回指定すると132カラム、2回指定（`-ww`）するとカラム幅の制限がなくなります。環境変数は長いため、`-ww` との組み合わせが実用的です。

### Linux の `ps -E` との違い

Linux（procps-ng）の `ps` は BSD スタイルのオプション `e` で環境変数を表示します。

```bash
# Linux
ps eww -p $$     # BSD スタイル: e = 環境変数表示, ww = 幅無制限

# macOS
ps -E -ww -p $$  # -E = 環境変数表示, -ww = 幅無制限
```

macOS で `ps -E` と入力した場合、BSD スタイルのオプション解釈により環境変数が表示されるケースがありますが、macOS の man ps(1) に記載された正式な方法は `-E` です。

## 技術的背景

### macOS における `ps` の実装

- macOS の `ps` は `/proc` ファイルシステムではなく、`sysctl` の `KERN_PROCARGS2` 経由でプロセス情報を取得します
- Linux の `/proc/<pid>/environ` のようにファイルパーミッションで制御する仕組みが macOS には存在しません
- root および同一ユーザーのプロセスの環境変数が閲覧可能です

`ps` コマンドのソースコード（`adv_cmds/ps/print.c` の `getproclline()` 関数）は、`sysctl()` を `{ CTL_KERN, KERN_PROCARGS2, pid }` で呼び出してプロセスの引数と環境変数を取得しています。

- ps コマンドのソース: https://github.com/apple-oss-distributions/adv_cmds/tree/main/ps

### SIP による環境変数の読み取り制限（CS_RESTRICT）

macOS 11 Big Sur 以降、SIP (System Integrity Protection) が有効な環境では、**`CS_RESTRICT` フラグが設定されたプロセスの環境変数はカーネルレベルで非表示になります**。

#### 観察: `ps eww` で環境変数が見えるプロセスと見えないプロセス

```bash
# /usr/bin/perl — SIP 保護パス配下。環境変数は表示されない
$ /usr/bin/perl -e 'sleep 1000' &
$ ps eww -p $!
  PID   TT  STAT      TIME COMMAND
12345 s014  S+     0:00.01 perl -e sleep 1000

# ~/.rbenv/ 配下の ruby — SIP 保護対象外。環境変数が全て表示される
$ ~/.rbenv/versions/3.4.8/bin/ruby -e 'sleep 100' &
$ ps eww -p $!
  PID   TT  STAT      TIME COMMAND
12346 s014  S+     0:00.04 /Users/hito/.rbenv/versions/3.4.8/bin/ruby -e sleep 100 TERM=xterm-256color HOME=/Users/hito ...
```

| バイナリのパス | 環境変数の表示 | 理由 |
|---|---|---|
| `/usr/bin/perl` | 表示されない | SIP 保護パス配下のバイナリ。`CS_RESTRICT` フラグが設定されています |
| `~/.local/bin/claude` | 表示される | SIP 保護対象外のパスです |
| `~/.rbenv/versions/3.4.8/bin/ruby` | 表示される | SIP 保護対象外のパスです |

SIP の保護対象パス（`/usr/bin/`, `/bin/`, `/usr/sbin/`, `/sbin/`）にある Apple 署名済みバイナリには `CS_RESTRICT` フラグが設定されています。

#### XNU カーネルソースにおける実装

環境変数の読み取り制限は、XNU カーネルの `bsd/kern/kern_sysctl.c` にある `sysctl_procargsx()` 関数で実装されています。

```c
// bsd/kern/kern_sysctl.c — sysctl_procargsx()

#define SYSCTL_PROCARGS_READ_ENVVARS_ENTITLEMENT \
    "com.apple.private.read-environment-variables"

bool omit_env_vars = true;

#if DEVELOPMENT || DEBUG
    omit_env_vars = false;
#endif

if (p == current_proc() ||
    !cs_restricted(p) ||
#if CONFIG_CSR
    csr_check(CSR_ALLOW_UNRESTRICTED_DTRACE) == 0 ||
#endif
    IOCurrentTaskHasEntitlement(SYSCTL_PROCARGS_READ_ENVVARS_ENTITLEMENT))
{
    omit_env_vars = false;
}
```

環境変数が**表示される**（`omit_env_vars = false`）条件は以下のいずれかを満たす場合です:

1. DEVELOPMENT または DEBUG ビルドのカーネルである
2. 呼び出し元が対象プロセス自身である（`p == current_proc()`）
3. 対象プロセスに `CS_RESTRICT` フラグが設定されていない（`!cs_restricted(p)`）
4. SIP の `CSR_ALLOW_UNRESTRICTED_DTRACE` が許可されている
5. 呼び出し元が `com.apple.private.read-environment-variables` エンタイトルメントを持つ

逆に言えば、リリース版カーネル上で、SIP が有効かつ `CS_RESTRICT` フラグが付いたプロセスの環境変数を、別プロセスから `KERN_PROCARGS2` 経由で取得することはできません。

#### 関連するソースコードと定数

| ファイル | 関数・定数 | 役割 |
|---|---|---|
| `bsd/kern/kern_sysctl.c` | `sysctl_procargsx()` | 環境変数フィルタリングの本体です |
| `bsd/kern/kern_sysctl.c` | `sysctl_doprocargs2()` | `KERN_PROCARGS2` のハンドラです |
| `bsd/kern/kern_cs.c` | `cs_restricted()` | `CS_RESTRICT` フラグの確認を行います |
| `osfmk/kern/cs_blobs.h` | `CS_RESTRICT = 0x00000800` | フラグの定数定義です |
| `bsd/sys/csr.h` | `CSR_ALLOW_UNRESTRICTED_DTRACE` | SIP のフラグ定義です |

XNU ソース: https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_sysctl.c

#### 導入時期

xnu-3247（El Capitan 10.11）の `sysctl_procargsx()` には `omit_env_vars` ロジックが存在しません。xnu-7195（macOS 11 Big Sur）で導入されたと推定されます。

### 結論

macOS には `CS_RESTRICT` フラグと SIP による環境変数の読み取り制限がカーネルレベルで実装されています。ただし、この保護は `/usr/bin/` 等の SIP 保護パス配下にある Apple 署名済みバイナリに限定されます。サードパーティのバイナリやユーザーがインストールしたバイナリには `CS_RESTRICT` フラグが設定されないため、`ps -E` で閲覧することを防ぐことはできません。緩和策を組み合わせて対応する必要があります。

## 緩和策

### 1. 環境変数にシークレットを渡さない（推奨）

最も確実な方法です。代替手段を以下に示します。

#### ファイル経由で渡す

シークレットをファイルに書き、`chmod 600` で保護し、アプリケーション側でファイルから読み取ります。

```bash
echo "secret-value" > /path/to/secret
chmod 600 /path/to/secret
my-app --password-file=/path/to/secret
```

#### stdin 経由で渡す

パイプや heredoc でプロセスの標準入力にシークレットを渡します。

```bash
echo "secret-value" | my-app --password-stdin
```

#### macOS Keychain を利用する

`security` コマンドや Keychain Services API を使います。

```bash
# 追加
security add-generic-password -s "my-app" -a "api-key" -w "secret-value" login.keychain-db

# 取得（-w でパスワード文字列のみ出力）
DB_PASSWORD=$(security find-generic-password -s "my-app" -a "api-key" -w)

# ファイルディスクリプタ経由で渡す（ps に露出しない）
exec 3<<< "$DB_PASSWORD"
my-app --password-fd=3
```

#### シークレットマネージャを利用する

1Password CLI、HashiCorp Vault などのシークレットマネージャから実行時に取得します。

### 1Password CLI `op run` の注意点

`op run --env-file=.env` は `.env` ファイル中のシークレット参照（`op://vault/item/field`）を 1Password から解決し、子プロセスの環境変数として渡します。

```bash
# .env の内容
# DB_PASSWORD=op://Private/database/password

op run --env-file=.env -- my-app
```

`op run` が提供する価値は「`.env` ファイルにシークレットの平文を保存しない」ことです。しかし、**子プロセスの環境変数としてシークレットが渡される仕組みは変わらないため、`ps -E -ww` による露出リスクは残ります**。

```bash
# 別のターミナルから確認すると、解決済みのシークレットが見える
ps -E -ww -p <子プロセスのPID>
```

`op run` 自体のプロセスにはシークレットがコマンドライン引数に現れないため、`ps` の引数欄（`COMMAND` 列）には露出しません。露出するのは子プロセスの環境変数です。

`op run` を使う場合でも、アプリケーション側で起動直後に `unsetenv()` するなどの追加対策を併用することが望ましいです。

### 2. プロセス起動後に環境変数を消す

アプリケーション側で起動直後に環境変数を読み取り、メモリ上に保持した後 `unsetenv()` で削除します。

```c
#include <stdlib.h>
#include <string.h>

char *secret = strdup(getenv("SECRET_KEY"));
unsetenv("SECRET_KEY");

// 以降は secret 変数を使う
// 使い終わったら明示的に消去する
memset(secret, 0, strlen(secret));
free(secret);
```

起動直後の短い時間帯には `ps -E` で閲覧可能なため、レースコンディションが残ります。完全な対策ではありません。

### 3. `security.bsd.see_other_uids` で他ユーザーのプロセスを非表示にする

```bash
sudo sysctl security.bsd.see_other_uids=0
```

一般ユーザーが **他ユーザー** のプロセス情報を閲覧できなくなります。ただし、**同一ユーザー** のプロセスや **root** からは引き続き閲覧可能です。

### 4. Endpoint Security フレームワーク

macOS の Endpoint Security フレームワークを使い `proc_info` 系のシステムコールを監視・制限することは理論上可能ですが、MDM 配布の System Extension として実装する必要があり、一般的な対策とは言えません。

## Keychain Services API

macOS Keychain は `ps -E` 対策として有効な手段です。以下に API の詳細を記載します。

### アイテムの種類

| クラス | 定数 | 用途 |
|---|---|---|
| Generic Password | `kSecClassGenericPassword` | 任意のシークレット（API キー、トークンなど） |
| Internet Password | `kSecClassInternetPassword` | URL に紐づく認証情報 |
| Certificate | `kSecClassCertificate` | X.509 証明書 |
| Key | `kSecClassKey` | 暗号鍵 |
| Identity | `kSecClassIdentity` | 証明書 + 秘密鍵のペア |

### C API（Security.framework）による CRUD 操作

#### アイテムの追加

```c
#include <Security/Security.h>

OSStatus add_secret(const char *service, const char *account, const char *secret) {
    CFMutableDictionaryRef query = CFDictionaryCreateMutable(
        NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecAttrService,
        CFStringCreateWithCString(NULL, service, kCFStringEncodingUTF8));
    CFDictionarySetValue(query, kSecAttrAccount,
        CFStringCreateWithCString(NULL, account, kCFStringEncodingUTF8));
    CFDictionarySetValue(query, kSecValueData,
        CFDataCreate(NULL, (const UInt8 *)secret, strlen(secret)));
    CFDictionarySetValue(query, kSecAttrAccessible,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly);

    OSStatus status = SecItemAdd(query, NULL);
    CFRelease(query);
    return status;
}
```

#### アイテムの取得

```c
OSStatus get_secret(const char *service, const char *account,
                    char *buf, size_t buf_len) {
    CFMutableDictionaryRef query = CFDictionaryCreateMutable(
        NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecAttrService,
        CFStringCreateWithCString(NULL, service, kCFStringEncodingUTF8));
    CFDictionarySetValue(query, kSecAttrAccount,
        CFStringCreateWithCString(NULL, account, kCFStringEncodingUTF8));
    CFDictionarySetValue(query, kSecReturnData, kCFBooleanTrue);
    CFDictionarySetValue(query, kSecMatchLimit, kSecMatchLimitOne);

    CFDataRef result = NULL;
    OSStatus status = SecItemCopyMatching(query, (CFTypeRef *)&result);

    if (status == errSecSuccess && result != NULL) {
        CFIndex len = CFDataGetLength(result);
        if ((size_t)len < buf_len) {
            memcpy(buf, CFDataGetBytePtr(result), len);
            buf[len] = '\0';
        }
        CFRelease(result);
    }

    CFRelease(query);
    return status;
}
```

#### アイテムの更新

```c
OSStatus update_secret(const char *service, const char *account,
                       const char *new_secret) {
    CFMutableDictionaryRef query = CFDictionaryCreateMutable(
        NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecAttrService,
        CFStringCreateWithCString(NULL, service, kCFStringEncodingUTF8));
    CFDictionarySetValue(query, kSecAttrAccount,
        CFStringCreateWithCString(NULL, account, kCFStringEncodingUTF8));

    CFMutableDictionaryRef attrs = CFDictionaryCreateMutable(
        NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(attrs, kSecValueData,
        CFDataCreate(NULL, (const UInt8 *)new_secret, strlen(new_secret)));

    OSStatus status = SecItemUpdate(query, attrs);
    CFRelease(query);
    CFRelease(attrs);
    return status;
}
```

#### アイテムの削除

```c
OSStatus delete_secret(const char *service, const char *account) {
    CFMutableDictionaryRef query = CFDictionaryCreateMutable(
        NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecAttrService,
        CFStringCreateWithCString(NULL, service, kCFStringEncodingUTF8));
    CFDictionarySetValue(query, kSecAttrAccount,
        CFStringCreateWithCString(NULL, account, kCFStringEncodingUTF8));

    OSStatus status = SecItemDelete(query);
    CFRelease(query);
    return status;
}
```

### Swift API

```swift
import Security
import Foundation

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
    case itemNotFound
    case decodingFailed
}

struct KeychainHelper {
    static func save(service: String, account: String, data: Data) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func load(service: String, account: String) throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { throw KeychainError.itemNotFound }
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data else { throw KeychainError.decodingFailed }
        return data
    }

    static func delete(service: String, account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
```

### `security` コマンドによる操作

```bash
# 追加
security add-generic-password \
    -s "my-app" \
    -a "api-key" \
    -w "secret-value-here" \
    -T "" \
    login.keychain-db

# 取得（-w でパスワード文字列のみ出力）
security find-generic-password \
    -s "my-app" \
    -a "api-key" \
    -w

# 削除
security delete-generic-password \
    -s "my-app" \
    -a "api-key"
```

### アクセス制御（kSecAttrAccessible）

| 定数 | 意味 |
|---|---|
| `kSecAttrAccessibleWhenUnlocked` | デバイスがアンロック中のみアクセス可能。バックアップに含まれます |
| `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | 同上。バックアップに含まれません |
| `kSecAttrAccessibleAfterFirstUnlock` | 再起動後最初のアンロック以降アクセス可能。バックグラウンド処理向けです |
| `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | 同上。バックアップに含まれません |

### キーチェーンの種類

| キーチェーン | パス | 用途 |
|---|---|---|
| login | `~/Library/Keychains/login.keychain-db` | ユーザーごとのデフォルト。ログイン時に自動アンロックされます |
| System | `/Library/Keychains/System.keychain` | システム全体で共有。root 権限が必要です |
| カスタム | 任意のパス | `SecKeychainCreate` で独自に作成できます |

### 主要なエラーコード

| 定数 | 値 | 意味 |
|---|---|---|
| `errSecSuccess` | 0 | 成功 |
| `errSecItemNotFound` | -25300 | アイテムが存在しません |
| `errSecDuplicateItem` | -25299 | 同じアイテムが既に存在します |
| `errSecAuthFailed` | -25293 | 認証失敗（キーチェーンがロック中など） |
| `errSecInteractionNotAllowed` | -25308 | ユーザー操作が必要だが許可されていません |

## 緩和策のまとめ

| 方法 | 効果 | 実装コスト |
|---|---|---|
| シークレットをファイル経由で渡す | 高 | 低 |
| stdin 経由で渡す | 高 | 低 |
| Keychain / シークレットマネージャ | 高 | 中 |
| 起動後に `unsetenv()` | 中（レースあり） | 低 |
| `security.bsd.see_other_uids=0` | 限定的 | 低 |

## 参考リソース

### XNU カーネルソース

- [kern_sysctl.c — sysctl_procargsx()](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_sysctl.c) — 環境変数フィルタリングの実装箇所です
- [kern_cs.c — cs_restricted()](https://github.com/apple/darwin-xnu/blob/main/bsd/kern/kern_cs.c) — `CS_RESTRICT` フラグの判定を行います
- [adv_cmds/ps](https://github.com/apple-oss-distributions/adv_cmds/tree/main/ps) — macOS の `ps` コマンドのソースコードです

### Apple 公式ドキュメント

- [About System Integrity Protection](https://support.apple.com/en-us/102149)

### 技術記事

- [macOS's System Integrity Protection sanitizes your environment](https://briandfoy.github.io/macos-s-system-integrity-protection-sanitizes-your-environment/) — SIP が環境変数に与える影響の解説です
- [System Integrity Protection: The misunderstood setting](https://khronokernel.com/macos/2022/12/09/SIP.html) — SIP の各フラグの詳細な解説です
- [DYLD_INSERT_LIBRARIES injection in macOS — CS_RESTRICT の解説](https://theevilbit.github.io/posts/dyld_insert_libraries_dylib_injection_in_macos_osx_deep_dive/) — `CS_RESTRICT` フラグと DYLD の制限について解説しています
- [Endangered Technique: Using Environment Variables to Find Escaped Processes](https://medium.com/@captaindomestic/endangered-technique-using-environment-variables-to-find-escaped-processes-64eb7ff70602) — `KERN_PROCARGS2` の環境変数制限がセキュリティツールに与える影響を解説しています

### 関連する Issue / バグレポート

- [Emacs bug#48548](https://lists.gnu.org/archive/html/bug-gnu-emacs/2021-05/msg01652.html) — macOS でプロセス属性が取得できない問題の報告です
- [psutil #2189](https://github.com/giampaolo/psutil/issues/2189) — macOS での `cmdline()` が `NoSuchProcess` を返す問題です
- [Go #60047](https://github.com/golang/go/issues/60047) — `KERN_PROCARGS2` sysctl のバグ回避に関する議論です
