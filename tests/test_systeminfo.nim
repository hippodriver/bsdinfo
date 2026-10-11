import std/unittest

import bsdinfo/[cpu, disk, gpu, memory, osinfo, systeminfo]

suite "collectSystem":
  let sys = collectSystem()

  test "os panel is populated":
    check sys.os.ostype == "FreeBSD"
    check sys.os.ostype == collectOs().ostype

  test "cpu panel matches the standalone collector":
    check sys.cpu.logicalCount > 0
    check sys.cpu.logicalCount == collectCpu().logicalCount

  test "memory panel is populated":
    check sys.memory.totalBytes > 0
    check sys.memory.totalBytes == collectMemory().totalBytes

  test "disk panel is populated":
    check sys.disks.fileSystems.len > 0

  test "gpu panel matches the standalone collector":
    check sys.gpus.len == collectGpus().len
