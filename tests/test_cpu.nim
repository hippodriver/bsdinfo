import std/unittest

import bsdinfo/cpu
import bsdinfo/sysctlread

suite "collectCpu":
  let cpu = collectCpu()

  test "model comes from hw.model":
    check cpu.model.len > 0
    check cpu.model == sysctlString("hw.model")

  test "logical count matches hw.ncpu":
    check cpu.logicalCount > 0
    check cpu.logicalCount == sysctlInt("hw.ncpu")

  test "one core frequency per logical CPU":
    check cpu.coreFrequenciesMhz.len == cpu.logicalCount

  test "core frequencies are non-negative":
    for freq in cpu.coreFrequenciesMhz:
      check freq >= 0
