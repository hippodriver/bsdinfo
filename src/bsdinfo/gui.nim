## Graphical dashboard built with owlkettle (GTK4 + cairo).

import std/[math, strutils]

import owlkettle
import owlkettle/cairo

import ./cpu
import ./format
import ./gpu
import ./net
import ./sysctlread
import ./systeminfo

type NetSample* = tuple[rx, tx: float]

const NetHistoryLength = 60

viewable App:
  system: SystemInfo
  cpuSampler: CpuLoadSampler
  netSampler: NetLoadSampler
  netHistory: seq[NetSample]
  tab: int = 0
  loaded: bool = false
  error: string = ""
  timer: EventDescriptor
  refreshMs: int = 2000

proc drawNetHistory(ctx: CairoContext; size: (int, int); history: seq[NetSample]) =
  let
    w = size[0].float
    h = size[1].float

  ctx.setSource(0.12, 0.12, 0.14, 1.0)
  ctx.rectangle(0.0, 0.0, w, h)
  ctx.fill()

  if history.len < 2:
    return

  var peak = 1.0
  for sample in history:
    if sample.rx > peak:
      peak = sample.rx
    if sample.tx > peak:
      peak = sample.tx

  let step = w / float(history.len - 1)

  ctx.setSource(0.20, 0.78, 0.45, 1.0)
  ctx.lineWidth = 2.0
  for i in 0 ..< history.len:
    let x = float(i) * step
    let y = h - (history[i].rx / peak) * (h - 4.0) - 2.0
    if i == 0:
      ctx.moveTo(x, y)
    else:
      ctx.lineTo(x, y)
  ctx.stroke()

  ctx.setSource(0.35, 0.60, 0.95, 1.0)
  ctx.lineWidth = 2.0
  for i in 0 ..< history.len:
    let x = float(i) * step
    let y = h - (history[i].tx / peak) * (h - 4.0) - 2.0
    if i == 0:
      ctx.moveTo(x, y)
    else:
      ctx.lineTo(x, y)
  ctx.stroke()

proc refreshSystem(app: AppState) =
  app.system = collectSystem(app.cpuSampler, app.netSampler)
  var rx = 0.0
  var tx = 0.0
  for rate in app.system.net.rates:
    rx += rate.rxBytesPerSec
    tx += rate.txBytesPerSec
  app.netHistory.add (rx: rx, tx: tx)
  while app.netHistory.len > NetHistoryLength:
    app.netHistory.delete(0)

