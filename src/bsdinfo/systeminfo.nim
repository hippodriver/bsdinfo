## Aggregate of every hardware and software panel.

import ./cpu
import ./disk
import ./gpu
import ./memory
import ./net
import ./osinfo

type
  SystemInfo* = object
    os*: OsInfo
    cpu*: CpuInfo
    memory*: MemoryInfo
    disks*: DiskInfo
    gpus*: seq[GpuInfo]
    net*: NetworkInfo

proc collectSystem*(cpuSampler: var CpuLoadSampler;
                    netSampler: var NetLoadSampler): SystemInfo =
  ## Collect every panel. Raises `SysctlError` if a required core sysctl
  ## (`kern.ostype`, `kern.osrelease`, `hw.model`, `hw.ncpu`) is unavailable.
  ## `cpuSampler` and `netSampler` carry load state between refreshes.
  result.os = collectOs()
  result.cpu = collectCpu(cpuSampler)
  result.memory = collectMemory()
  result.disks = collectDisks()
  result.gpus = collectGpus()
  result.net = collectNetwork(netSampler)
