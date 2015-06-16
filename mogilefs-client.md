# mogilefs-client

この例外がどんな実装なのかを追いけかるよ

```
mogfs002:7001 never became readable (timeout=0.1)
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/socket_common.rb:16:in `unreadable_socket!'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/socket/kgio.rb:24:in `timed_read'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/socket_common.rb:29:in `timed_gets'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/backend.rb:243:in `block in do_request'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/backend.rb:240:in `synchronize'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/backend.rb:240:in `do_request'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/backend.rb:22:in `block (2 levels) in add_idempotent_command'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/mogilefs.rb:386:in `sleep'
```

## request timeout の実装を追う

##### サンプルコード

request timeout を擬似的に再現するには `sleep` を呼ぶとよい

```ruby
#!/usr/bin/env ruby

require 'mogilefs'

hosts = [
  'mogfs001:7001', # 127.0.0.1:7001
  'mogfs002:7001', # 127.0.0.1:7001
  'mogfs003:7001', # 127.0.0.1:7001
]

domain = 'sandbox'
timeout = 0.1
fail_timeout = 5

mogfs = MogileFS::MogileFS.new(
  hosts: hosts,
  domain: domain,
  timeout: timeout,
  fail_timeout: fail_timeout,
)

# 俺俺リトライ
1.upto(hosts.size) { |i|
  begin
    warn mogfs.sleep(1)
    break
  rescue MogileFS::UnreadableSocketError, MogileFS::Timeout => e
    warn ""
    warn e
    warn e.backtrace
    next
  rescue
    raise
  end
}
```

##### 実行結果

```
$ bundle exec ruby hoge.rb
mogfs002:7001 never became readable (timeout=0.1)
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/socket_common.rb:16:in `unreadable_socket!'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/socket/kgio.rb:24:in `timed_read'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/socket_common.rb:29:in `timed_gets'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/backend.rb:243:in `block in do_request'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/backend.rb:240:in `synchronize'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/backend.rb:240:in `do_request'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/backend.rb:22:in `block (2 levels) in add_idempotent_command'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/mogilefs.rb:386:in `sleep'
hoge.rb:24:in `block in <main>'
hoge.rb:22:in `upto'
hoge.rb:22:in `<main>'

mogfs001:7001 never became readable (timeout=0.1)
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/socket_common.rb:16:in `unreadable_socket!'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/socket/kgio.rb:24:in `timed_read'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/socket_common.rb:29:in `timed_gets'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/backend.rb:243:in `block in do_request'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/backend.rb:240:in `synchronize'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/backend.rb:240:in `do_request'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/backend.rb:22:in `block (2 levels) in add_idempotent_command'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/mogilefs.rb:386:in `sleep'
hoge.rb:24:in `block in <main>'
hoge.rb:22:in `upto'
hoge.rb:22:in `<main>'

mogfs002:7001 never became readable (timeout=0.1)
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/socket_common.rb:16:in `unreadable_socket!'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/socket/kgio.rb:24:in `timed_read'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/socket_common.rb:29:in `timed_gets'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/backend.rb:243:in `block in do_request'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/backend.rb:240:in `synchronize'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/backend.rb:240:in `do_request'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/backend.rb:22:in `block (2 levels) in add_idempotent_command'
./vendor/bundle/ruby/2.2.0/gems/mogilefs-client-3.8.0/lib/mogilefs/mogilefs.rb:386:in `sleep'
hoge.rb:24:in `block in <main>'
hoge.rb:22:in `upto'
hoge.rb:22:in `<main>'
```

`sleep する時間 > timeout 値` の場合、上記のように raise する

## MogileFS::Backend#sleep から実装を追う

mogilefs クライアントから mogilefsd に何かデータを送るのは `command` と命名されている。

```ruby
  add_idempotent_command :sleep
```

`sleep` コマンドは `add_idempotent_command` によって、メタプログラミングなやり方で追加されている  

```
  # ...  

  # adds idempotent MogileFS commands +names+, these commands may be retried
  # transparently on a different tracker if there is a network/server error.
  def self.add_idempotent_command(*names)
    names.each do |name|
      define_method name do |*args|
        do_request(name, args[0] || {}, true)
      end
    end
  end
```

低いレイヤで何をやっているかは `do_request` を追いかけることになる

## MogileFS::Backend#do_request

ここから結構複雑。がんばって解読して。ポイントは

 * mogilefs クライアント は mogilefsd に command を送る
 * mogilefs クライアント は mogilefsd が command に応答するのを待つ
   * ここでタイムアウトすると raise する

という点である 

```ruby
  # Performs the +cmd+ request with +args+.
  def do_request(cmd, args, idempotent = false)
    no_raise = args.delete(:ruby_no_raise)
    request = make_request(cmd, args)
    line = nil
    failed = false
    @mutex.synchronize do
      begin
        io = dispatch_unlocked(request)
        # ここの中で raise する
        line = io.timed_gets(@timeout)
        break if /\r?\n\z/ =~ line

        line and raise MogileFS::InvalidResponseError,
                       "Invalid response from server: #{line.inspect}"

        idempotent or
          raise EOFError, "end of file reached after: #{request.inspect}"
        # fall through to retry in loop
      rescue SystemCallError,
             MogileFS::InvalidResponseError # truncated response
        # we got a successful timed_write, but not a timed_gets
        if idempotent
          failed = true
          shutdown_unlocked(false)
          retry
        end
        shutdown_unlocked(true)
      rescue MogileFS::UnreadableSocketError, MogileFS::Timeout
        # ここで rescue する
        shutdown_unlocked(true)
      rescue
        # we DO NOT want the response we timed out waiting for, to crop up later
        # on, on the same socket, intersperesed with a subsequent request!  we
        # close the socket if there's any error.
        shutdown_unlocked(true)
      end while idempotent
      shutdown_unlocked if failed
    end # @mutex.synchronize
    parse_response(line, no_raise ? request : nil)
  end
```

## MogileFS::SocketCommon#timed_gets

`timed_read` で mogilefsd の応答を待つ

```ruby
  SEP_RE = /\A(.*?#{Regexp.escape("\n")})/
  def timed_gets(timeout = 5)
    unless defined?(@rbuf) && @rbuf
      @rbuf = timed_read(1024, "", timeout) or return # EOF
    end
    begin
      @rbuf.sub!(SEP_RE, "") and return $1
      tmp ||= ""

      # ここで待つ
      if timed_read(1024, tmp, timeout)
        @rbuf << tmp
      else
        # EOF, return the last buffered bit even without SEP_RE matching
        # (not ideal for MogileFS, this is an error)
        return @rbuf.empty? ? nil : @rbuf.slice!(0, @rbuf.size)
      end
    end while true
  end
```

## MogileFS::Socket < Kgio::Socket

`timed_read` は `kgio::Socket` によって実装されている。
`kgio_wait_readable` でタイムアウトすると、 `unreadable_socket = MogileFS::UnreadableSocketError` を raise する

```ruby
class MogileFS::Socket < Kgio::Socket
  include MogileFS::SocketCommon

  # ...  

  def timed_read(len, dst = "", timeout = 5)
    case rc = kgio_tryread(len, dst)
    when :wait_readable
      # ここで raise する
      kgio_wait_readable(timeout) or unreadable_socket!(timeout)
    else
      return rc
    end while true
  end
```

kgio_wait_readable の実装は [ここいら](https://github.com/betterplace/kgio/blob/master/ext/kgio/wait.c) を追う。本題からズレるので言及しない
