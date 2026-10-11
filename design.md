# Features

- Similar to https://thetumultuousunicornofdarkness.github.io/CPU-X/
- FreeBSD lead platform
- Should display system hardware info
- Should display system software operating system info
- display in tui
- integrate into xfce
- Cover: CPU, GPU, memory, disk space

# Tech Stack

- FreeBSD https://www.freebsd.org/
- Nim https://nim-lang.org/
- Atlas instead of nimble
- git
- Recognize skills in ~/.agents/skills/

# AI Strategy

- produce a plan first
- Select libraries to use
- Go step by step
- Extend this document if appropriate

# Plan

## Target environment (verified on this machine)

- FreeBSD 15.1-RELEASE-p4, amd64, `lang/nim` 2.2.12, Atlas 0.14.5.
- Intel Core i5-10400, 12 logical CPUs, ~64 GiB RAM, AMD Radeon RX 6600 GPU.
- Available data sources: `sysctl(8)`, `pciconf(8)` (no `libpci` on this box),
  `geom(8)` + `libgeom.so`, `df(1)`, `/usr/include/sys/mount.h`,
  `/usr/include/sys/sysctl.h`.

## Library selection

| Concern | Choice | Why |
|---------|--------|-----|
| GUI (XFCE integration) | `owlkettle` (github.com/can-lehmann/owlkettle) | Declarative pure-Nim DSL over GTK4; built and ran on this FreeBSD 15.1/XFCE box with no new packages; `LevelBar`/`ProgressBar` plus cairo `DrawingArea` for gauges |
| TUI (optional frontend) | `illwill` (github.com/johnnovak/illwill) | Pure Nim, zero C deps, POSIX path compiles on FreeBSD; immediate-mode canvas fits a CPU-X style dashboard |
| Dependency manager | Atlas | Project requirement; replaces Nimble's global path |
| CPU/memory/OS data | libc `sysctl`/`sysctlbyname` via hand-written FFI | `sysctl` lives in libc, no extra library; typed access to every `hw.*` and `vm.stats.*` oid |
| Disk space | libc `getfsstat(2)` / `statfs` via FFI (`sys/mount.h`) | Native, no subprocess; same data `df(1)` reports |
| GPU | `pciconf -lv` subprocess | No `libpci` available; `pciconf` ships in the base system |
| Disk devices (models/sizes) | `geom disk list` subprocess | Simple and stable; `libgeom` FFI is a later stretch goal |
| OS/software info | `std/posix` `uname` + `kern.*` sysctls | Stdlib already binds `uname`; `kern.osrelease`/`kern.version` add detail |
| Tests | `std/unittest` | Stdlib, no dependency |

Rationale: the data layer stays free of external native library dependencies so
it builds with only Nim + Atlas. The two subprocess sources (`pciconf`, `geom`)
are read-only diagnostics already present in a FreeBSD base install. The GUI
uses GTK4 (already installed, not an XFCE-specific library) via owlkettle; the
data model is frontend-agnostic so a TUI can reuse it.

### GUI options evaluated (verified on this machine)

| Option | Type | Build on FreeBSD | Custom gauges | Verdict |
|--------|------|------------------|---------------|---------|
| **owlkettle** | Pure Nim DSL over GTK4 + cairo | Verified: build + run OK, no new packages | `DrawingArea` + cairo, `LevelBar`, `ProgressBar` | **Chosen** |
| NiGui | Pure Nim, GTK3 via `dlopen` | Verified: compiles with no config | `Canvas` (rect/line/text only, no arcs) | Backup; WIP, minimal widgets, untested on BSD upstream |
| ImGui (`nimgl/imgui`) | Immediate-mode C++, `nim cpp` | Needs `glfw` (not installed) + GL 3.3 core context | Best (draw list + plot helpers) | Rejected: extra C++/GL deps and plumbing |
| fidget / windy | Pure Nim X11/GL | fidget broken (staticglfw); windy needs a `defined(freebsd)` patch | Full control via pixie | Rejected: patched fork required |

owlkettle notes: needs `gtk4`, `cairo`, and `pkg-config` at compile time; does
*not* need gobject-introspection at build or runtime. `libadwaita` is optional
(only when importing `owlkettle/adw`). No other Nimble dependencies.

## Data source map

