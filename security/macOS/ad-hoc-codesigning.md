# macOS Ad Hoc 署名 (linker-signed)

macOS のバイナリに付与されるコード署名の方式のうち、最も簡易な「ad hoc 署名」と、リンカが自動付与する「linker-signed」について整理します。

## コード署名の方式

macOS のコード署名は大きく 3 つの方式があります。

| 方式 | 説明 |
|---|---|
| Developer ID 署名 | Apple Developer Program の証明書で署名します。Notarization や App Store 配布に必要です |
| Ad hoc 署名 | 開発者の identity を使わず、バイナリのハッシュだけで署名します |
| Linker-signed | ld リンカがリンク時に自動付与する ad hoc 署名です |

## Ad hoc 署名

- 証明書や Apple Developer アカウントが不要です
- `codesign -s - <binary>` で手動付与できます
- バイナリの内容からハッシュを計算し、そのハッシュ自体が署名になります
- ローカル実行専用です。他のマシンでは Gatekeeper に拒否される場合があります

### 仕組み

通常のコード署名では、証明書の秘密鍵でハッシュに署名しますが、ad hoc 署名はハッシュの計算のみを行います。署名者の identity を証明する情報が含まれないため、「誰が署名したか」ではなく「バイナリが改竄されていないか」の検証のみが可能です。

## Linker-signed

### 背景: Apple Silicon の要件

Apple Silicon (arm64) の macOS では、署名なしバイナリは実行できません。カーネルがバイナリ実行時にコード署名を検証し、署名がなければ `SIGKILL` で強制終了します。

この制約により、開発者が明示的にコード署名を行わなくてもバイナリが実行できるように、Apple の `ld` リンカがリンク時に自動で ad hoc 署名を付与する仕組みが導入されました。

### man ld(1) の記述

`man ld` に以下の記載があります。

> **-adhoc_codesign**
> Directs the linker to add an ad-hoc codesignature to the output file. The default for Apple Silicon binaries is to be ad-hoc codesigned.
>
> **-no_adhoc_codesign**
> Directs the linker to not add ad-hoc codesignature to the output file, even for Apple Silicon binaries.

Apple Silicon バイナリではデフォルトで ad hoc 署名が付与されます。`-no_adhoc_codesign` で明示的に無効化できますが、その場合 Apple Silicon 上では実行できないバイナリが生成されます。

### man codesign(1) の記述

`man codesign` に linker-signed と adhoc の違いが記載されています。

> **linker-signed**
> Identifies a signature as signed by the linker. Linker signatures are very similar to adhoc signatures, except:
> - linker signatures can be replaced without using the `--force` option.
> - linker signatures are never preserved regardless of the use of the `--preserve-metadata` option.
> - linker signatures will usually not contain any embedded code requirements including a designated requirement.

linker-signed は ad hoc 署名とほぼ同じですが、以下の点が異なります。

| 観点 | ad hoc (`codesign -s -`) | linker-signed |
|---|---|---|
| 上書き時の `--force` | 必要 | 不要 |
| `--preserve-metadata` での保持 | 保持される | 保持されない |
| code requirements の埋め込み | 含まれる | 通常含まれない |

リンカが付与した署名は「仮の署名」として扱われるため、開発者が後から `codesign` で正式な署名を上書きしやすい設計になっています。

### 特徴

- `swift build` や `clang` でビルドするだけで、自動的に署名済みバイナリが生成されます
- 開発者が `codesign` コマンドを明示的に実行する必要はありません
- Intel Mac では署名なしバイナリも実行可能ですが、リンカは同様に ad hoc 署名を付与します

### 確認方法

```bash
# バイナリの署名情報を確認する
codesign -dv /path/to/binary 2>&1

# 出力例
# Executable=/path/to/binary
# Identifier=binary
# Format=Mach-O thin (arm64)
# ...
# Signature=adhoc
```

`Signature=adhoc` と表示されれば、ad hoc 署名 (linker-signed を含む) です。

### codesign -v による検証

```bash
# 署名の検証
codesign -v /path/to/binary

# ad hoc 署名のバイナリは valid と判定される
# バイナリを改竄すると invalid signature と判定される
```

## バイナリフォーマット

コード署名は Mach-O バイナリの末尾に埋め込まれます。Mach-O ヘッダのロードコマンド `LC_CODE_SIGNATURE` が署名データの位置とサイズを指します。

### Mach-O ロードコマンド: LC_CODE_SIGNATURE

```
      cmd LC_CODE_SIGNATURE
  cmdsize 16
  dataoff 16560        ← ファイル先頭からの署名データのオフセット
 datasize 280          ← 署名データのサイズ (バイト)
```

