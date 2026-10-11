## Aggregate of every hardware and software panel.

import ./cpu
import ./disk
import ./gpu
import ./memory
import ./osinfo

type
  SystemInfo* = object
    os*: OsInfo
    cpu*: CpuInfo
    memory*: MemoryInfo
    disks*: DiskInfo
    gpus*: seq[GpuInfo]

proc collectSystem*(): SystemInfo =
  ## Collect every panel. Raises `SysctlError` if a required core sysctl
  ## (`kern.ostype`, `kern.osrelease`, `hw.model`, `hw.ncpu`) is unavailable.
  result.os = collectOs()
  result.cpu = collectCpu()
  result.memory = collectMemory()
  result.disks = collectDisks()
  result.gpus = collectGpus()
