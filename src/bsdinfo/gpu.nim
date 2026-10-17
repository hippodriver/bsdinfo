## GPU (display controller) information.
##
## Devices come from `pciconf -lv` (FreeBSD has no `libpci` in the base
## system); the load, memory and sensor readings come from the amdgpu driver
## through its `sys.device.drmnN.*` sysctls and `DRM_IOCTL_AMDGPU_INFO`.

import std/[osproc, strutils]

import ./amdgpu_drm
import ./format
import ./sysctlread

const
  PciDisplayBaseClass = 0x03
  HexDigits = {'0' .. '9', 'a' .. 'f', 'A' .. 'F'}

type
  GpuMetrics* = object
    loadPercent*: int              ## GPU utilisation
    memLoadPercent*: int           ## memory-controller utilisation
    vramTotalBytes*: uint64
    vramUsedBytes*: uint64
    vramCpuAccessibleBytes*: uint64
    gttBytes*: uint64             ## driver-reported GTT value; drm-kmod 3.54
                                  ## reports the same counter as VRAM usage
    temperatureC*: float
    powerW*: float
    sclkMhz*: int                  ## shader clock
    mclkMhz*: int                  ## memory clock
    fanSpeedRpm*: int              ## 0: not exposed by drm-kmod 3.54

  GpuDriverInfo* = object
    drmDevice*: string             ## sysctl prefix, e.g. `sys.device.drmn0`
    driverVersion*: string         ## e.g. `amdgpu 3.54.0`
    vbiosVersion*: string
    smcFirmware*: string
    powerState*: string

  GpuInfo* = object
    slot*: string        ## PCI location, e.g. `vgapci0@pci0:3:0:0:`
    vendorName*: string  ## vendor string from `pciconf`
    deviceName*: string  ## device string from `pciconf`
    vendorId*: uint16    ## PCI vendor id
    deviceId*: uint16    ## PCI device id
    pciClass*: uint32    ## full PCI class, e.g. 0x030000
    metrics*: GpuMetrics
    driver*: GpuDriverInfo

proc extractQuoted(line: string): string =
  let start = line.find('\'')
  if start < 0:
    return ""
  let stop = line.find('\'', start + 1)
  if stop < 0:
    return ""
  result = line[start + 1 ..< stop]

proc extractHex(line: string; prefix: string): uint32 =
  let at = line.find(prefix)
  if at < 0:
    return 0
  let start = at + prefix.len
  var stop = start
  while stop < line.len and line[stop] in HexDigits:
    inc stop
  if stop == start:
    return 0
  try:
    result = uint32(parseHexInt(line[start ..< stop]))
  except ValueError:
    result = 0

proc parsePciconfLv*(output: string): seq[GpuInfo] =
  ## Parse `pciconf -lv` output, returning only display-class devices.
  var current: GpuInfo
  var haveCurrent = false
  var isDisplay = false

  template flush() =
    if haveCurrent and isDisplay:
      result.add current

  for line in output.splitLines():
    if line.len == 0:
      continue

    if line[0] == ' ' or line[0] == '\t':
      if not haveCurrent:
        continue
      let trimmed = line.strip()
      if trimmed.startsWith("vendor") and trimmed.contains('='):
        current.vendorName = extractQuoted(trimmed)
      elif trimmed.startsWith("device") and trimmed.contains('='):
        current.deviceName = extractQuoted(trimmed)
    else:
      flush()
      current = GpuInfo()
      haveCurrent = true

      current.pciClass = extractHex(line, "class=0x")
      current.vendorId = uint16(extractHex(line, " vendor=0x"))
      current.deviceId = uint16(extractHex(line, " device=0x"))

      let tab = line.find('\t')
      let stop = if tab >= 0: tab else: line.len
      current.slot = line[0 ..< stop]

      isDisplay = (current.pciClass shr 16) == PciDisplayBaseClass

  flush()

proc parseAmdgpuVersion*(msgBuf: string): string =
  ## Extract the version from the `Initialized amdgpu <version> ...` line that
  ## the driver writes to the kernel message buffer.
  const Marker = "Initialized amdgpu "
  for line in msgBuf.splitLines():
    let at = line.find(Marker)
    if at >= 0:
      let fields = line[at + Marker.len .. ^1].splitWhitespace()
      if fields.len > 0:
        return fields[0]
  ""

proc parseClockMhz(text: string): int =
  for token in text.splitWhitespace():
    if token.endsWith("Mhz") or token.endsWith("MHz"):
      try:
        return parseInt(token[0 ..< token.len - 3])
      except ValueError:
        return 0
  0

proc parseCurrentClock*(text: string): int =
  ## Parse `pp_dpm_*` output (`0: 500Mhz`, `1: 800Mhz *`) into the frequency of
  ## the active state, marked with `*`, or the first entry when none is marked.
  var fallback = 0
  for line in text.splitLines():
    let trimmed = line.strip()
    let value = parseClockMhz(trimmed)
    if value == 0:
      continue
    if fallback == 0:
      fallback = value
    if '*' in trimmed:
      return value
  fallback

proc parseSysctlInt(text: string; default = 0): int =
  try:
    parseInt(text.strip())
  except ValueError:
    default

const DrmPrefixes = ["sys.device.drmn", "dev.amdgpu."]

proc findDrmDevice*(): string =
  ## Locate the drm-kmod device sysctl prefix, e.g. `sys.device.drmn0`.
  for prefix in DrmPrefixes:
    for unit in 0 .. 7:
      let name = prefix & $unit
      if hasSysctl(name & ".gpu_busy_percent"):
        return name
  ""

