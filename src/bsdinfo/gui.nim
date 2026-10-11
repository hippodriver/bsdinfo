## Graphical dashboard built with owlkettle (GTK4 + cairo).

import std/math

import owlkettle
import owlkettle/cairo

import ./cpu
import ./format
import ./sysctlread
import ./systeminfo

viewable App:
  system: SystemInfo
  loaded: bool = false
  error: string = ""
  timer: EventDescriptor
  refreshMs: int = 2000

proc maxCoreFrequency(cpu: CpuInfo): int =
  result = 1
  for freq in cpu.coreFrequenciesMhz:
    if freq > result:
      result = freq

method view(app: AppState): Widget =
  if not app.loaded:
    app.loaded = true
    try:
      app.system = collectSystem()
    except SysctlError:
      app.error = "failed to read system information"

  if app.timer.isNil:
    app.timer = addGlobalTimeout(app.refreshMs, proc(): bool =
      try:
        app.system = collectSystem()
        app.error = ""
      except SysctlError:
        app.error = "failed to read system information"
      discard app.redraw()
      result = true
    )

  let maxFreq = maxCoreFrequency(app.system.cpu)

  result = gui:
    Window:
      title = "bsdinfo"
      defaultSize = (960, 720)

      ScrolledWindow:
        propagateNaturalHeight = true
        Box:
          orient = OrientY
          spacing = 12
          margin = 12

          if app.error.len > 0:
            Label(text = app.error)

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
                spacing = 2
                for freq in app.system.cpu.coreFrequenciesMhz:
                  LevelBar:
                    orient = OrientY
                    min = 0.0
                    max = float(maxFreq)
                    value = float(freq)

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

          Frame:
            label = "Graphics"
            Box:
              orient = OrientY
              spacing = 2
              if app.system.gpus.len == 0:
                Label(text = "no display device detected")
              for gpu in app.system.gpus:
                Label(text = gpu.vendorName & "  " & gpu.deviceName & "  (" & gpu.slot & ")")

proc runGui*() =
  brew(App())
