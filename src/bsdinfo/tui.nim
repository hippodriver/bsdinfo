## Terminal dashboard built with illwill, reusing the shared `SystemInfo`.

import std/[os, strutils]

import illwill

import ./cpu
import ./format
import ./gpu
import ./net
import ./sysctlread
import ./systeminfo

const RefreshSeconds = 1.0

proc bar(fraction: float; width: int): string =
  var columns = width
  if columns < 1:
    columns = 1
  var value = fraction
  if value < 0.0:
    value = 0.0
  elif value > 1.0:
    value = 1.0
  let filled = int(value * columns.float + 0.5)
  result = "[" & repeat('#', filled) & repeat(' ', columns - filled) & "]"

const
  CoreNameWidth = 6
  CoreFreqWidth = 9
  CoreBarWidth = 12
  CorePercentWidth = 6

proc coreCell(core: CpuCore; index: int): string =
  "cpu" & align($index, CoreNameWidth - 3) & " " &
    align(formatMhz(core.frequencyMhz), CoreFreqWidth) & " " &
    bar(core.loadPercent / 100.0, CoreBarWidth) & " " &
    align(formatPercent(core.loadPercent), CorePercentWidth)

proc coreHeaderCell(): string =
  "core" & repeat(' ', CoreNameWidth - "core".len) & " " &
    align("freq", CoreFreqWidth) & " " &
    "load" & repeat(' ', CoreBarWidth + 2 - "load".len) & " " &
    repeat(' ', CorePercentWidth)

proc drawLine(tb: var TerminalBuffer; y: var int; width: int; text: string) =
  if y >= 0 and y < int(tb.height):
    let clipped = if text.len > width: text[0 ..< width] else: text
    tb.write(0, y.Natural, clipped)
  inc y

proc drawTitle(tb: var TerminalBuffer; y: var int; width: int; title: string) =
  tb.setForegroundColor(fgCyan)
  tb.setBackgroundColor(bgNone)
  if y >= 0 and y < int(tb.height):
    let header = title & " "
    let rule = repeat('-', max(0, width - header.len))
    tb.write(0, y.Natural, (header & rule)[0 ..< width])
  tb.setForegroundColor(fgNone)
  inc y

