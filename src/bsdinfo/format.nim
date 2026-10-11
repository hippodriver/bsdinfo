## Human-readable formatting for display values.

import std/strutils

const ByteUnits = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"]

proc formatBytes*(bytes: uint64): string =
  ## Format a byte count using binary units, e.g. `64.0 GiB`.
  if bytes < 1024:
    return $bytes & " B"
  var value = bytes.float
  var unit = 0
  while value >= 1024.0 and unit < ByteUnits.high:
    value /= 1024.0
    inc unit
  result = formatFloat(value, ffDecimal, 1) & " " & ByteUnits[unit]

proc formatMhz*(mhz: int): string =
  ## Format a frequency given in MHz, switching to GHz above 1000 MHz.
  if mhz >= 1000:
    formatFloat(mhz.float / 1000.0, ffDecimal, 2) & " GHz"
  else:
    $mhz & " MHz"

proc formatPercent*(value: float): string =
  ## Format a percentage with one decimal place, e.g. `42.3%`.
  formatFloat(value, ffDecimal, 1) & "%"
