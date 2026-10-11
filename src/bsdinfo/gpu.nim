## GPU (display controller) information parsed from `pciconf -lv`.
##
## FreeBSD has no `libpci` in the base system, so the PCI configuration is read
## through the `pciconf(8)` utility and only display-class devices (PCI base
## class 0x03) are kept.

import std/[osproc, strutils]

const
  PciDisplayBaseClass = 0x03
  HexDigits = {'0' .. '9', 'a' .. 'f', 'A' .. 'F'}

type
  GpuInfo* = object
    slot*: string        ## PCI location, e.g. `vgapci0@pci0:3:0:0:`
    vendorName*: string  ## vendor string from `pciconf`
    deviceName*: string  ## device string from `pciconf`
    vendorId*: uint16    ## PCI vendor id
    deviceId*: uint16    ## PCI device id
    pciClass*: uint32    ## full PCI class, e.g. 0x030000

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

proc collectGpus*(): seq[GpuInfo] =
  ## Enumerate display devices using `pciconf -lv`. Returns an empty sequence if
  ## the utility is unavailable or reports an error.
  try:
    let (output, exitCode) = execCmdEx("/usr/sbin/pciconf -lv")
    if exitCode == 0:
      result = parsePciconfLv(output)
  except OSError:
    discard
