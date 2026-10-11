## CPU information collected from FreeBSD sysctls.

import ./sysctlread

type
  CpuInfo* = object
    model*: string              ## `hw.model`
    logicalCount*: int          ## `hw.ncpu`
    baseClockMhz*: int          ## `hw.clockrate`
    tscFrequencyHz*: uint64     ## `machdep.tsc_freq`
    coreFrequenciesMhz*: seq[int]  ## `dev.cpu.N.freq`, one entry per logical CPU

proc collectCpu*(): CpuInfo =
  ## Gather CPU information. Throws `SysctlError` only if `hw.model` or
  ## `hw.ncpu` is unavailable; other fields fall back to zero.
  result.model = sysctlString("hw.model")
  result.logicalCount = sysctlInt("hw.ncpu")
  result.baseClockMhz = sysctlIntOrDefault("hw.clockrate", 0)
  result.tscFrequencyHz = sysctlU64OrDefault("machdep.tsc_freq", 0)

  for cpu in 0 ..< result.logicalCount:
    let freq = sysctlIntOrDefault("dev.cpu." & $cpu & ".freq", 0)
    result.coreFrequenciesMhz.add freq
