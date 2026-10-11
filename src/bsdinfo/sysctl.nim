## Raw bindings to the FreeBSD libc `sysctl` interface.
##
## This module only imports the C functions; use `sysctlread` for typed,
## error-reporting accessors.

{.push header: "<sys/sysctl.h>".}

proc sysctl*(name: ptr cint, namelen: cuint, oldp: pointer,
             oldlenp: ptr csize_t, newp: pointer,
             newlen: csize_t): cint {.importc.}

proc sysctlbyname*(name: cstring, oldp: pointer, oldlenp: ptr csize_t,
                   newp: pointer, newlen: csize_t): cint {.importc.}

{.pop.}
