import std/unittest

import bsdinfo/memory
import bsdinfo/sysctlread

suite "collectMemory":
  let mem = collectMemory()

  test "total matches hw.physmem":
    check mem.totalBytes > 0
    check mem.totalBytes == sysctlU64("hw.physmem")

  test "page size is positive":
    check mem.pageSize > 0

  test "total pages match the vm sysctl":
    check mem.totalPages == uint64(sysctlUint("vm.stats.vm.v_page_count"))

  test "used plus free equals total":
    check mem.usedBytes + mem.freeBytes == mem.totalBytes

  test "used percent is within range":
    check mem.usedPercent >= 0.0
    check mem.usedPercent <= 100.0
