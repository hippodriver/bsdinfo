## Operating system identification from `kern.*` sysctls and `uname(2)`.

import std/posix_utils

import ./sysctlread

type
  OsInfo* = object
    ostype*: string      ## `kern.ostype`
    release*: string     ## `kern.osrelease`
    version*: string     ## `kern.version`
    hostname*: string    ## `kern.hostname` (falls back to `uname`)
    arch*: string        ## `hw.machine` (falls back to `uname`)

proc collectOs*(): OsInfo =
  ## Gather OS identification. Raises `SysctlError` if `kern.ostype` or
  ## `kern.osrelease` is unavailable; hostname and arch fall back to `uname(2)`.
  result.ostype = sysctlString("kern.ostype")
  result.release = sysctlString("kern.osrelease")
  result.version = sysctlStringOrDefault("kern.version", "")
  result.hostname = sysctlStringOrDefault("kern.hostname", "")
  result.arch = sysctlStringOrDefault("hw.machine", "")

  if result.hostname.len == 0 or result.arch.len == 0:
    try:
      let u = uname()
      if result.hostname.len == 0:
        result.hostname = u.nodename
      if result.arch.len == 0:
        result.arch = u.machine
    except OSError:
      discard
