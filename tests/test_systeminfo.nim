import std/unittest

import bsdinfo/[cpu, disk, gpu, memory, net, osinfo, systeminfo]

suite "collectSystem":
  var cpuSampler: CpuLoadSampler
  var netSampler: NetLoadSampler
  let sys = collectSystem(cpuSampler, netSampler)

  test "os panel is populated":
    check sys.os.ostype == "FreeBSD"
    check sys.os.ostype == collectOs().ostype

  test "cpu panel matches the standalone collector":
    var other: CpuLoadSampler
    check sys.cpu.logicalCount > 0
    check sys.cpu.logicalCount == collectCpu(other).logicalCount

  test "memory panel is populated":
    check sys.memory.totalBytes > 0
    check sys.memory.totalBytes == collectMemory().totalBytes

  test "disk panel is populated":
    check sys.disks.fileSystems.len > 0

  test "gpu panel matches the standalone collector":
    check sys.gpus.len == collectGpus().len

  test "network panel is populated":
    check sys.net.interfaces.len > 0
    check sys.net.rates.len == sys.net.interfaces.len