| Panel | Source |
|-------|--------|
| CPU model | `hw.model` |
| CPU count | `hw.ncpu` |
| CPU base/boost clock | `hw.clockrate`, `machdep.tsc_freq` |
| CPU per-core freq | `dev.cpu.N.freq` (N = 0..ncpu-1) |
| Total/real memory | `hw.physmem`, `hw.realmem`, `hw.pagesize` |
| Memory in use/free | `vm.stats.vm.v_{active,inactive,wire,free,cache,page}_count` * pagesize |
| OS name/release/version | `kern.ostype`, `kern.osrelease`, `kern.version` |
| Hostname / arch | `kern.hostname`, `uname(2)` machine + `hw.machine` |
| GPU | `pciconf -lv` VGA/display class entries (vendor + device strings) |
| Disk devices | `geom disk list` (name, mediasize, descr) |
| Disk space | `getfsstat(2)` per mounted filesystem (total/used/avail) |

## Module layout (one responsibility per module, narrow exports)

```text
bsdinfo/
  bsdinfo.nimble          # package metadata + Atlas requirements
  atlas.lock              # pinned dependency checkouts
  README.md               # usage, build, install, architecture
  LICENSE                 # MIT
  atlas.config / deps/     # Atlas workspace
  src/
    bsdinfo.nim            # main entry: collect + run TUI
    bsdinfo/
      sysctl.nim           # raw libc sysctl / sysctlbyname FFI
      sysctlread.nim       # typed helpers: sysctlStr / sysctlInt / sysctlU64
      statfs.nim           # raw getfsstat / struct statfs FFI
      cpu.nim              # CpuInfo + collectCpu
      memory.nim           # MemoryInfo + collectMemory
      osinfo.nim           # OsInfo + collectOs
      disk.nim             # DiskInfo + collectDisks (geom + getfsstat)
      gpu.nim              # GpuInfo + collectGpus (pciconf)
      systeminfo.nim       # SystemInfo aggregate + collectSystem
      format.nim           # human-readable bytes / MHz / percent formatting
      gui.nim              # owlkettle app: renders SystemInfo (primary UI)
      tui.nim              # optional illwill rendering of SystemInfo
  tests/
    test_sysctl.nim        # FFI round-trips against known sysctl values
    test_collect.nim       # collectors return sane, non-empty data
  packaging/
    bsdinfo.desktop        # XFCE launcher (starts the GUI)
```

`bsdinfo.nim` selects the frontend (`--tui` for the terminal UI, GUI by
default). Both frontends consume the same `SystemInfo` value.

Public surface per panel: a plain `object` model plus a `collectX(): TXxx`
proc that raises on hard failure and returns best-effort partial data otherwise.

## Step-by-step milestones

1. **Scaffold** - `bsdinfo.nimble`, `atlas init`, add `illwill`, dir layout,
   confirm an empty illwill fullscreen canvas compiles and runs.
2. **sysctl FFI** - `sysctl.nim` + `sysctlread.nim`, unit tests for known oids.
3. **CPU** - `cpu.nim` (model, counts, clocks, per-core freq) + tests.
4. **Memory** - `memory.nim` (total/used/free/percent) + tests.
5. **OS info** - `osinfo.nim` (ostype, release, version, hostname, arch).
6. **Disk** - `disk.nim`: `getfsstat` for space, `geom disk list` for devices.
7. **GPU** - `gpu.nim`: parse `pciconf -lv` display entries.
8. **Aggregate** - `systeminfo.nim` ties panels together.
9. **GUI** - `gui.nim`: owlkettle dashboard (paneled boxes, LevelBar/ProgressBar
   meters, cairo arc gauges), periodic refresh via a GLib timer.
10. **TUI (optional)** - `tui.nim`: illwill paneled dashboard, quit key.
11. **XFCE integration** - `bsdinfo.desktop` entry launching the GUI + install notes.
12. **Polish** - README, `atlas pin`, full test pass.

Each milestone ends with a compile + test run.

## Status

- [x] 1. Scaffold. `bsdinfo.nimble` + `atlas init` + `atlas install` resolved
  `illwill 0.4.1` and `owlkettle 3.1.0`. `src/bsdinfo.nim`, `src/bsdinfo/gui.nim`,
  `src/bsdinfo/tui.nim` stub frontends compile; GUI launches on `:0.0`, TUI
  renders under a pty.
