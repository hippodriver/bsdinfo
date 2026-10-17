## Raw bindings for the amdgpu `DRM_IOCTL_AMDGPU_INFO` query.
##
## FreeBSD ships no DRM headers in the base system, so the stable DRM ABI values
## are declared here (they match `libdrm/amdgpu_drm.h`): the ioctl request
## number, the query and sensor ids, and the 32-byte `struct drm_amdgpu_info`
## request. Only libc's `open` / `ioctl` are used, so no library is linked.

const
  DrmIoctlAmdgpuInfo* = 0x80206445'u64
    ## `_IOW('d', DRM_COMMAND_BASE + DRM_AMDGPU_INFO, struct drm_amdgpu_info)`.

  AmdgpuInfoVramUsage* = 0x10'u32
  AmdgpuInfoMemory* = 0x19'u32
  AmdgpuInfoSensor* = 0x1D'u32

  AmdgpuSensorGfxSclk* = 0x1'u32
  AmdgpuSensorGfxMclk* = 0x2'u32
  AmdgpuSensorGpuTemp* = 0x3'u32
  AmdgpuSensorGpuLoad* = 0x4'u32
  AmdgpuSensorGpuAvgPower* = 0x5'u32
  AmdgpuSensorStablePstateGfxSclk* = 0x8'u32
  AmdgpuSensorStablePstateGfxMclk* = 0x9'u32

type
  DrmAmdgpuInfo* = object
    ## Layout of `struct drm_amdgpu_info`. The trailing union is 16 bytes, of
    ## which only the first `uint32` (`sensor_info.type`) is used here.
    returnPointer*: uint64
    returnSize*: uint32
    query*: uint32
    inData*: array[16, byte]

  DrmAmdgpuInfoVramGtt* = object
    vramSize*: uint64
    vramCpuAccessibleSize*: uint64
    gttSize*: uint64

const DrmNodes = ["/dev/dri/renderD128", "/dev/dri/card0"]
  ## The render node is preferred: the primary node rejects these queries with
  ## `EPERM` while a display server holds it.

var ORdwr {.importc: "O_RDWR", header: "<fcntl.h>".}: cint

proc c_open(path: cstring, flags: cint): cint
  {.importc: "open", header: "<fcntl.h>", varargs.}

proc c_close(fd: cint): cint
  {.importc: "close", header: "<unistd.h>".}

proc c_ioctl(fd: cint, request: culong): cint
  {.importc: "ioctl", header: "<sys/ioctl.h>", varargs.}

proc openDrmNode*(): cint =
  ## Open the first usable DRM node, or return -1.
  for path in DrmNodes:
    let fd = c_open(path.cstring, ORdwr)
    if fd >= 0:
      return fd
  -1

proc closeDrmNode*(fd: cint) =
  if fd >= 0:
    discard c_close(fd)

proc amdgpuInfo(fd: cint; query: uint32; outPtr: pointer; outSize: uint32;
                in0: uint32 = 0): bool =
  var info: DrmAmdgpuInfo
  info.returnPointer = uint64(cast[uint](outPtr))
  info.returnSize = outSize
  info.query = query
  if in0 != 0:
    cast[ptr uint32](addr info.inData[0])[] = in0
  c_ioctl(fd, DrmIoctlAmdgpuInfo.culong, addr info) == 0

proc queryVramUsage*(fd: cint; usedBytes: var uint64): bool =
  ## Bytes of VRAM currently allocated.
  amdgpuInfo(fd, AmdgpuInfoVramUsage, addr usedBytes, uint32(sizeof(usedBytes)))

proc queryMemory*(fd: cint; memory: var DrmAmdgpuInfoVramGtt): bool =
  ## VRAM, CPU-accessible VRAM and GTT sizes.
  amdgpuInfo(fd, AmdgpuInfoMemory, addr memory, uint32(sizeof(memory)))

proc querySensor*(fd: cint; sensor: uint32; value: var uint32): bool =
  ## One sensor reading, e.g. `AmdgpuSensorGpuTemp` or `AmdgpuSensorGpuLoad`.
  amdgpuInfo(fd, AmdgpuInfoSensor, addr value, uint32(sizeof(value)), sensor)
