## Physical memory information collected from FreeBSD sysctls.

import ./sysctlread

type
  MemoryInfo* = object
    totalBytes*: uint64      ## `hw.physmem` (usable memory)
    realBytes*: uint64       ## `hw.realmem` (total installed memory)
    pageSize*: int           ## `hw.pagesize`
    totalPages*: uint64      ## `vm.stats.vm.v_page_count`
    freeBytes*: uint64
    activeBytes*: uint64
    inactiveBytes*: uint64
    wiredBytes*: uint64
    cachedBytes*: uint64
    usedBytes*: uint64
    usedPercent*: float

proc pagesToBytes(pages: uint64; pageSize: int): uint64 =
  if pageSize <= 0:
    0'u64
  else:
    pages * uint64(pageSize)

proc collectMemory*(): MemoryInfo =
  ## Gather physical memory information. Every field falls back to zero when
  ## its sysctl is unavailable.
  result.totalBytes = sysctlU64OrDefault("hw.physmem", 0)
  result.realBytes = sysctlU64OrDefault("hw.realmem", 0)
  result.pageSize = sysctlIntOrDefault("hw.pagesize", 0)

  result.totalPages = uint64(sysctlUintOrDefault("vm.stats.vm.v_page_count", 0))

  let freePages = uint64(sysctlUintOrDefault("vm.stats.vm.v_free_count", 0))
  result.freeBytes = pagesToBytes(freePages, result.pageSize)
  result.activeBytes =
    pagesToBytes(uint64(sysctlUintOrDefault("vm.stats.vm.v_active_count", 0)),
                 result.pageSize)
  result.inactiveBytes =
    pagesToBytes(uint64(sysctlUintOrDefault("vm.stats.vm.v_inactive_count", 0)),
                 result.pageSize)
  result.wiredBytes =
    pagesToBytes(uint64(sysctlUintOrDefault("vm.stats.vm.v_wire_count", 0)),
                 result.pageSize)
  result.cachedBytes =
    pagesToBytes(uint64(sysctlUintOrDefault("vm.stats.vm.v_cache_count", 0)),
                 result.pageSize)

  if result.totalBytes >= result.freeBytes:
    result.usedBytes = result.totalBytes - result.freeBytes
  else:
    result.usedBytes = 0

  if result.totalBytes == 0:
    result.usedPercent = 0.0
  else:
    result.usedPercent = result.usedBytes.float / result.totalBytes.float * 100.0
