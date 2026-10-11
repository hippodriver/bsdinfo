## Typed, error-reporting accessors over the raw `sysctl` bindings.
##
## Required lookups (`sysctlString`, `sysctlInt`, `sysctlUint`, `sysctlU64`)
## raise `SysctlError` when the name is unknown or unreadable. Optional lookups
## use the `*OrDefault` variants or `hasSysctl` for a membership test.

import std/posix

import ./sysctl

type
  SysctlError* = object of CatchableError

proc raiseSysctl(name: string; code: cint) {.noinline, noreturn.} =
  let detail = if code == 0: "not found" else: $strerror(code)
  raise newException(SysctlError, "sysctl '" & name & "': " & detail)

proc sizeOfSysctl(name: string): csize_t =
  var len: csize_t = 0
  if sysctlbyname(name.cstring, nil, addr len, nil, 0) != 0:
    raiseSysctl(name, errno)
  result = len

proc hasSysctl*(name: string): bool =
  ## True when `name` resolves to a readable sysctl.
  var len: csize_t = 0
  sysctlbyname(name.cstring, nil, addr len, nil, 0) == 0

proc sysctlString*(name: string): string =
  ## Read a sysctl that returns a NUL-terminated string.
  var len = sizeOfSysctl(name)
  if len == 0:
    return ""
  result = newString(len)
  if sysctlbyname(name.cstring, result[0].addr, addr len, nil, 0) != 0:
    raiseSysctl(name, errno)
  result.setLen(len)
  while result.len > 0 and result[^1] == '\0':
    result.setLen(result.len - 1)

proc sysctlInt*(name: string): int =
  ## Read a sysctl backed by a C `int`.
  var value: cint
  var len = csize_t(sizeof(value))
  if sysctlbyname(name.cstring, addr value, addr len, nil, 0) != 0:
    raiseSysctl(name, errno)
  result = int(value)

proc sysctlUint*(name: string): uint =
  ## Read a sysctl backed by a C `unsigned int`.
  var value: cuint
  var len = csize_t(sizeof(value))
  if sysctlbyname(name.cstring, addr value, addr len, nil, 0) != 0:
    raiseSysctl(name, errno)
  result = uint(value)

proc sysctlU64*(name: string): uint64 =
  ## Read a sysctl backed by a 64-bit unsigned integer.
  var value: uint64
  var len = csize_t(sizeof(value))
  if sysctlbyname(name.cstring, addr value, addr len, nil, 0) != 0:
    raiseSysctl(name, errno)
  result = value

proc sysctlStringOrDefault*(name: string; default = ""): string =
  ## Optional lookup: return `default` when `name` is unreadable.
  try:
    sysctlString(name)
  except SysctlError:
    default

proc sysctlIntOrDefault*(name: string; default = 0): int =
  ## Optional lookup: return `default` when `name` is unreadable.
  try:
    sysctlInt(name)
  except SysctlError:
    default

proc sysctlU64OrDefault*(name: string; default = 0'u64): uint64 =
  ## Optional lookup: return `default` when `name` is unreadable.
  try:
    sysctlU64(name)
  except SysctlError:
    default

proc sysctlUintOrDefault*(name: string; default: uint = 0): uint =
  ## Optional lookup: return `default` when `name` is unreadable.
  try:
    sysctlUint(name)
  except SysctlError:
    default
