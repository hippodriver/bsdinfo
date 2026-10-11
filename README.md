# bsdinfo

A FreeBSD system information tool in the spirit of
[CPU-X](https://thetumultuousunicornofdarkness.github.io/CPU-X/): it shows CPU,
memory, disk and GPU information from a graphical GTK4 dashboard or a terminal
UI. Written in Nim, with the data layer kept free of external native
dependencies.

## Features

- Operating system, hostname and architecture identification
- CPU model, logical CPU count, base clock and per-core frequencies
- Physical memory usage (total, used, free, active, inactive, wired)
- Mounted filesystems with usage bars and physical storage devices
- Display controllers (GPU) detected via PCI configuration
- Two frontends over one shared data model:
  - a GTK4 dashboard (owlkettle) with a cairo arc gauge, auto-refreshing
  - a terminal dashboard (illwill) with bars, quitting on `q`
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
| `src/bsdinfo/cpu.nim` | `CpuInfo` + `collectCpu` |
| `src/bsdinfo/memory.nim` | `MemoryInfo` + `collectMemory` |
| `src/bsdinfo/osinfo.nim` | `OsInfo` + `collectOs` |
| `src/bsdinfo/disk.nim` | `DiskInfo` + `collectDisks` |
| `src/bsdinfo/gpu.nim` | `GpuInfo` + `collectGpus` |
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
| GPU | `pciconf -lv` |

See `design.md` for the full plan and implementation notes.

## License

MIT
