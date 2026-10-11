import std/unittest

import bsdinfo/sysctlread

suite "sysctl strings":
  test "kern.ostype is FreeBSD":
    check sysctlString("kern.ostype") == "FreeBSD"

  test "hw.model is non-empty":
    check sysctlString("hw.model").len > 0

  test "kern.osrelease starts with a digit":
    let release = sysctlString("kern.osrelease")
    check release.len > 0
    check release[0] in {'0'..'9'}

suite "sysctl integers":
  test "hw.ncpu is positive":
    check sysctlInt("hw.ncpu") > 0

  test "hw.pagesize is a positive power of two":
    let pageSize = sysctlInt("hw.pagesize")
    check pageSize > 0
    check (pageSize and (pageSize - 1)) == 0

suite "sysctl unsigned":
  test "vm.stats.vm.v_page_count is positive":
    check sysctlUint("vm.stats.vm.v_page_count") > 0

suite "sysctl 64-bit":
  test "hw.physmem is positive":
    check sysctlU64("hw.physmem") > 0

suite "optional lookups":
  test "hasSysctl is true for a known name":
    check hasSysctl("kern.ostype")

  test "hasSysctl is false for an unknown name":
    check not hasSysctl("no.such.oid.bsdinfo")

  test "sysctlIntOrDefault returns the fallback":
    check sysctlIntOrDefault("no.such.oid.bsdinfo", -1) == -1

  test "sysctlStringOrDefault returns the fallback":
    check sysctlStringOrDefault("no.such.oid.bsdinfo", "x") == "x"

suite "error reporting":
  test "sysctlString raises SysctlError":
    expect SysctlError:
      discard sysctlString("no.such.oid.bsdinfo")

  test "sysctlInt raises SysctlError":
    expect SysctlError:
      discard sysctlInt("no.such.oid.bsdinfo")
