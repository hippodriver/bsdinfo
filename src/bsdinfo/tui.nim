## Terminal dashboard built with illwill, reusing the shared `SystemInfo`.

import std/[os, strutils]

import illwill

import ./format
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

proc render(tb: var TerminalBuffer; system: SystemInfo; error: string) =
  let width = int(tb.width)
  var y = 0

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

  var maxFreq = 1
  for freq in system.cpu.coreFrequenciesMhz:
    if freq > maxFreq:
      maxFreq = freq
  for idx, freq in system.cpu.coreFrequenciesMhz:
    let name = "cpu" & align($idx, 3)
    drawLine(tb, y, width, name & " " & bar(freq.float / maxFreq.float, 20) & " " &
                               align($freq, 5) & " MHz")

  if system.cpu.coreFrequenciesMhz.len == 0:
    drawLine(tb, y, width, "no per-core frequency information")

  drawTitle(tb, y, width, "Memory")
  drawLine(tb, y, width, "used " & formatBytes(system.memory.usedBytes) & " / " &
                             formatBytes(system.memory.totalBytes) & "  " &
                             formatPercent(system.memory.usedPercent))
  drawLine(tb, y, width, bar(system.memory.usedPercent / 100.0, max(10, width - 2)))
  drawLine(tb, y, width, "active " & formatBytes(system.memory.activeBytes) &
                             "   inactive " & formatBytes(system.memory.inactiveBytes) &
                             "   wired " & formatBytes(system.memory.wiredBytes) &
                             "   free " & formatBytes(system.memory.freeBytes))

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

  drawTitle(tb, y, width, "Graphics")
  if system.gpus.len == 0:
    drawLine(tb, y, width, "no display device detected")
  for gpu in system.gpus:
    drawLine(tb, y, width, gpu.vendorName & "  " & gpu.deviceName & "  (" & gpu.slot & ")")

  if int(tb.height) > 1 and width > 0:
    tb.setForegroundColor(fgYellow)
    let footer = "q: quit   refresh: 1s"
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
  var error = ""

  proc refresh() =
    try:
      system = collectSystem()
      error = ""
    except SysctlError:
      error = "failed to read system information"

  refresh()

  var running = true
  var ticks = 0

  while running:
    if tb.width != terminalWidth() or tb.height != terminalHeight():
      tb = newTerminalBuffer(terminalWidth(), terminalHeight())

    tb.clear()
    render(tb, system, error)
    tb.display()

    case getKey()
    of Key.Escape, Key.Q, Key.CtrlC:
      running = false
    else:
      discard

    sleep(50)
    inc ticks
    if ticks * 50 >= (RefreshSeconds * 1000.0).int:
      ticks = 0
      refresh()

  illwillDeinit()
  showCursor()