proc render(tb: var TerminalBuffer; system: SystemInfo; error: string;
            scroll: int): int =
  ## Draw the dashboard starting at line `scroll` and return the total number of
  ## lines, so the caller can clamp the scroll position.
  let width = int(tb.width)
  var y = -scroll

  tb.setForegroundColor(fgWhite)
  drawLine(tb, y, width, "bsdinfo  " & system.os.hostname & "  " &
                             system.os.ostype & " " & system.os.release &
                             "  " & system.os.arch)
  if error.len > 0:
    tb.setForegroundColor(fgRed)
    drawLine(tb, y, width, error)
    tb.setForegroundColor(fgWhite)

  drawTitle(tb, y, width, "CPU")
  drawLine(tb, y, width, system.cpu.model)
  drawLine(tb, y, width, $system.cpu.logicalCount & " logical CPUs    base " &
                             formatMhz(system.cpu.baseClockMhz) & "    tsc " &
                             formatMhz(int(system.cpu.tscFrequencyHz div 1_000_000)))

  let coreHalf = (system.cpu.cores.len + 1) div 2
  drawLine(tb, y, width, coreHeaderCell() & "    " & coreHeaderCell())
  for row in 0 ..< coreHalf:
    var line = coreCell(system.cpu.cores[row], row)
    if row + coreHalf < system.cpu.cores.len:
      line.add "    " & coreCell(system.cpu.cores[row + coreHalf], row + coreHalf)
    drawLine(tb, y, width, line)

  if system.cpu.cores.len == 0:
    drawLine(tb, y, width, "no per-core frequency information")

  drawTitle(tb, y, width, "Graphics")
  if system.gpus.len == 0:
    drawLine(tb, y, width, "no display device detected")
  for gpu in system.gpus:
    drawLine(tb, y, width, gpu.vendorName & "  " & gpu.deviceName & "  (" & gpu.slot & ")")
    if gpu.driver.drmDevice.len > 0:
      drawLine(tb, y, width, "  driver " & driverSummary(gpu.driver))
      drawLine(tb, y, width, "  gpu load " &
        bar(gpu.metrics.loadPercent.float / 100.0, 20) & " " &
        align(formatPercent(gpu.metrics.loadPercent.float), 6))
      if gpu.metrics.vramTotalBytes > 0:
        drawLine(tb, y, width, "  " & vramSummary(gpu.metrics))
      drawLine(tb, y, width, "  " & metricsSummary(gpu.metrics))

  drawTitle(tb, y, width, "Memory")
  drawLine(tb, y, width, "used " & formatBytes(system.memory.usedBytes) & " / " &
                             formatBytes(system.memory.totalBytes) & "  " &
                             formatPercent(system.memory.usedPercent))
  drawLine(tb, y, width, bar(system.memory.usedPercent / 100.0, max(10, width - 2)))
  drawLine(tb, y, width, "active " & formatBytes(system.memory.activeBytes) &
                             "   inactive " & formatBytes(system.memory.inactiveBytes) &
                             "   wired " & formatBytes(system.memory.wiredBytes) &
                             "   free " & formatBytes(system.memory.freeBytes))

  drawTitle(tb, y, width, "Network")
  for iface in system.net.interfaces:
    drawLine(tb, y, width, iface.name &
      (if iface.mac.len > 0: "  " & iface.mac else: "") &
      (if iface.isUp: "  up" else: "  down") &
      (if iface.linkSpeedBps > 0: "  " & formatLinkSpeed(iface.linkSpeedBps) else: ""))
    for address in iface.addresses:
      drawLine(tb, y, width, "  " & address.family & " " & address.address &
                                 "  netmask " & address.netmask)

  if system.net.gateway.len > 0:
    drawLine(tb, y, width, "gateway " & system.net.gateway &
      (if system.net.gatewayInterface.len > 0:
         " via " & system.net.gatewayInterface else: ""))
  else:
    drawLine(tb, y, width, "no default gateway")
  drawLine(tb, y, width, "name servers " & system.net.nameServers.join(", "))

  var maxRate = 1.0
  for rate in system.net.rates:
    if rate.rxBytesPerSec > maxRate:
      maxRate = rate.rxBytesPerSec
    if rate.txBytesPerSec > maxRate:
      maxRate = rate.txBytesPerSec
  for rate in system.net.rates:
    drawLine(tb, y, width, align(rate.name, 8) &
      " rx " & bar(rate.rxBytesPerSec / maxRate, 12) & " " &
      align(formatRate(rate.rxBytesPerSec), 12) &
      "  tx " & bar(rate.txBytesPerSec / maxRate, 12) & " " &
      align(formatRate(rate.txBytesPerSec), 12))

  if system.net.wlanInterfaces.len == 0:
    drawLine(tb, y, width, "no wireless interface")
  for wlan in system.net.wlanInterfaces:
    drawLine(tb, y, width, wlan.name &
      (if wlan.status.len > 0: "  " & wlan.status else: "") &
      (if wlan.ssid.len > 0: "  ssid " & wlan.ssid else: ""))
  for network in system.net.wlanNetworks:
    drawLine(tb, y, width, "  " & network.ssid & "  " & network.bssid &
                               "  ch " & network.channel & "  " & network.rate &
                               "  " & network.signal)

  drawTitle(tb, y, width, "Filesystems")
  for fs in system.disks.fileSystems:
    drawLine(tb, y, width, fs.mountPoint & " (" & fs.fsType & ")  " &
                               formatBytes(fs.usedBytes) & "/" & formatBytes(fs.totalBytes) &
                               "  " & formatPercent(fs.usedPercent) &
                               (if fs.readOnly: " ro" else: ""))
    drawLine(tb, y, width, "  " & bar(fs.usedPercent / 100.0, max(10, width - 4)))

  drawTitle(tb, y, width, "Storage Devices")
  for device in system.disks.devices:
    drawLine(tb, y, width, device.name & "  " & formatBytes(device.mediasizeBytes) &
                               "  " & device.description)

  result = y + scroll

  if int(tb.height) > 1 and width > 0:
    tb.setForegroundColor(fgYellow)
    let footer = "q: quit   up/down/pgup/pgdn: scroll   refresh: 1s"
    tb.write(0, (tb.height - 1).Natural,
             if footer.len > width: footer[0 ..< width] else: footer)
    tb.setForegroundColor(fgNone)

proc runTui*() =
  proc exitProc() {.noconv.} =
    illwillDeinit()
    showCursor()
    quit(0)

  illwillInit(fullscreen = true)
  setControlCHook(exitProc)
  hideCursor()

  var tb = newTerminalBuffer(terminalWidth(), terminalHeight())
  var system: SystemInfo
  var cpuSampler: CpuLoadSampler
  var netSampler: NetLoadSampler
  var error = ""

  proc refresh() =
    try:
      system = collectSystem(cpuSampler, netSampler)
      error = ""
    except SysctlError:
      error = "failed to read system information"

  refresh()

  var running = true
  var ticks = 0
  var scrollY = 0

  while running:
    if tb.width != terminalWidth() or tb.height != terminalHeight():
      tb = newTerminalBuffer(terminalWidth(), terminalHeight())
      scrollY = 0

    tb.clear()
    var total = render(tb, system, error, scrollY)
    let maxScroll = max(0, total - int(tb.height))
    if scrollY > maxScroll:
      scrollY = maxScroll
      tb.clear()
      total = render(tb, system, error, scrollY)
    tb.display()

    case getKey()
    of Key.Escape, Key.Q, Key.CtrlC:
      running = false
    of Key.Up:
      if scrollY > 0:
        dec scrollY
    of Key.Down:
      inc scrollY
    of Key.PageUp:
      scrollY = max(0, scrollY - max(1, int(tb.height) - 1))
    of Key.PageDown:
      scrollY += max(1, int(tb.height) - 1)
    of Key.Home:
      scrollY = 0
    of Key.End:
      scrollY = total
    else:
      discard

    sleep(50)
    inc ticks
    if ticks * 50 >= (RefreshSeconds * 1000.0).int:
      ticks = 0
      refresh()

  illwillDeinit()
  showCursor()
