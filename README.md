# bsdinfo

A FreeBSD system information tool in the spirit of
[CPU-X](https://thetumultuousunicornofdarkness.github.io/CPU-X/): it shows CPU,
memory, disk and GPU information from a graphical GTK4 dashboard or a terminal
UI. Written in Nim, with the data layer kept free of external native
dependencies.

## Features

- Operating system, hostname and architecture identification
- CPU model, logical CPU count, base clock, and per-core frequency and load
  (cores listed two per row in both frontends, under `core` / `frequency` /
  `load` column headers)
- Physical memory usage (total, used, free, active, inactive, wired)
- Mounted filesystems with usage bars and physical storage devices
- Network interfaces with their addresses and MAC, name servers, the default
  gateway, per-interface throughput and nearby wireless networks
- Display controllers (GPU) from PCI configuration, plus per-GPU load, VRAM
  usage and driver/firmware details (fan speed is not exposed by drm-kmod 3.54,
  so it is shown as `n/a`)
- Two frontends over one shared data model:
  - a GTK4 dashboard (owlkettle) with a cairo arc gauge, a throughput
    sparkline and tabs (`System`, `Storage`, `Network`), auto-refreshing
  - a terminal dashboard (illwill) with bars and scrollback, quitting on `q`
- XFCE application-menu integration via desktop entries

## Requirements

- FreeBSD (developed against 15.1)
- Nim 2.0 or newer
- [Atlas](https://nim-lang.org/docs/atlas.html) for dependency management
- GTK4 and cairo at build time for the GUI (`pkg-config --libs gtk4 cairo`)

The data layer needs no libraries beyond libc. GPU and storage-device details
come from the base-system `pciconf(8)` and `geom(8)` utilities.

## Build and run

```sh
atlas install                 # fetch dependencies (illwill, owlkettle)
nim c --out:bsdinfo src/bsdinfo.nim

./bsdinfo                     # graphical dashboard (default)
./bsdinfo --tui               # terminal dashboard
```

## Install with XFCE integration

```sh
./packaging/install.sh            # installs into ~/.local
PREFIX=/usr/local ./packaging/install.sh   # or a system prefix
```

This builds a release binary, installs it, and registers `bsdinfo` and
`bsdinfo (Terminal)` in the XFCE application menu (System / Monitor category).

## Testing

```sh
nim c -r tests/test_sysctl.nim
nim c -r tests/test_cpu.nim
nim c -r tests/test_memory.nim
nim c -r tests/test_osinfo.nim
nim c -r tests/test_disk.nim
nim c -r tests/test_gpu.nim
nim c -r tests/test_net.nim
nim c -r tests/test_systeminfo.nim
nim c -r tests/test_format.nim
```

## Architecture

The data layer is frontend-agnostic. Each panel exposes a plain `object` model
plus a `collectX` proc; `collectSystem` aggregates them into a `SystemInfo`.

| Module | Responsibility |
|--------|----------------|
| `src/bsdinfo/sysctl.nim` | Raw libc `sysctl` / `sysctlbyname` FFI |
| `src/bsdinfo/sysctlread.nim` | Typed, error-reporting sysctl accessors |
| `src/bsdinfo/statfs.nim` | Raw `getfsstat` / `struct statfs` FFI |
| `src/bsdinfo/ifaddrs.nim` | Raw `getifaddrs` / `struct if_data` FFI |
| `src/bsdinfo/amdgpu_drm.nim` | Raw `DRM_IOCTL_AMDGPU_INFO` FFI |
| `src/bsdinfo/cpu.nim` | `CpuInfo` + `collectCpu` |
| `src/bsdinfo/memory.nim` | `MemoryInfo` + `collectMemory` |
| `src/bsdinfo/osinfo.nim` | `OsInfo` + `collectOs` |
| `src/bsdinfo/disk.nim` | `DiskInfo` + `collectDisks` |
| `src/bsdinfo/gpu.nim` | `GpuInfo` + `collectGpus` |
| `src/bsdinfo/net.nim` | `NetworkInfo` + `collectNetwork` |
| `src/bsdinfo/systeminfo.nim` | `SystemInfo` + `collectSystem` |
| `src/bsdinfo/format.nim` | Human-readable byte / MHz / percent formatting |
| `src/bsdinfo/gui.nim` | owlkettle GTK4 dashboard |
| `src/bsdinfo/tui.nim` | illwill terminal dashboard |
| `src/bsdinfo.nim` | Entry point and frontend selection |

### Data sources

| Panel | Source |
|-------|--------|
| CPU | `hw.model`, `hw.ncpu`, `hw.clockrate`, `machdep.tsc_freq`, `dev.cpu.N.freq` |
| Memory | `hw.physmem`, `hw.pagesize`, `vm.stats.vm.v_*_count` |
| OS | `kern.ostype`, `kern.osrelease`, `kern.version`, `kern.hostname`, `uname(2)` |
| Filesystems | `getfsstat(2)` |
| Storage devices | `geom disk list` |
| GPU devices | `pciconf -lv` |
| GPU load / VRAM / clocks | `sys.device.drmnN.*`, `DRM_IOCTL_AMDGPU_INFO` |
| GPU driver / firmware | `vbios_version`, `fw_version.*`, `kern.msgbuf` |
| Network interfaces, IPs, MAC | `getifaddrs(2)` |
| Interface throughput | `struct if_data` counters, delta between samples |
| Name servers | `/etc/resolv.conf` |
| Default gateway | `route -n get default` |
| Wireless networks | `ifconfig <wlan> list scan` |

See `design.md` for the full plan and implementation notes.

## License

MIT
