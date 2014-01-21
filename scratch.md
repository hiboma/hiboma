
## vagrant ssh-config を Tempfile に書き出して ssh -F で vagrant に接続

```ruby
ssh_config = Tempfile.new('nukofs-ssh-config')
ssh_config.write(`vagrant ssh-config`)
ssh_config.close
at_exit { ssh_config.unlink } 

guard 'shell' do 
  watch("nukofs.c") do
    puts "Building module ..."
    `time ssh -F #{ssh_config.path} default -- sudo /vagrant/script/make-and-make-test.sh`
  end 
end
```

 * 2-3秒しか変わらんかった。 make/テストケースの実行 が短いと快適かもしれない
 * make/テストの時間が長くなってきたら対して差を感じないはず