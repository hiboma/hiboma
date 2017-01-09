# SeaBIOS ブートローダ読み込み

BIOS の POST `Power On Self Test` のエントリポイントからブートローダ読み込までを俯瞰する

## SeaBIOS

ソースは `qemu-2.7.0/roms/seabios` 以下を読んでみる https://www.coreboot.org/SeaBIOS によると ***SeaBIOS*** とは下記の通り

```
SeaBIOS is an open-source legacy BIOS implementation which can be used as a coreboot payload. It implements the standard BIOS calling interfaces that a typical x86 proprietary BIOS implements.
```

## POST Power On Self Test

POST のコードは `handle_post` から始まる (handle_post) がどのように呼び出されるか、は別で調べよう)

```c
// Entry point for Power On Self Test (POST) - the BIOS initilization
// phase.  This function makes the memory at 0xc0000-0xfffff
// read/writable and then calls dopost().
void VISIBLE32FLAT
handle_post(void)
{
    if (!CONFIG_QEMU && !CONFIG_COREBOOT)
        return;

    serial_debug_preinit();
    debug_banner();

    // Check if we are running under Xen.
    xen_preinit();

    // Allow writes to modify bios area (0xf0000)
    make_bios_writable();

    // Now that memory is read/writable - start post process.
    dopost(); 🍄
}
```

`handle_post` で `make_bios_writable`　で `0xc0000-0xfffff` のメモリを読み書き可能に初期化をした後に `dopost` に続く。do_post の各処理はすっ飛ばして読む

```c
// Setup for code relocation and then relocate.
void VISIBLE32INIT
dopost(void)
{
    // Detect ram and setup internal malloc.
    qemu_preinit();
    coreboot_preinit();
    malloc_preinit();

    // Relocate initialization code and call maininit().
    reloc_preinit(maininit, NULL); 🍄
}
```

maininit では各種ハードウェアの初期化を済ませて `startBoot()` に続く。ざっと見で理解できたのは下記の通り

 * 割り込みベクタとハンドラの初期化
   * ブートローダを読む過程で、BIOS 自身が INT 命令で割り込みをかけて 割り込みベクタ経由でルーチンを呼び出す
 * BDA BIOS Data Area の初期化
   *  http://stanislavs.org/helppc/bios_data_area.html に従って memory map を設定する?
 * PnP Plagy and Play の初期化
 * キーボードコントローラーの初期化
 * マウスコントローラーの初期化
 * DMA の初期化
 * PIC の初期化
 * 浮動小数点数コプロセッサ (Math Coprocessor) の初期化
 * PCI の初期化
 * タイマーの初期化
 * クロックの初期化
 * TPM トラステッド プラットフォーム モジュール の初期化
 * USB
 * シリアルポート
 * PS/2 ポート
 * LPT
 * フロッピードライブ
 * ATA
 * AHCI Advanced Host Controller Interface
 * SCSI
 * virtio-blk, virtio-scsi の初期化なども紛れ込んでいる

それぞれの詳細を調べていたらキリがないので、割愛。`make_bios_readonly` で BIOS のコードがおいてあるセグメント `0xf0000` を読み取り専用にして、 `startBoot` に続く

```c
// Main setup code.
static void
maininit(void)
{
    // Initialize internal interfaces.
    interface_init();

    // Setup platform devices.
    platform_hardware_setup();

    // Start hardware initialization (if threads allowed during optionroms)
    if (threads_during_optionroms())
        device_hardware_setup();

    // Run vga option rom
    vgarom_setup();

    // Do hardware initialization (if running synchronously)
    if (!threads_during_optionroms()) {
        device_hardware_setup();
        wait_threads();
    }

    // Run option roms
    optionrom_setup();

    // Allow user to modify overall boot order.
    interactive_bootmenu();
    wait_threads();

    // Prepare for boot.
    prepareboot();

    // Write protect bios memory.
    make_bios_readonly();

    // Invoke int 19 to start boot process.
    startBoot(); 🍄
}
```

startBoot で `INT 0x13` で、割り込みベクタ19番目のハンドラ ***Boot Load Service Entry Point*** を呼び出す。 (アセンブラのコードを経由して) `handle_19` に続く

```c
// Begin the boot process by invoking an int0x19 in 16bit mode.
void VISIBLE32FLAT
startBoot(void)
{
    // Clear low-memory allocations (required by PMM spec).
    memset((void*)BUILD_STACK_ADDR, 0, BUILD_EBDA_MINIMUM - BUILD_STACK_ADDR);

    dprintf(3, "Jump to int19\n");
    struct bregs br;
    memset(&br, 0, sizeof(br));
    br.flags = F_IF;
    call16_int(0x19, &br);
}
```

BIOS 自身が BIOS サービスを呼び出すにあたって INT で割り込みをかけるのが面白い

## INT 19h Boot Load Service Entry Point

`INT 0x19` からブートローダの読み取りを行うのだが、ftp://ftp.embeddedarm.com/old/saved-downloads-manuals/EBIOS-UM.PDF  の *1.1.2.1.10 INT 19h, Bootstrap Routine* の説明によると

