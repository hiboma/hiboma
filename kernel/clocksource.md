

```
Mar 30 14:55:01 vagrant-centos65 kernel: ACPI: HPET 00000000264f02f0 00038 (v01 VBOX   VBOXHPET 00000001 ASL  00000061)
Mar 30 14:55:01 vagrant-centos65 kernel: ACPI: HPET id: 0x8086a201 base: 0xfed00000
Mar 30 14:55:01 vagrant-centos65 kernel: TSC: using HPET reference calibration
Mar 30 14:55:01 vagrant-centos65 kernel: HPET: 3 timers in total, 0 timers will be used for per-cpu timer
Mar 30 14:55:01 vagrant-centos65 kernel: hpet0: at MMIO 0xfed00000, IRQs 2, 8, 0
Mar 30 14:55:01 vagrant-centos65 kernel: hpet0: 3 comparators, 64-bit 100.000000 MHz counter
Mar 30 14:55:01 vagrant-centos65 kernel: Switching to clocksource hpet
Mar 30 14:55:01 vagrant-centos65 kernel: rtc0: alarms up to one day, 114 bytes nvram, hpet irqs
Mar 30 14:55:31 vagrant-centos65 kernel: ACPI: HPET 00000000264f02f0 00038 (v01 VBOX   VBOXHPET 00000001 ASL  00000061)
Mar 30 14:55:31 vagrant-centos65 kernel: ACPI: HPET id: 0x8086a201 base: 0xfed00000
Mar 30 14:55:31 vagrant-centos65 kernel: TSC: using HPET reference calibration
Mar 30 14:55:31 vagrant-centos65 kernel: HPET: 3 timers in total, 0 timers will be used for per-cpu timer
Mar 30 14:55:31 vagrant-centos65 kernel: hpet0: at MMIO 0xfed00000, IRQs 2, 8, 0
Mar 30 14:55:31 vagrant-centos65 kernel: hpet0: 3 comparators, 64-bit 100.000000 MHz counter
Mar 30 14:55:31 vagrant-centos65 kernel: Switching to clocksource hpet
Mar 30 14:55:31 vagrant-centos65 kernel: rtc0: alarms up to one day, 114 bytes nvram, hpet irqs
```


## /sys/devices/system/clocksource/clocksource0/current_clocksource

 * クロックソースを変えると `Switching to clocksource %s` のメッセージが出る
 