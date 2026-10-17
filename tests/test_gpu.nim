import std/[strutils, unittest]

import bsdinfo/amdgpu_drm
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

suite "DRM ABI":
  test "the amdgpu info request is 32 bytes":
    check sizeof(DrmAmdgpuInfo) == 32

  test "the ioctl request number matches the DRM ABI":
    check DrmIoctlAmdgpuInfo == 0x80206445'u64

suite "parseAmdgpuVersion":
  test "extracts the version from the message buffer":
    let msgBuf = "<118>Loading kernel modules: amdgpu\n" &
                 "<6>[drm] Initialized amdgpu 3.54.0 20150101 for drmn0 on minor 0\n"
    check parseAmdgpuVersion(msgBuf) == "3.54.0"

  test "returns an empty string when the line is absent":
    check parseAmdgpuVersion("no driver line here") == ""

suite "parseCurrentClock":
  test "picks the state marked with a star":
    check parseCurrentClock("0: 500Mhz\n1: 800Mhz *\n2: 2750Mhz") == 800

  test "falls back to the first entry":
    check parseCurrentClock("0: 500Mhz\n1: 800Mhz") == 500

  test "returns zero for empty input":
    check parseCurrentClock("") == 0

suite "summaries":
  test "vramSummary reports n/a without a driver":
    check vramSummary(GpuMetrics()) == "vram n/a"

  test "metricsSummary always mentions the fan":
    check metricsSummary(GpuMetrics()) == "fan n/a"

  test "driverSummary joins the available fields":
    let summary = driverSummary(
      GpuDriverInfo(driverVersion: "amdgpu 3.54.0", vbiosVersion: "113-X"))
    check "amdgpu 3.54.0" in summary
    check "vbios 113-X" in summary

suite "collectGpuMetrics":
  let metrics = collectGpuMetrics()

  test "VRAM usage never exceeds the total":
    if metrics.vramTotalBytes > 0:
      check metrics.vramUsedBytes <= metrics.vramTotalBytes

  test "temperature is plausible when reported":
    check metrics.temperatureC >= 0.0
    check metrics.temperatureC < 150.0

  test "fan speed is not exposed by drm-kmod":
    check metrics.fanSpeedRpm == 0

suite "collectGpuDriverInfo":
  let info = collectGpuDriverInfo()

  test "the driver version is reported when the device is present":
    if info.drmDevice.len > 0:
      check info.driverVersion.len > 0

  test "the vbios version is populated":
    if info.drmDevice.len > 0:
      check info.vbiosVersion.len > 0

suite "collectGpus":
  let gpus = collectGpus()

  test "every reported device is display class":
    for gpu in gpus:
      check (gpu.pciClass shr 16) == 0x03

  test "reported devices are fully described":
    for gpu in gpus:
      check gpu.vendorName.len > 0
      check gpu.deviceName.len > 0

  test "metrics are attached to the first GPU":
    if gpus.len > 0 and findDrmDevice().len > 0:
      check gpus[0].metrics.vramTotalBytes > 0
      check gpus[0].driver.driverVersion.len > 0