> The boot actions for drives A: through K: read one sector from the drive at sector 1, head 0, track 0 into physical memory location 00007C00h. If the read is successful and if the boot record contains the byte sequence 55h, aah, as the last two bytes in the 512-byte sector, then control is transferred to the boot record at 16:16 address 07C0:0000, and the BIOS plays no further role in the bootstrap process.

* A〜Kドライブから ヘッド `0`、トラック `0` の 1セクタを読みとり、物理メモリ `00007C00h` に配置する
* 1セクタ 512バイトで、最後の2バイトが `0x55``0xaa` かどうかをみる
* 16:16? ( `16bit:16bit` の論理アドレスであることを明示しているのかな?)
* `07C0:0000` に制御を移したあとのブートストラッププロセスでは、BIOS は関与しない

```c
// INT 19h Boot Load Service Entry Point
void VISIBLE32FLAT
handle_19(void)
{
    debug_enter(NULL, DEBUG_HDL_19);
    BootSequence = 0;
    do_boot(0); 🍄
}
```

`do_boot` ではブートローダを読み込むデバイスによって処理を分岐している (デバイスの指定は qemu から指定するのかな?) 一番簡単そうなフロッピーの場合を読んでいく。 `boot_disk` は引数が違うだけで FDD/HDD どちらの場合にも使いまわせる

```c
// Determine next boot method and attempt a boot using it.
static void
do_boot(int seq_nr)
{
    if (! CONFIG_BOOT)
        panic("Boot support not compiled in.\n");

    if (seq_nr >= BEVCount)
        boot_fail();

    // Boot the given BEV type.
    struct bev_s *ie = &BEV[seq_nr];
    switch (ie->type) {
    case IPL_TYPE_FLOPPY:
        printf("Booting from Floppy...\n");
        boot_disk(0x00, CheckFloppySig); 🍄
        break;
    case IPL_TYPE_HARDDISK:
        printf("Booting from Hard Disk...\n");
        boot_disk(0x80, 1);
        break;
    case IPL_TYPE_CDROM:
        boot_cdrom((void*)ie->vector);
        break;
    case IPL_TYPE_CBFS:
        boot_cbfs((void*)ie->vector);
        break;
    case IPL_TYPE_BEV:
        boot_rom(ie->vector);
        break;
    case IPL_TYPE_HALT:
        boot_fail();
        break;
    }

    // Boot failed: invoke the boot recovery function
    struct bregs br;
    memset(&br, 0, sizeof(br));
    br.flags = F_IF;
    call16_int(0x18, &br);
}
```

boo_disk でドライブからセクタを読み取り `0x7c0:0000` にセクタをロードする。OS を自作する系の教科書で最初に出てくるマジックナンバーに辿り着く

```c
// Boot from a disk (either floppy or harddrive)
static void
boot_disk(u8 bootdrv, int checksig)
{
    u16 bootseg = 0x07c0; // 0x07c0:0000 の論理アドレスにブートロードをロードする (物理アドレスは 0x7c000)

    // Read sector
    struct bregs br;
    memset(&br, 0, sizeof(br));
    br.flags = F_IF;
    br.dl = bootdrv;       // ブートローダを読むドライブ
    br.es = bootseg;       // ブートローダを読み込むセグメント(ES)の指定
    br.ah = 2;             // サービス番号 -> Read Sectors
    br.al = 1;             // セクタ数
    br.cl = 1;             // 1番目のセクタ
    call16_int(0x13, &br); // INT 0x13 で BIOS サービスを呼び出し、ディスクから セクタの読み取り

    // ディスクの読み取りで失敗してたら CF フラグがたつ。エラーハンドリングのコード
    if (br.flags & F_CF) {
        printf("Boot failed: could not read the boot disk\n\n");
        return;
    }

    if (checksig) {
        struct mbr_s *mbr = (void*)0;
        if (GET_FARVAR(bootseg, mbr->signature) != MBR_SIGNATURE) {
            printf("Boot failed: not a bootable disk\n\n");
            return;
        }
    }

    tpm_add_bcv(bootdrv, MAKE_FLATPTR(bootseg, 0), 512);

    /* Canonicalize bootseg:bootip */
    u16 bootip = (bootseg & 0x0fff) << 4;
    bootseg &= 0xf000;

    call_boot_entry(SEGOFF(bootseg, bootip), bootdrv);
}
```

bootip や bootseg を `Canonicalize` する理由がよくわからない。最後に `call_boot_entry` で far call して BIOS からブートローダへ制御が移る

```c
// Jump to a bootup entry point.
static void
call_boot_entry(struct segoff_s bootsegip, u8 bootdrv)
{
    dprintf(1, "Booting from %04x:%04x\n", bootsegip.seg, bootsegip.offset);
    struct bregs br;
    memset(&br, 0, sizeof(br));
    br.flags = F_IF;
    br.code = bootsegip;
    // Set the magic number in ax and the boot drive in dl.
    br.dl = bootdrv; //?
    br.ax = 0xaa55;  //?
    farcall16(&br);
}
```

farcall の前に `DL = bootdrv`, AX = `0xaa55` を入れているが、BIOS の仕様か? 
