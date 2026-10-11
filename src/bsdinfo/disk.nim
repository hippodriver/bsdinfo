## Disk information: mounted filesystems (via `getfsstat`) and physical block
## devices (via `geom disk list`).

import std/[osproc, strutils]

import ./statfs

type
  FileSystemInfo* = object
    device*: string
    mountPoint*: string
    fsType*: string
    totalBytes*: uint64
    freeBytes*: uint64
    availBytes*: uint64
    usedBytes*: uint64
    usedPercent*: float
    readOnly*: bool

  DiskDeviceInfo* = object
    name*: string
    description*: string
    mediasizeBytes*: uint64

  DiskInfo* = object
    fileSystems*: seq[FileSystemInfo]
    devices*: seq[DiskDeviceInfo]

proc charArrayToString(buf: openArray[char]): string =
  for c in buf:
    if c == '\0':
      break
    result.add c

proc collectFileSystems*(): seq[FileSystemInfo] =
  ## Enumerate mounted filesystems using `getfsstat(2)`.
  let count = getfsstat(nil, 0, MNT_NOWAIT)
  if count <= 0:
    return @[]

  var stats = newSeq[StatFs](count)
  let used = getfsstat(addr stats[0], clong(count * sizeof(StatFs)), MNT_NOWAIT)
  if used <= 0:
    return @[]

  for i in 0 ..< used:
    let fs = stats[i]
    let blockSize = fs.f_bsize
    let total = fs.f_blocks * blockSize
    let free = fs.f_bfree * blockSize
    let avail = if fs.f_bavail > 0: uint64(fs.f_bavail) * blockSize else: 0'u64
    let usedBytes = if total >= free: total - free else: 0'u64

    result.add FileSystemInfo(
      device: charArrayToString(fs.f_mntfromname),
      mountPoint: charArrayToString(fs.f_mntonname),
      fsType: charArrayToString(fs.f_fstypename),
      totalBytes: total,
      freeBytes: free,
      availBytes: avail,
      usedBytes: usedBytes,
      usedPercent: if total == 0: 0.0
                   else: usedBytes.float / total.float * 100.0,
      readOnly: (fs.f_flags and MNT_RDONLY) != 0
    )

proc parseGeomDiskList(output: string): seq[DiskDeviceInfo] =
  var current: DiskDeviceInfo
  var haveCurrent = false

  for line in output.splitLines():
    if line.startsWith("Geom name: "):
      if haveCurrent:
        result.add current
      current = DiskDeviceInfo(name: line["Geom name: ".len .. ^1].strip())
      haveCurrent = true
    elif haveCurrent:
      let trimmed = line.strip()
      if trimmed.startsWith("Mediasize: "):
        let rest = trimmed["Mediasize: ".len .. ^1]
        let bytesStr = rest.split(' ')[0]
        try:
          current.mediasizeBytes = parseBiggestUInt(bytesStr)
        except ValueError:
          discard
      elif trimmed.startsWith("descr: "):
        current.description = trimmed["descr: ".len .. ^1]

  if haveCurrent:
    result.add current

proc collectDiskDevices*(): seq[DiskDeviceInfo] =
  ## Enumerate physical devices using `geom disk list`.
  try:
    let (output, exitCode) = execCmdEx("/sbin/geom disk list")
    if exitCode == 0:
      result = parseGeomDiskList(output)
  except OSError:
    discard

proc collectDisks*(): DiskInfo =
  ## Gather mounted filesystems and physical devices.
  result.fileSystems = collectFileSystems()
  result.devices = collectDiskDevices()
