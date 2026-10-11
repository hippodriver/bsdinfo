import std/unittest

import bsdinfo/gpu

const sample =
  "vgapci0@pci0:3:0:0:\tclass=0x030000 rev=0xc7 hdr=0x00 " &
  "vendor=0x1002 device=0x73ff subvendor=0x1da2 subdevice=0xe447\n" &
  "    vendor     = 'Advanced Micro Devices, Inc. [AMD/ATI]'\n" &
  "    device     = 'Navi 23 [Radeon RX 6600/6600 XT/6600M]'\n" &
  "    class      = display\n" &
  "    subclass   = VGA\n" &
  "hdac0@pci0:3:0:1:\tclass=0x040300 rev=0x00 hdr=0x00 " &
  "vendor=0x1002 device=0xab28 subvendor=0x1002 subdevice=0x1002\n" &
  "    vendor     = 'Advanced Micro Devices, Inc. [AMD/ATI]'\n" &
  "    device     = 'Navi 21/23 HDMI/DP Audio Controller'\n" &
  "    class      = multimedia\n" &
  "    subclass   = HDA\n"

suite "parsePciconfLv":
  let gpus = parsePciconfLv(sample)

  test "keeps only display controllers":
    check gpus.len == 1

  test "extracts names":
    check gpus[0].vendorName == "Advanced Micro Devices, Inc. [AMD/ATI]"
    check gpus[0].deviceName == "Navi 23 [Radeon RX 6600/6600 XT/6600M]"

  test "extracts ids and class":
    check gpus[0].vendorId == 0x1002'u16
    check gpus[0].deviceId == 0x73ff'u16
    check gpus[0].pciClass == 0x030000'u32

  test "extracts the slot":
    check gpus[0].slot == "vgapci0@pci0:3:0:0:"

suite "collectGpus":
  let gpus = collectGpus()

  test "every reported device is display class":
    for gpu in gpus:
      check (gpu.pciClass shr 16) == 0x03

  test "reported devices are fully described":
    for gpu in gpus:
      check gpu.vendorName.len > 0
      check gpu.deviceName.len > 0
