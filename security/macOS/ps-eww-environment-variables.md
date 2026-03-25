# macOS で `ps eww` による環境変数の露出を抑制する方法

> This report was generated with [Claude Code](https://claude.ai/code) (Claude Opus 4.6)

## 概要

macOS では `ps eww` コマンドにより、同一ユーザーや root がプロセスの環境変数を閲覧できます。環境変数にシークレット（API キー、データベースパスワードなど）を格納している場合、意図しない情報漏洩のリスクがあります。

本レポートでは、この問題の技術的背景と緩和策をまとめます。

## 技術的背景

### macOS における `ps` の実装

- macOS の `ps` は `/proc` ファイルシステムではなく、`sysctl` の `kern.procargs2` 経由でプロセス情報を取得します
- Linux の `/proc/<pid>/environ` のようにファイルパーミッションで制御する仕組みが macOS には存在しません
- root および同一ユーザーのプロセスの環境変数が閲覧可能です

### 結論

macOS には、一般ユーザーが他ユーザーのプロセスの環境変数を `ps eww` で閲覧することを完全に防ぐカーネルレベルの仕組みはありません。緩和策を組み合わせて対応する必要があります。

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

起動直後の短い時間帯には `ps eww` で閲覧可能なため、レースコンディションが残ります。完全な対策ではありません。

### 3. `security.bsd.see_other_uids` で他ユーザーのプロセスを非表示にする

```bash
sudo sysctl security.bsd.see_other_uids=0
```

一般ユーザーが **他ユーザー** のプロセス情報を閲覧できなくなります。ただし、**同一ユーザー** のプロセスや **root** からは引き続き閲覧可能です。

### 4. Endpoint Security フレームワーク

macOS の Endpoint Security フレームワークを使い `proc_info` 系のシステムコールを監視・制限することは理論上可能ですが、MDM 配布の System Extension として実装する必要があり、一般的な対策とは言えません。

## Keychain Services API

macOS Keychain は `ps eww` 対策として有効な手段です。以下に API の詳細を記載します。

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
