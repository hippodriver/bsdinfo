## Raw bindings to the FreeBSD `getfsstat` mount-statistics interface.

const MFSNAMELEN = 16
const MNAMELEN = 1024

type
  StatFs* {.importc: "struct statfs", header: "<sys/mount.h>", bycopy.} = object
    ## Only the fields `bsdinfo` reads are declared; the compiler uses the real
    ## C layout (`sizeof` matches `sizeof(struct statfs)` on FreeBSD 15).
    f_flags* {.importc: "f_flags".}: uint64
    f_bsize* {.importc: "f_bsize".}: uint64
    f_blocks* {.importc: "f_blocks".}: uint64
    f_bfree* {.importc: "f_bfree".}: uint64
    f_bavail* {.importc: "f_bavail".}: int64
    f_fstypename* {.importc: "f_fstypename".}: array[MFSNAMELEN, char]
    f_mntfromname* {.importc: "f_mntfromname".}: array[MNAMELEN, char]
    f_mntonname* {.importc: "f_mntonname".}: array[MNAMELEN, char]

var
  MNT_NOWAIT* {.importc, header: "<sys/mount.h>".}: cint
  MNT_RDONLY* {.importc, header: "<sys/mount.h>".}: uint64

proc getfsstat*(buf: ptr StatFs; bufsize: clong; mode: cint): cint
  {.importc, header: "<sys/mount.h>".}