- [x] 2. sysctl FFI. `src/bsdinfo/sysctl.nim` (raw `sysctl`/`sysctlbyname`),
  `src/bsdinfo/sysctlread.nim` (typed `sysctlString`/`Int`/`Uint`/`U64` raising
  `SysctlError`, plus `hasSysctl` and `*OrDefault` optional lookups). 13 tests in
  `tests/test_sysctl.nim` pass.
- [x] 3. CPU. `src/bsdinfo/cpu.nim` exposes `CpuInfo` (model, logical count,
  base clock, TSC frequency, per-core frequencies) and `collectCpu`; covered by
  `tests/test_cpu.nim`.
- [x] 4. Memory. `src/bsdinfo/memory.nim` exposes `MemoryInfo` (total/real
  bytes, page size, page count, free/active/inactive/wired/cached bytes,
  used bytes and percent) and `collectMemory`; covered by `tests/test_memory.nim`.
- [x] 5. OS info. `src/bsdinfo/osinfo.nim` exposes `OsInfo` (ostype, release,
  version, hostname, arch) and `collectOs`, falling back to `uname(2)`; covered
  by `tests/test_osinfo.nim`.
- [x] 6. Disk. `src/bsdinfo/statfs.nim` binds `getfsstat`/`struct statfs`;
  `src/bsdinfo/disk.nim` exposes `DiskInfo` (mounted filesystems with
  total/free/avail/used bytes and percent, and physical devices from
  `geom disk list`) via `collectDisks`; covered by `tests/test_disk.nim`.
- [x] 7. GPU. `src/bsdinfo/gpu.nim` exposes `GpuInfo` and `collectGpus`, parsing
  `pciconf -lv` and keeping only display-class (0x03) devices; `parsePciconfLv`
  is covered by `tests/test_gpu.nim`.
- [x] 8. Aggregate. `src/bsdinfo/systeminfo.nim` exposes `SystemInfo` and
  `collectSystem`, tying every panel together; covered by
  `tests/test_systeminfo.nim`.
- [x] 9. GUI. `src/bsdinfo/gui.nim` is an owlkettle dashboard (OS, CPU with
  per-core frequency bars, memory with a cairo arc gauge, filesystems, storage
  devices, graphics panels) that refreshes every 2 s via `addGlobalTimeout`.
  `src/bsdinfo/format.nim` adds display formatting (`tests/test_format.nim`).
  Window verified to map at 960x720.
- [x] 10. TUI. `src/bsdinfo/tui.nim` is an illwill dashboard reusing
  `SystemInfo` (header, CPU with per-core bars, memory bar and breakdown,
  filesystems, storage devices, graphics), refreshing every 1 s and quitting on
  `q`/Escape. Verified under a pty at 46x120.
- [x] 11. XFCE integration. `packaging/bsdinfo.desktop` (GUI) and
  `packaging/bsdinfo-tui.desktop` (terminal) menu entries plus
  `packaging/install.sh`, which builds a release binary, installs it under a
  prefix (default `~/.local`), rewrites `Exec` to the absolute path, and
  refreshes the desktop database. Both entries pass `desktop-file-validate`.
- [x] 12. Polish. `README.md`, `LICENSE` (MIT), and `atlas.lock` (pins
  illwill @ 99a120f7 and owlkettle @ edc52563). Full suite passes (51 tests)
  and the release build succeeds; project diagnostics are clean.


### Build and run

```sh
atlas install               # materialize deps/ and nim.cfg
nim c --out:bsdinfo src/bsdinfo.nim
./bsdinfo                   # GUI (default)
./bsdinfo --tui             # terminal UI
./packaging/install.sh      # install GUI + XFCE menu entries (~/.local)
nim c -r tests/test_sysctl.nim   # unit tests
nim c -r tests/test_cpu.nim      # unit tests
nim c -r tests/test_memory.nim   # unit tests
nim c -r tests/test_osinfo.nim   # unit tests
nim c -r tests/test_disk.nim     # unit tests
nim c -r tests/test_gpu.nim      # unit tests
nim c -r tests/test_systeminfo.nim  # unit tests
nim c -r tests/test_format.nim      # unit tests
```

 