method view(app: AppState): Widget =
  if not app.loaded:
    app.loaded = true
    try:
      refreshSystem(app)
    except SysctlError:
      app.error = "failed to read system information"

  if app.timer.isNil:
    app.timer = addGlobalTimeout(app.refreshMs, proc(): bool =
      try:
        refreshSystem(app)
        app.error = ""
      except SysctlError:
        app.error = "failed to read system information"
      discard app.redraw()
      result = true
    )

  var maxRate = 1.0
  for rate in app.system.net.rates:
    if rate.rxBytesPerSec > maxRate:
      maxRate = rate.rxBytesPerSec
    if rate.txBytesPerSec > maxRate:
      maxRate = rate.txBytesPerSec

  let cpuHalf = (app.system.cpu.cores.len + 1) div 2

  result = gui:
    Window:
      title = "bsdinfo"
      defaultSize = (960, 720)

      Box:
        orient = OrientY

        Box {.expand: false.}:
          orient = OrientX
          spacing = 0
          margin = Margin(top: 12, bottom: 0, left: 12, right: 12)
          style = StyleClass("linked")
          ToggleButton {.expand: false.}:
            text = "System"
            state = app.tab == 0
            proc changed(state: bool) =
              if state:
                app.tab = 0
          ToggleButton {.expand: false.}:
            text = "Storage"
            state = app.tab == 1
            proc changed(state: bool) =
              if state:
                app.tab = 1
          ToggleButton {.expand: false.}:
            text = "Network"
            state = app.tab == 2
            proc changed(state: bool) =
              if state:
                app.tab = 2

        ScrolledWindow:
          propagateNaturalHeight = true
          Box:
            orient = OrientY
            spacing = 12
            margin = Margin(top: 6, bottom: 12, left: 12, right: 12)

            if app.error.len > 0:
              Label(text = app.error)

            if app.tab == 0:
              Frame:
                label = "Operating System"
                Box:
                  orient = OrientY
                  spacing = 2
                  Label(text = app.system.os.ostype & " " & app.system.os.release)
                  Label(text = "host " & app.system.os.hostname & "    arch " & app.system.os.arch)
                  Label(text = app.system.os.version)

              Frame:
                label = "CPU"
                Box:
                  orient = OrientY
                  spacing = 4
                  Label(text = app.system.cpu.model)
                  Label(text = $app.system.cpu.logicalCount & " logical CPUs    base " &
                               formatMhz(app.system.cpu.baseClockMhz))
                  Box:
                    orient = OrientX
                    spacing = 24
                    Label {.expand: false.}:
                      text = "core"
                      xAlign = 0.0
                      sizeRequest = (48, -1)
                      style = StyleClass("dim-label")
                    Label {.expand: false.}:
                      text = "frequency"
                      xAlign = 1.0
                      sizeRequest = (90, -1)
                      style = StyleClass("dim-label")
                    Label {.expand: true.}:
                      text = "load"
                      xAlign = 0.0
                      style = StyleClass("dim-label")
                    Label {.expand: false.}:
                      text = "core"
                      xAlign = 0.0
                      sizeRequest = (48, -1)
                      style = StyleClass("dim-label")
                    Label {.expand: false.}:
                      text = "frequency"
                      xAlign = 1.0
                      sizeRequest = (90, -1)
                      style = StyleClass("dim-label")
                    Label {.expand: true.}:
                      text = "load"
                      xAlign = 0.0
                      style = StyleClass("dim-label")
                  for row in 0 ..< cpuHalf:
                    Box:
                      orient = OrientX
                      spacing = 24
                      Label {.expand: false.}:
                        text = "cpu" & $row
                        xAlign = 0.0
                        sizeRequest = (48, -1)
                      Label {.expand: false.}:
                        text = formatMhz(app.system.cpu.cores[row].frequencyMhz)
                        xAlign = 1.0
                        sizeRequest = (90, -1)
                      Box {.expand: true.}:
                        orient = OrientX
                        spacing = 6
                        LevelBar {.expand: true.}:
                          min = 0.0
                          max = 100.0
                          value = app.system.cpu.cores[row].loadPercent
                          sizeRequest = (0, 16)
                        Label:
                          text = formatPercent(app.system.cpu.cores[row].loadPercent)
                          xAlign = 1.0
                          sizeRequest = (64, -1)
                      if row + cpuHalf < app.system.cpu.cores.len:
                        Label {.expand: false.}:
                          text = "cpu" & $(row + cpuHalf)
                          xAlign = 0.0
                          sizeRequest = (48, -1)
                        Label {.expand: false.}:
                          text = formatMhz(app.system.cpu.cores[row + cpuHalf].frequencyMhz)
                          xAlign = 1.0
                          sizeRequest = (90, -1)
                        Box {.expand: true.}:
                          orient = OrientX
                          spacing = 6
                          LevelBar {.expand: true.}:
                            min = 0.0
                            max = 100.0
                            value = app.system.cpu.cores[row + cpuHalf].loadPercent
                            sizeRequest = (0, 16)
                          Label:
                            text = formatPercent(app.system.cpu.cores[row + cpuHalf].loadPercent)
                            xAlign = 1.0
                            sizeRequest = (64, -1)
                      else:
                        Label {.expand: false.}:
                          text = ""
                          sizeRequest = (48, -1)
                        Label {.expand: false.}:
                          text = ""
                          sizeRequest = (90, -1)
                        Label {.expand: true.}:
                          text = ""

              Frame:
                label = "Graphics"
                Box:
                  orient = OrientY
                  spacing = 6
                  if app.system.gpus.len == 0:
                    Label(text = "no display device detected")
                  for gpu in app.system.gpus:
                    Box:
                      orient = OrientY
                      spacing = 2
                      Label(text = gpu.vendorName & "  " & gpu.deviceName &
                                   "  (" & gpu.slot & ")")
                      if gpu.driver.drmDevice.len > 0:
                        Label(text = "driver " & driverSummary(gpu.driver))
                        Box:
                          orient = OrientX
                          spacing = 6
                          Label {.expand: false.}:
                            text = "gpu load"
                            xAlign = 0.0
                            sizeRequest = (90, -1)
                            style = StyleClass("dim-label")
                          LevelBar {.expand: true.}:
                            min = 0.0
                            max = 100.0
                            value = float(gpu.metrics.loadPercent)
                            sizeRequest = (0, 16)
                          Label:
                            text = formatPercent(float(gpu.metrics.loadPercent))
                            xAlign = 1.0
                            sizeRequest = (64, -1)
                        if gpu.metrics.vramTotalBytes > 0:
                          Box:
                            orient = OrientX
                            spacing = 6
                            Label {.expand: false.}:
                              text = "memory"
                              xAlign = 0.0
                              sizeRequest = (90, -1)
                              style = StyleClass("dim-label")
                            LevelBar {.expand: true.}:
                              min = 0.0
                              max = float(max(gpu.metrics.vramTotalBytes, 1'u64))
                              value = float(gpu.metrics.vramUsedBytes)
                              sizeRequest = (0, 16)
                            Label:
                              text = vramSummary(gpu.metrics)
                              xAlign = 1.0
                              sizeRequest = (260, -1)
                        Label(text = metricsSummary(gpu.metrics))

              Frame:
                label = "Memory"
                Box:
                  orient = OrientX
                  spacing = 12
                  DrawingArea:
                    proc draw(ctx: CairoContext, size: (int, int)): bool =
                      let
                        w = size[0].float
                        h = size[1].float
                        cx = w / 2.0
                        cy = h / 2.0
                        radius = min(w, h) * 0.38
                        startAngle = degToRad(135.0)
                        stopAngle = degToRad(405.0)

                      var fraction = app.system.memory.usedPercent / 100.0
                      if fraction < 0.0:
                        fraction = 0.0
                      elif fraction > 1.0:
                        fraction = 1.0

                      ctx.setSource(0.12, 0.12, 0.14, 1.0)
                      ctx.rectangle(0.0, 0.0, w, h)
                      ctx.fill()

                      ctx.arc(cx, cy, radius, startAngle, stopAngle)
                      ctx.lineWidth = 12.0
                      ctx.lineCap = LineCapRound
                      ctx.setSource(0.30, 0.30, 0.34, 1.0)
                      ctx.stroke()

                      ctx.arc(cx, cy, radius, startAngle,
                              startAngle + (stopAngle - startAngle) * fraction)
                      ctx.lineWidth = 12.0
                      ctx.lineCap = LineCapRound
                      ctx.source = (0.20, 0.78, 0.45, 1.0)
                      ctx.stroke()

                      ctx.selectFontFace("Sans", FontSlantNormal, FontWeightBold)
                      ctx.fontSize = 22.0
                      let label = formatPercent(app.system.memory.usedPercent)
                      let extents = ctx.textExtents(label)
                      ctx.moveTo(cx - extents.width / 2.0 - extents.xBearing,
                                 cy + extents.height / 2.0)
                      ctx.text(label)
                      ctx.setSource(1.0, 1.0, 1.0, 1.0)
                      ctx.fill()
                      return false

                  Box:
                    orient = OrientY
                    spacing = 2
                    Label(text = "used " & formatBytes(app.system.memory.usedBytes) &
                                 " / " & formatBytes(app.system.memory.totalBytes))
                    Label(text = "active " & formatBytes(app.system.memory.activeBytes))
                    Label(text = "inactive " & formatBytes(app.system.memory.inactiveBytes))
                    Label(text = "wired " & formatBytes(app.system.memory.wiredBytes))
                    Label(text = "free " & formatBytes(app.system.memory.freeBytes))

            elif app.tab == 1:
              Frame:
                label = "Filesystems"
                Box:
                  orient = OrientY
                  spacing = 6
                  for fs in app.system.disks.fileSystems:
                    Box:
                      orient = OrientY
                      spacing = 2
                      Label(text = fs.mountPoint & "  (" & fs.fsType & ")  " &
                                   formatBytes(fs.usedBytes) & " / " & formatBytes(fs.totalBytes) &
                                   "  " & formatPercent(fs.usedPercent) &
                                   (if fs.readOnly: "  [ro]" else: ""))
                      LevelBar:
                        value = fs.usedPercent / 100.0
                        min = 0.0
                        max = 1.0

              Frame:
                label = "Storage Devices"
                Box:
                  orient = OrientY
                  spacing = 2
                  for device in app.system.disks.devices:
                    Label(text = device.name & "  " & formatBytes(device.mediasizeBytes) &
                                 "  " & device.description)

            else:
              Frame:
                label = "Interfaces"
                Box:
                  orient = OrientY
                  spacing = 6
                  for iface in app.system.net.interfaces:
                    Box:
                      orient = OrientY
                      spacing = 2
                      Label(text = iface.name &
                                   (if iface.mac.len > 0: "  " & iface.mac else: "") &
                                   (if iface.isUp: "  up" else: "  down") &
                                   (if iface.linkSpeedBps > 0:
                                      "  " & formatLinkSpeed(iface.linkSpeedBps) else: "") &
                                   (if iface.mtu > 0: "  mtu " & $iface.mtu else: ""))
                      if iface.addresses.len == 0:
                        Label(text = "  no address")
                      for address in iface.addresses:
                        Label(text = "  " & address.family & " " & address.address &
                                     "  netmask " & address.netmask)

              Frame:
                label = "Gateway and Name Servers"
                Box:
                  orient = OrientY
                  spacing = 2
                  if app.system.net.gateway.len == 0:
                    Label(text = "no default gateway")
                  else:
                    Label(text = "gateway " & app.system.net.gateway &
                                 (if app.system.net.gatewayInterface.len > 0:
                                    "  via " & app.system.net.gatewayInterface else: ""))
                  Label(text = "name servers " &
                               app.system.net.nameServers.join(", "))
                  if app.system.net.searchDomains.len > 0:
                    Label(text = "search " & app.system.net.searchDomains.join(", "))

              Frame:
                label = "Interface Load"
                Box:
                  orient = OrientY
                  spacing = 6
                  DrawingArea {.expand: false.}:
                    sizeRequest = (-1, 80)
                    proc draw(ctx: CairoContext, size: (int, int)): bool =
                      drawNetHistory(ctx, size, app.netHistory)
                      return false
                  Box:
                    orient = OrientX
                    spacing = 6
                    Label {.expand: false.}:
                      text = "interface"
                      xAlign = 0.0
                      sizeRequest = (72, -1)
                      style = StyleClass("dim-label")
                    Label {.expand: true.}:
                      text = "rx"
                      xAlign = 0.0
                      style = StyleClass("dim-label")
                    Label {.expand: true.}:
                      text = "tx"
                      xAlign = 0.0
                      style = StyleClass("dim-label")
                  if app.system.net.rates.len == 0:
                    Label(text = "no interface rate information")
                  for rate in app.system.net.rates:
                    Box:
                      orient = OrientX
                      spacing = 6
                      Label {.expand: false.}:
                        text = rate.name
                        xAlign = 0.0
                        sizeRequest = (72, -1)
                      Box {.expand: true.}:
                        orient = OrientX
                        spacing = 6
                        LevelBar {.expand: true.}:
                          min = 0.0
                          max = maxRate
                          value = rate.rxBytesPerSec
                          sizeRequest = (0, 16)
                        Label {.expand: false.}:
                          text = formatRate(rate.rxBytesPerSec)
                          xAlign = 1.0
                          sizeRequest = (90, -1)
                      Box {.expand: true.}:
                        orient = OrientX
                        spacing = 6
                        LevelBar {.expand: true.}:
                          min = 0.0
                          max = maxRate
                          value = rate.txBytesPerSec
                          sizeRequest = (0, 16)
                        Label {.expand: false.}:
                          text = formatRate(rate.txBytesPerSec)
                          xAlign = 1.0
                          sizeRequest = (90, -1)

              Frame:
                label = "Wireless"
                Box:
                  orient = OrientY
                  spacing = 2
                  if app.system.net.wlanInterfaces.len == 0:
                    Label(text = "no wireless interface")
                  for wlan in app.system.net.wlanInterfaces:
                    Label(text = wlan.name &
                                 (if wlan.status.len > 0: "  " & wlan.status else: "") &
                                 (if wlan.ssid.len > 0: "  ssid " & wlan.ssid else: ""))
                  if app.system.net.wlanNetworks.len > 0:
                    Label(text = "available networks")
                  for network in app.system.net.wlanNetworks:
                    Label(text = "  " & network.ssid & "  " & network.bssid &
                                 "  ch " & network.channel & "  " & network.rate &
                                 "  " & network.signal &
                                 (if network.caps.len > 0:
                                    "  " & network.caps.join(" ") else: ""))

proc runGui*() =
  brew(App())
