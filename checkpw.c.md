# checkpw

 * checkpw-1.02/checkpw.c

```c
#include <sys/stat.h>
#include "error.h"
#include "pathexec.h"
#include "prot.h"
#include "stralloc.h"
#include "openreadclose.h"
#include "env.h"

#include "auto_maildir.h"
#include "auto_password.h"
#include "auto_patrn.h"

#include <pwd.h>
static struct passwd *pw;

static char up[513];
static int uplen;

static stralloc stored = {0};
static stralloc pwfile = {0};

void cleanup()
{
  int i;
  for (i = 0;i < sizeof(up);++i) up[i] = 0;
  for (i = 0;i < stored.len;++i) stored.s[i] = 0;
}

void die(int x)
{
  cleanup();
  _exit(x);
}

main(int argc,char **argv)
{
  char *login;
  char *dash;
  char *ext;
  char *password;
  struct stat st;
  int r;
  int i;
 
  if (!argv[1]) _exit(2);
  
  /* DASH=1 にしたりすると拡張アドレスを使って .password ファイルを探す */
  dash = env_get("DASH");
 
  uplen = 0;

  /*
   * fd = 3 から アカウントとパスワードを read(2) するフォーマットは
   *
   *   "account@example.com\0password\0<???@mailexample.com>\0"
   *
   *   1. アカウント
   *   2. パスワード
   *   3. 接続してきたクライアントのタイムスタンプとホスト名 (?)
   *
   * という \0 区切りの文字列
   */
  for (;;) {
    do
      r = read(3,up + uplen,sizeof(up) - uplen);
    while ((r == -1) && (errno == error_intr));
    if (r == -1) _exit(111);
    if (r == 0) break;
    uplen += r;
    if (uplen >= sizeof(up)) _exit(1);
  }
  close(3);

  i = 0;
  if (i >= uplen) _exit(2);

  /* fd = 3 で read した文字列からログインアカウントを抜き出す */
  login = up + i;
  while (up[i++]) if (i >= uplen) _exit(2);

  /* パスワードを抜き出す */
  password = up + i;
  if (i >= uplen) _exit(2);
  while (up[i++]) if (i >= uplen) _exit(2);

  i = 0;
  ext = login + str_len(login);

  /* ログインを試みるために getpwnam でアカウントを探す */
  for (;;) {

   /*
    * login はログインアカウント (例: test@example.com, example.com-test )
    * ext   は拡張アドレス       (例: test-ext@exmaple.com なら test, test-ext@exmaple.com )
    */
    pw = getpwnam(login);
    if (pw) break;

    /*
     * エラーが EBUSY なら 111 で exit する
     * nscd が死んでる時とか?
     */
    if (errno == error_txtbsy) die(111);

    /*
     * 拡張メールアドレスの - を探す
     *
     */
    for (; ext != login && *ext != '-'; --ext);

    /*
     * getpwnam でログインできるアカウントが無かったので 1 で exit
     */
    if (ext == login) die(1);

    /*
     * ?
     */
    if (i) login[i] = '-';
    i = ext - login;
    login[i] = 0;
    ++ext;
  }
  
  /*
   * ここまできたらログインアカウントが見つかっている(認証はまだ)
   * ログインしたアカウントのホームディレクトリの .password を探す
   *
   * pwfile という変数に .password のパスが格納される
   * 例) vagrant なら "/home/vagrant/Maildir/.password"
   */

  /* ログインアカウントの $HOME に chdir */
  if (chdir(pw->pw_dir) == -1) die(111);

  /* pwfile = $HOME + "/Maildir" な文字列を作る */
  if (!stralloc_copys(&pwfile, auto_maildir)) die(111);

  /*
   * 環境変数DASHと拡張メールアドレスが有効な場合は
   *
   *   pwfile = pwfile + ENV["DASH"] + ext
   *
   * な文字列を作る
   */
  if (dash && *ext) {
    if (!stralloc_cats(&pwfile, dash)) die(111);
    if (!stralloc_cats(&pwfile, ext)) die(111);
  }

  /* pwfile = pwfile + "/" */
  if (!stralloc_append(&pwfile, "/")) die(111);

  /* pwfile = pwfile + ".password な文字列をつくる */
  if (!stralloc_cats(&pwfile, auto_password)) die(111);

  /* \0 終端にする? */
  if (!stralloc_0(&pwfile)) die(111);

  /* $HOME/Maildir/.password を stat する。無ければ 1 で exit */
  if (stat(pwfile.s,&st) == -1) die(1);

  /* $HOME/Maildir/.password の uid とログインアカウントの uid が一致するかどうかを見る */
  if (st.st_uid != pw->pw_uid) die(1);

  /* ??? */
  if (st.st_mode & auto_patrn) die(111);

  /* $HOME/Maildir/.password の中身を storead に読み込む */
  if (openreadclose(pwfile.s,&stored,32) != 1) die(111);

  /* \0 終端にする ?*/
  if (!stralloc_0(&stored)) die(111);
  stored.s[str_chr(stored.s,'\n')] = 0;

  /* .password とクライアントが入力したパスワードを比較 (平文!!!!) */
  if (!*stored.s || strcmp(password,stored.s)) die(1);

  /* pw->pw_gid に setgid する */
  if (prot_gid((int) pw->pw_gid) == -1) die(1);

  /* pw->pw_uid に setuid する */
  if (prot_uid((int) pw->pw_uid) == -1) die(1);

  /* 環境変数をセット */
  if (!pathexec_env("USER",pw->pw_name)) die(111);
  if (!pathexec_env("EXT",ext)) die(111);
  if (!pathexec_env("HOME",pw->pw_dir)) die(111);
  if (!pathexec_env("SHELL",pw->pw_shell)) die(111);
  cleanup();

  /* checkpw に渡したコマンドを execve */
  pathexec(argv + 1);
  _exit(111);
}
```
