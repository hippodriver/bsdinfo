## CPU information collected from FreeBSD sysctls.
##
## Frequencies come from `dev.cpu.N.freq`; per-core load is derived from
## `kern.cp_times`. Because load is a rate, `CpuLoadSampler` keeps the previous
## tick counts between refreshes.

import ./sysctlread

const
  CpuStates* = 5      ## CP_USER, CP_NICE, CP_SYS, CP_INTR, CP_IDLE
  CpuIdleState* = 4   ## index of CP_IDLE within a state vector

type
  CpuCore* = object
    frequencyMhz*: int    ## `dev.cpu.N.freq`
    loadPercent*: float   ## busy time since the previous sample, 0..100

  CpuInfo* = object
    model*: string              ## `hw.model`
    logicalCount*: int          ## `hw.ncpu`
    baseClockMhz*: int          ## `hw.clockrate`
    tscFrequencyHz*: uint64     ## `machdep.tsc_freq`
    cores*: seq[CpuCore]        ## one entry per logical CPU

  CpuLoadSampler* = object
    ## Holds the previous `kern.cp_times` reading so load can be computed as a
    ## delta between refreshes. Reuse one instance across samples.
    prev: seq[array[CpuStates, int64]]
    primed*: bool             ## true once a baseline exists

proc sampleCpuTimes*(): seq[array[CpuStates, int64]] =
  ## Read `kern.cp_times`: one state vector per logical CPU, in the order
  ## `user, nice, sys, intr, idle`. Returns an empty sequence if the sysctl is
  ## unavailable or its length is not a whole number of state vectors.
  let raw = sysctlRaw("kern.cp_times")
  let vectorSize = CpuStates * sizeof(clong)
  if raw.len == 0 or raw.len mod vectorSize != 0:
    return @[]
  let coreCount = raw.len div vectorSize
  var ticks = newSeq[clong](coreCount * CpuStates)
  copyMem(addr ticks[0], unsafeAddr raw[0], raw.len)
  result = newSeq[array[CpuStates, int64]](coreCount)
  for core in 0 ..< coreCount:
    for state in 0 ..< CpuStates:
      result[core][state] = int64(ticks[core * CpuStates + state])

proc coreLoadPercent*(prev, curr: array[CpuStates, int64]): float =
  ## Busy percentage between two tick vectors, clamped to 0..100.
  var prevTotal, currTotal: int64
  for state in 0 ..< CpuStates:
    prevTotal += prev[state]
    currTotal += curr[state]
  let totalDelta = currTotal - prevTotal
  if totalDelta <= 0:
    return 0.0
  let idleDelta = curr[CpuIdleState] - prev[CpuIdleState]
  result = 100.0 * (1.0 - idleDelta.float / totalDelta.float)
  if result < 0.0:
    result = 0.0
  elif result > 100.0:
    result = 100.0

proc sampleLoad*(sampler: var CpuLoadSampler): seq[float] =
  ## Per-core busy percentage since the previous call. The first call (or one
  ## after the CPU count changed) primes the baseline and reports zero.
  let times = sampleCpuTimes()
  if times.len == 0:
    sampler.prev = @[]
    sampler.primed = false
    return
  result = newSeq[float](times.len)
  if sampler.prev.len == times.len:
    for core in 0 ..< times.len:
      result[core] = coreLoadPercent(sampler.prev[core], times[core])
    sampler.primed = true
  else:
    sampler.primed = false
  sampler.prev = times

proc collectCpu*(sampler: var CpuLoadSampler): CpuInfo =
  ## Gather CPU information. Throws `SysctlError` only if `hw.model` or
  ## `hw.ncpu` is unavailable; other fields fall back to zero.
  result.model = sysctlString("hw.model")
  result.logicalCount = sysctlInt("hw.ncpu")
  result.baseClockMhz = sysctlIntOrDefault("hw.clockrate", 0)
  result.tscFrequencyHz = sysctlU64OrDefault("machdep.tsc_freq", 0)

  let loads = sampleLoad(sampler)
  for cpu in 0 ..< result.logicalCount:
    let freq = sysctlIntOrDefault("dev.cpu." & $cpu & ".freq", 0)
    let load = if cpu < loads.len: loads[cpu] else: 0.0
    result.cores.add CpuCore(frequencyMhz: freq, loadPercent: load)