proc collectGpuMetrics*(): GpuMetrics =
  ## Read the GPU load, memory usage and sensor values. Everything is
  ## best-effort: a missing driver or an unreadable device leaves fields zero.
  let drm = findDrmDevice()
  if drm.len > 0:
    result.loadPercent = parseSysctlInt(sysctlStringOrDefault(drm & ".gpu_busy_percent"))
    result.memLoadPercent = parseSysctlInt(sysctlStringOrDefault(drm & ".mem_busy_percent"))
    result.sclkMhz = parseCurrentClock(sysctlStringOrDefault(drm & ".pp_dpm_sclk"))
    result.mclkMhz = parseCurrentClock(sysctlStringOrDefault(drm & ".pp_dpm_mclk"))

  let fd = openDrmNode()
  if fd < 0:
    return
  defer: closeDrmNode(fd)

  var used: uint64
  if queryVramUsage(fd, used):
    result.vramUsedBytes = used

  var memory: DrmAmdgpuInfoVramGtt
  if queryMemory(fd, memory):
    result.vramTotalBytes = memory.vramSize
    result.vramCpuAccessibleBytes = memory.vramCpuAccessibleSize
    result.gttBytes = memory.gttSize

  var value: uint32
  if querySensor(fd, AmdgpuSensorGpuTemp, value):
    result.temperatureC = value.float / 1000.0
  if querySensor(fd, AmdgpuSensorGpuLoad, value):
    result.loadPercent = int(value)
  if querySensor(fd, AmdgpuSensorGpuAvgPower, value):
    result.powerW = value.float
  if querySensor(fd, AmdgpuSensorStablePstateGfxSclk, value):
    result.sclkMhz = int(value)
  if querySensor(fd, AmdgpuSensorStablePstateGfxMclk, value):
    result.mclkMhz = int(value)

proc collectGpuDriverInfo*(): GpuDriverInfo =
  ## Read the driver, VBIOS and firmware identification.
  result.drmDevice = findDrmDevice()
  if result.drmDevice.len > 0:
    result.vbiosVersion = sysctlStringOrDefault(result.drmDevice & ".vbios_version", "")
    result.powerState =
      sysctlStringOrDefault(result.drmDevice & ".power_dpm_state", "")
    result.smcFirmware =
      sysctlStringOrDefault(result.drmDevice & ".fw_version.smc_fw_version", "")

  if hasSysctl("kern.msgbuf"):
    let version = parseAmdgpuVersion(sysctlStringOrDefault("kern.msgbuf", ""))
    if version.len > 0:
      result.driverVersion = "amdgpu " & version

  if result.driverVersion.len == 0 and result.drmDevice.len > 0:
    result.driverVersion = "amdgpu"

proc vramPercent*(metrics: GpuMetrics): float =
  if metrics.vramTotalBytes == 0:
    0.0
  else:
    metrics.vramUsedBytes.float / metrics.vramTotalBytes.float * 100.0

proc vramSummary*(metrics: GpuMetrics): string =
  ## e.g. `vram 711 MiB / 7.98 GiB  8.7%`.
  if metrics.vramTotalBytes == 0:
    return "vram n/a"
  "vram " & formatBytes(metrics.vramUsedBytes) & " / " &
    formatBytes(metrics.vramTotalBytes) & "  " & formatPercent(vramPercent(metrics))

proc metricsSummary*(metrics: GpuMetrics): string =
  ## e.g. `temp 50.0 C  power 5 W  sclk 1.95 GHz  mclk 676 MHz  fan n/a`.
  var parts: seq[string]
  if metrics.temperatureC > 0.0:
    parts.add "temp " & formatFloat(metrics.temperatureC, ffDecimal, 1) & " C"
  if metrics.powerW > 0.0:
    parts.add "power " & $int(metrics.powerW) & " W"
  if metrics.sclkMhz > 0:
    parts.add "sclk " & formatMhz(metrics.sclkMhz)
  if metrics.mclkMhz > 0:
    parts.add "mclk " & formatMhz(metrics.mclkMhz)
  if metrics.fanSpeedRpm > 0:
    parts.add "fan " & $metrics.fanSpeedRpm & " rpm"
  else:
    parts.add "fan n/a"
  parts.join("   ")

proc driverSummary*(info: GpuDriverInfo): string =
  ## e.g. `amdgpu 3.54.0  sys.device.drmn0  vbios 113-2447LHM-WD1  smc 0x003b3200`.
  var parts: seq[string]
  if info.driverVersion.len > 0:
    parts.add info.driverVersion
  if info.drmDevice.len > 0:
    parts.add info.drmDevice
  if info.vbiosVersion.len > 0:
    parts.add "vbios " & info.vbiosVersion
  if info.smcFirmware.len > 0:
    parts.add "smc " & info.smcFirmware
  if info.powerState.len > 0:
    parts.add "power " & info.powerState
  parts.join("   ")

proc collectGpus*(): seq[GpuInfo] =
  ## Enumerate display devices using `pciconf -lv`, then attach the driver's
  ## metrics to the first entry. drm-kmod exposes a single device node, so with
  ## more than one GPU only the first is described.
  try:
    let (output, exitCode) = execCmdEx("/usr/sbin/pciconf -lv")
    if exitCode == 0:
      result = parsePciconfLv(output)
  except OSError:
    discard

  if result.len == 0:
    return

  result[0].metrics = collectGpuMetrics()
  result[0].driver = collectGpuDriverInfo()
