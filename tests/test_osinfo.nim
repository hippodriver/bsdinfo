import std/unittest

import std/posix_utils

import bsdinfo/osinfo
import bsdinfo/sysctlread

suite "collectOs":
  let os = collectOs()

  test "ostype is FreeBSD":
    check os.ostype == "FreeBSD"
    check os.ostype == sysctlString("kern.ostype")

  test "release matches kern.osrelease":
    check os.release.len > 0
    check os.release == sysctlString("kern.osrelease")

  test "version is populated":
    check os.version.len > 0

  test "hostname is populated":
    check os.hostname.len > 0

  test "arch is populated":
    check os.arch.len > 0

  test "uname agrees on arch on this platform":
    check os.arch == uname().machine
