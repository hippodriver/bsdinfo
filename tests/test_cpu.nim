import std/unittest

import bsdinfo/cpu
import bsdinfo/sysctlread

suite "collectCpu":
  var sampler: CpuLoadSampler
  let cpu = collectCpu(sampler)

  test "model comes from hw.model":
    check cpu.model.len > 0
    check cpu.model == sysctlString("hw.model")

  test "logical count matches hw.ncpu":
    check cpu.logicalCount > 0
    check cpu.logicalCount == sysctlInt("hw.ncpu")

  test "one core entry per logical CPU":
    check cpu.cores.len == cpu.logicalCount

  test "core frequencies are non-negative":
    for core in cpu.cores:
      check core.frequencyMhz >= 0

  test "the first sample has no load baseline":
    for core in cpu.cores:
      check core.loadPercent == 0.0

suite "coreLoadPercent":
  test "an idle-only delta reports no load":
    let prev: array[CpuStates, int64] = [100'i64, 0, 0, 0, 100]
    let curr: array[CpuStates, int64] = [100, 0, 0, 0, 200]
    check coreLoadPercent(prev, curr) == 0.0

  test "a busy-only delta reports full load":
    let prev: array[CpuStates, int64] = [100'i64, 0, 0, 0, 100]
    let curr: array[CpuStates, int64] = [200, 0, 0, 0, 100]
    check coreLoadPercent(prev, curr) == 100.0

  test "a half-busy delta reports half load":
    let prev: array[CpuStates, int64] = [0'i64, 0, 0, 0, 0]
    let curr: array[CpuStates, int64] = [50, 0, 0, 0, 50]
    check coreLoadPercent(prev, curr) == 50.0

  test "identical samples report no load":
    let ticks: array[CpuStates, int64] = [10'i64, 1, 2, 3, 400]
    check coreLoadPercent(ticks, ticks) == 0.0

  test "the result is clamped to 0..100":
    let prev: array[CpuStates, int64] = [0'i64, 0, 0, 0, 100]
    let curr: array[CpuStates, int64] = [100, 0, 0, 0, 0]
    let load = coreLoadPercent(prev, curr)
    check load >= 0.0
    check load <= 100.0

suite "sampleCpuTimes":
  test "returns one state vector per logical CPU":
    let times = sampleCpuTimes()
    check times.len == sysctlInt("hw.ncpu")

suite "CpuLoadSampler":
  test "the first sample primes the baseline":
    var sampler: CpuLoadSampler
    let loads = sampleLoad(sampler)
    check loads.len == sysctlInt("hw.ncpu")
    check sampler.primed == false
    for load in loads:
      check load == 0.0

  test "the second sample reports a load within range":
    var sampler: CpuLoadSampler
    discard sampleLoad(sampler)
    let loads = sampleLoad(sampler)
    check sampler.primed == true
    for load in loads:
      check load >= 0.0
      check load <= 100.0