`otool -l <binary> | grep -A 5 LC_CODE_SIGNATURE` で確認できます。署名データはバイナリの末尾（`__LINKEDIT` セグメント内）に配置されます。

### SuperBlob 構造

`LC_CODE_SIGNATURE` が指す先には **SuperBlob** と呼ばれるコンテナ構造があります。SuperBlob は複数の Blob を束ねるヘッダです。

```
+---------------------------+
| SuperBlob Header          |  magic: 0xfade0cc0 (EmbeddedSignatureBlob)
|   length                  |  SuperBlob 全体のサイズ
|   count                   |  含まれる Blob の数
|   index[]                 |  各 Blob の type と offset
+---------------------------+
| Blob 1: CodeDirectory     |  magic: 0xfade0c02
+---------------------------+
| Blob 2: Requirements      |  magic: 0xfade0c01
+---------------------------+
| Blob 3: CMS Signature     |  magic: 0xfade0b01 (BlobWrapper)
+---------------------------+
```

主要な Blob のマジックナンバーは以下の通りです。

| マジックナンバー | 名前 | 説明 |
|---|---|---|
| `0xfade0cc0` | EmbeddedSignatureBlob | SuperBlob のヘッダです |
| `0xfade0c02` | CodeDirectory | コードのハッシュと署名メタデータを保持します |
| `0xfade0c01` | RequirementsBlob | code requirements（署名の検証条件）を保持します |
| `0xfade0b01` | BlobWrapper | CMS (PKCS#7) 署名データを保持します |

### CodeDirectory

CodeDirectory はコード署名の核となる構造で、以下の情報を含みます。

```
CodeDirectory v=20400 size=259 flags=0x20002(adhoc,linker-signed) hashes=5+0 location=embedded
Hash type=sha256 size=32
Page size=4096
Identifier=test_adhoc
```

| フィールド | 説明 |
|---|---|
| `flags` | 署名のフラグです。`0x2` = adhoc、`0x20000` = linker-signed です |
| `hashes` | `N+M` の形式です。N はコードページのハッシュ数、M は special slot のハッシュ数です |
| `Hash type` | ハッシュアルゴリズムです。`sha256` が標準です |
| `Page size` | ハッシュの計算単位です。4096 バイト（1 ページ）ごとにハッシュを計算します |
| `Identifier` | バイナリの識別子です。linker-signed の場合はファイル名が使われます |

コードのページごとにハッシュが計算され、CodeDirectory に格納されます。検証時はページ単位でハッシュを再計算し、CodeDirectory の値と比較します。

### Ad hoc 署名と通常署名のフォーマットの違い

| 構成要素 | 通常署名 (Developer ID) | Ad hoc / Linker-signed |
|---|---|---|
| SuperBlob | あります | あります |
| CodeDirectory | あります | あります |
| Requirements | あります | ad hoc: あります / linker-signed: 通常ありません |
| CMS Signature (BlobWrapper) | あります（証明書チェーンを含みます） | **ありません** |
| CodeDirectory の flags | `0x0` (none) | `0x2` (adhoc) または `0x20002` (adhoc,linker-signed) |

ad hoc 署名では CMS Signature Blob が省略されます。そのため署名データのサイズが大幅に小さくなります。上記の実バイナリでの比較では、Apple 署名の `/usr/bin/true` は 18,448 バイト、linker-signed のテストバイナリは 280 バイトでした。

### 確認コマンド

```bash
# LC_CODE_SIGNATURE ロードコマンドの確認
otool -l /path/to/binary | grep -A 5 LC_CODE_SIGNATURE

# 署名領域のバイナリダンプ（SuperBlob のマジックナンバー 0xfade0cc0 を確認する）
xxd -s <dataoff> -l <datasize> /path/to/binary

# CodeDirectory の flags を含む詳細情報
codesign -d --verbose=4 /path/to/binary 2>&1
```

## 配布時の注意

| 配布方法 | ad hoc 署名で可能か |
|---|---|
| ローカル開発・テスト | 可能 |
| 同一マシン上での実行 | 可能 |
| 他のマシンへの配布 | Gatekeeper に拒否される場合がある |
| App Store 配布 | 不可。Developer ID 署名 + Notarization が必要 |
| MDM 経由の配布 | 構成プロファイルで許可すれば可能 |

## 関連する macOS のセキュリティ機構

- **Gatekeeper**: ダウンロードしたアプリの署名と Notarization を検証します
- **XProtect**: マルウェアのシグネチャベースの検出を行います
- **Sandbox.kext**: App Sandbox のカーネル側実装です。署名情報をもとにサンドボックスルールを適用します
- **amfid (Apple Mobile File Integrity Daemon)**: コード署名の検証をカーネルから委譲されるデーモンです
