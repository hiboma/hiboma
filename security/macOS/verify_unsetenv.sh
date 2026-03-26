#!/bin/bash
#
# unsetenv() が ps -E の出力に影響するかを検証するスクリプト
#
# 検証方法:
#   1. 環境変数 TEST_SECRET を設定して子プロセスを起動する
#   2. 子プロセスは起動直後に unsetenv("TEST_SECRET") を実行し sleep する
#   3. 親プロセスから ps -E -ww で子プロセスの環境変数を確認する
#
# 期待結果:
#   - getenv() は unsetenv() 後に (null) を返す
#   - ps -E -ww には unsetenv() 後も TEST_SECRET が表示される
#   - KERN_PROCARGS2 は exec 時のスナップショットであり、ユーザ空間の
#     unsetenv() では変更できないことを確認する
#

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# C プログラムをコンパイル
cat > "$WORKDIR/test_unsetenv.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(void) {
    const char *env_name = "TEST_SECRET";
    const char *val = getenv(env_name);

    if (val == NULL) {
        fprintf(stderr, "TEST_SECRET is not set\n");
        return 1;
    }

    /* 環境変数を読み取って unsetenv で削除 */
    char *saved = strdup(val);
    unsetenv(env_name);

    /* unsetenv 後の getenv 結果 */
    const char *after = getenv(env_name);
    printf("getenv after unsetenv: %s\n", after ? after : "(null)");
    fflush(stdout);

    /* 親プロセスが ps -E で確認する時間を確保 */
    sleep(5);

    memset(saved, 0, strlen(saved));
    free(saved);
    return 0;
}
EOF

cc -o "$WORKDIR/test_unsetenv" "$WORKDIR/test_unsetenv.c"

echo "=== 検証: unsetenv() は ps -E の出力に影響するか ==="
echo ""

# 環境変数を設定して子プロセスをバックグラウンドで起動
TEST_SECRET="SUPER_SECRET_VALUE_12345" "$WORKDIR/test_unsetenv" &
CHILD_PID=$!

# 子プロセスが起動して unsetenv を実行する時間を待つ
sleep 1

echo "子プロセス PID: $CHILD_PID"
echo ""

# ps -E で子プロセスの環境変数を確認
echo "--- ps -E -ww -p $CHILD_PID の出力 ---"
PS_OUTPUT=$(ps -E -ww -p "$CHILD_PID" 2>&1 || true)
echo "$PS_OUTPUT"
echo "---"
echo ""

# TEST_SECRET が ps の出力に含まれるか判定
if echo "$PS_OUTPUT" | grep -q "SUPER_SECRET_VALUE_12345"; then
    echo "結果: unsetenv() 後も ps -E に TEST_SECRET が表示されます"
    echo "結論: unsetenv() は ps -E に対して【無効】です"
    echo ""
    echo "KERN_PROCARGS2 はカーネルが exec 時に保存したスナップショットであり、"
    echo "ユーザ空間の unsetenv() では変更できません。"
else
    echo "結果: unsetenv() 後、ps -E に TEST_SECRET は表示されません"
    echo "結論: unsetenv() は ps -E に対して【有効】です"
fi

# クリーンアップ
wait "$CHILD_PID" 2>/dev/null || true
