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
| CPU per-core load | `kern.cp_times` delta between samples |
| Total/real memory | `hw.physmem`, `hw.realmem`, `hw.pagesize` |
| Memory in use/free | `vm.stats.vm.v_{active,inactive,wire,free,cache,page}_count` * pagesize |
| OS name/release/version | `kern.ostype`, `kern.osrelease`, `kern.version` |
| Hostname / arch | `kern.hostname`, `uname(2)` machine + `hw.machine` |
| GPU | `pciconf -lv` VGA/display class entries (vendor + device strings) |
| Disk devices | `geom disk list` (name, mediasize, descr) |
| Disk space | `getfsstat(2)` per mounted filesystem (total/used/avail) |
| Network interfaces, IPs, MAC | `getifaddrs(2)` |
| Interface throughput / speed | `struct if_data` in the `AF_LINK` `ifa_data`, delta between samples |
| Name servers / search domains | `/etc/resolv.conf` |
| Default gateway | `route -n get default` |
| Wireless networks | `ifconfig <wlan> list scan` (cached results, no root) |

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
      ifaddrs.nim          # raw getifaddrs / struct if_data FFI
      amdgpu_drm.nim       # raw DRM_IOCTL_AMDGPU_INFO FFI
      cpu.nim              # CpuInfo + collectCpu
      memory.nim           # MemoryInfo + collectMemory
      osinfo.nim           # OsInfo + collectOs
      disk.nim             # DiskInfo + collectDisks (geom + getfsstat)
      gpu.nim              # GpuInfo + collectGpus (pciconf)
      net.nim              # NetworkInfo + collectNetwork (getifaddrs, route, ifconfig)
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
- [x] 13. CPU load and frequency detail. `sysctlread.nim` gains `sysctlRaw`;
  `cpu.nim` adds a per-core `CpuCore` model, `CpuLoadSampler`, `kern.cp_times`
  decoding (`sampleCpuTimes`, `coreLoadPercent`, `sampleLoad`), and replaces
  `coreFrequenciesMhz` with `cores`; `collectCpu`/`collectSystem` take the
  sampler. The GUI lists the cores two per row (left half then right half) and
  the TUI does the same, both under a header row labelling the core, frequency
  and load columns; the frequency is a numeric readout and the load is a bar plus
  percentage. Full suite passes (60 tests).
- [x] 14. GUI tabs. The owlkettle dashboard splits into a `System` tab
  (operating system, CPU, memory, graphics) and a `Storage` tab (filesystems,
  storage devices), selected by a linked `ToggleButton` strip above a shared
  `ScrolledWindow`. owlkettle ships no notebook/stack widget, so the tab state
  is a plain `int` on `AppState` and each toggle sets it.
- [x] 15. Network tab. `ifaddrs.nim` binds `getifaddrs` / `struct if_data`;
  `net.nim` adds `NetworkInfo`, `collectNetwork`, the `NetLoadSampler` throughput
  sampler and the `parseResolvConf` / `parseRouteGetDefault` / `parseIfconfigScan`
  parsers. The GUI gains a `Network` tab (interfaces, gateway and name servers,
  rx/tx bars with a cairo sparkline, wireless); the TUI gains a `Network`
  section and becomes scrollable. Covered by `tests/test_net.nim`. Full suite
  passes (80 tests).
- [x] 16. GPU details. `amdgpu_drm.nim` binds `DRM_IOCTL_AMDGPU_INFO`; `gpu.nim`
  adds `GpuMetrics` (load, VRAM used/total, temperature, power, clocks) and
  `GpuDriverInfo` (driver version, vbios, SMC firmware, power state), collected
  from `sys.device.drmnN.*` and the DRM render node, with `parseAmdgpuVersion`
  and `parseCurrentClock` parsers. The Graphics panel shows load and memory bars
  plus a sensor line; fan speed reads `n/a`. Covered by `tests/test_gpu.nim`.
  Full suite passes (96 tests).
- [ ] 16. GPU details (planned, see "GPU details" below). Per-GPU load, VRAM
  usage, driver/firmware info and fan speed.


## CPU load and frequency detail

Status: implemented. `src/bsdinfo/cpu.nim` exposes `CpuCore`, `CpuLoadSampler`,
`sampleCpuTimes`, `coreLoadPercent` and `sampleLoad`; `sysctlread.nim` gained
`sysctlRaw`. Both frontends list the cores as rows under a header row labelling
the core, frequency and load columns; the frequency is a numeric readout and the
load is a bar plus percentage. Covered by `tests/test_cpu.nim` (13 tests) and an
updated `tests/test_systeminfo.nim`.

Goal: show live per-core utilisation next to per-core frequency, each with a
numeric readout, and a bar for the load.

### Data source (verified on this machine)

- `kern.cp_times` returns `hw.ncpu * CPUSTATES` C `long` values (8 bytes each
  on amd64), CPU-major, state order `CP_USER, CP_NICE, CP_SYS, CP_INTR,
  CP_IDLE` (`/usr/include/sys/resource.h`). 12 CPUs read back as 480 bytes.
- Per-core busy fraction comes from two samples an interval apart:
  `busy = 1 - idleDelta / totalDelta`.
- `dev.cpu.N.freq` already supplies the current per-core MHz.

### Data layer

1. `sysctlread.nim`: add `sysctlRaw*(name): seq[byte]`, an untyped bulk read
   for array-valued oids. The existing typed helpers stay unchanged.
2. `cpu.nim`:
   - Add `CpuStates = 5` / `CpuIdleState = 4` constants and a
     `CpuLoadSampler*` object holding the previous per-core idle and total
     tick counts plus a `primed` flag.
   - Add `sampleCpuTimes(): seq[array[CpuStates, int64]]` decoding the raw
     bytes into per-core tick arrays, validating `len == ncpu * CpuStates`.
   - Add `sampleLoad(s: var CpuLoadSampler): seq[float]` returning the
     per-core busy percentage since the previous call; the first call primes
     the baseline and reports zeros.
   - Replace `CpuInfo.coreFrequenciesMhz` with a per-core record
     `CpuCore* = object` carrying `frequencyMhz*: int` and
     `loadPercent*: float`, as `CpuInfo.cores*: seq[CpuCore]`.
3. `systeminfo.nim`: `collectSystem*(sampler: var CpuLoadSampler)` threads the
   sampler through so both frontends share one delta state.

### Frontends

- `gui.nim`: `AppState` keeps a `CpuLoadSampler` across the existing 2 s
  `addGlobalTimeout` refresh. The CPU panel is a header row plus one row per pair
  of cores (the left half of the cores first, then the right half): `cpuN` label,
  the frequency as text (`formatMhz`), a load bar (`LevelBar`, 0..100) and the
  load as text (`formatPercent`), repeated twice per row. Fixed-width columns so
  the header and the numbers line up.
- `tui.nim`: one line per core (now two cores per line, laid out as `coreCell`
  pairs built from `coreHeaderCell`), reusing the existing `bar`.

### Tests

- `test_cpu.nim`: decode a synthetic `kern.cp_times` buffer (known byte
  layout) and drive a delta through two hand-fed samples; live checks that
  `cores.len == hw.ncpu` and every load is within 0..100.
- `test_systeminfo.nim`: update for the sampler-aware `collectSystem`.

### Edge cases

- First refresh has no baseline: report 0% until the second tick.
- CPUs may appear or disappear: reallocate when `ncpu` or the array length
  changes.
- Counter wrap: compute deltas on unsigned values and clamp to 0..100.

## Network tab

Status: implemented. A third GUI tab (`Network`) plus a matching TUI section show
interfaces and their addresses, name servers and the default gateway,
per-interface throughput with a diagram, and nearby wireless networks. The data
sources below were checked on this machine before implementation.

### Data sources (checked on this machine)

- `getifaddrs(2)` (libc, `<ifaddrs.h>`) lists every interface with its name,
  flags and addresses and, for the `AF_LINK` entry, a `struct if_data` pointer in
  `ifa_data`. Verified here: `igc0` (AF_LINK `18:c0:4d:3a:fc:a3`, inet
  `192.168.1.15`) and `lo0`. Nim's stdlib has no `ifaddrs` binding, so a small
  raw module is needed (same pattern as `sysctl.nim` / `statfs.nim`).
- `struct if_data` (`<net/if.h>`) carries `ifi_ibytes` / `ifi_obytes`,
  `ifi_ipackets` / `ifi_opackets`, `ifi_baudrate` (link speed) and `ifi_mtu`.
  Verified: `igc0` reported `baud=1000000000 ibytes=3005937701 obytes=189132114`.
  Throughput is the delta between two samples, so it needs a sampler like
  `CpuLoadSampler`.
- Name servers and search domains: `/etc/resolv.conf` (`nameserver` / `search`
  lines). Verified: `192.168.1.1`, `8.8.8.8`.
- Default gateway: there is no libc accessor for the routing table; use
  `/sbin/route -n get default` and read the `gateway:` / `interface:` lines
  (read-only, base system). A native `sysctl(NET_RT_DUMP)` parser is a later
  stretch goal.
- Wireless: `net.wlan.devices` names the driver device (`rtwn0` here) and `wlanN`
  clone interfaces appear in `getifaddrs`. Available networks come from
  `ifconfig wlanN list scan`, which shows cached scan results without root
  (`ifconfig wlanN scan` needs super-user, so it is not used). The current
  association (`ssid`, `status`) comes from `ifconfig wlanN` / `list sta`. This
  box has `rtwn0` but no `wlanN` interface yet, so the wireless panel must fall
  back to "no wireless interface" and the scan parser is tested against a
  synthetic sample.

### Module layout

- `src/bsdinfo/ifaddrs.nim` - raw `getifaddrs` / `freeifaddrs` and
  `struct ifaddrs` / `struct if_data` FFI.
- `src/bsdinfo/net.nim` - models plus `collectInterfaces`, `collectNameServers`,
  `collectGateway`, `collectWlan`, `sampleRates`, `collectNetwork`; the pure
  parsers `parseResolvConf`, `parseRouteGetDefault` and `parseIfconfigScan` are
  exported for tests.
- `systeminfo.nim` - `SystemInfo.net` and `collectSystem(cpuSampler, netSampler)`.

### Models

- `NetInterface`: name, mac, flags, up, loopback, mtu, baudrate, addresses,
  rx/tx byte counters.
- `IpAddress`: family (`inet` / `inet6`), address, netmask.
- `InterfaceRate`: name, `rxBytesPerSec`, `txBytesPerSec`.
- `WlanNetwork`: ssid, bssid, channel, rate, signal, caps.
- `NetworkInfo`: interfaces, rates, nameServers, searchDomains, gateway,
  gatewayInterface, wlanInterfaces, wlanNetworks.
- `NetLoadSampler`: previous per-interface rx/tx counters plus a timestamp and a
  `primed` flag (mirrors `CpuLoadSampler`).

### Frontends

- GUI: a third `Network` tab in the tab strip. Panels: interfaces (name, MAC,
  addresses, link speed, up/down), gateway and name servers, per-interface
  throughput (a bar per direction plus numbers, and a cairo `DrawingArea`
  sparkline of the recent history kept in `AppState`), and wireless (associated
  SSID, then scan results with signal and capabilities).
- TUI: a `Network` section with interface lines, gateway and name servers,
  per-interface `rx`/`tx` bars, and the wireless list. Sections are ordered CPU,
  Graphics, Memory, Network, Filesystems, Storage Devices; the CPU section lists
  two cores per row, like the GUI. The whole TUI is scrollable with the arrow
  keys and Page Up/Down (`render` returns the total line count and the caller
  clamps the offset).

### Tests

- `tests/test_net.nim`: live checks (at least one interface, at least one has an
  address, name servers parse, the first rate sample is zero and later samples
  are non-negative), plus parser tests with synthetic input for `resolv.conf`,
  the `route -n get default` output and `ifconfig wlan0 list scan` output.

### Edge cases

- No wireless interface or no cached scan results: empty lists, GUI shows a
  placeholder.
- Interface set changes between samples (e.g. a `wlanN` clone is created):
  re-init the sampler when the name set changes.
- Counter reset or wrap: compute deltas on unsigned values and clamp negatives
  to zero.
- IPv6 link-local addresses carry a `%ifname` scope suffix; keep it as printed.
- `route` or `ifconfig` missing or failing: best-effort empty values, as with
  `pciconf` and `geom`.


## GPU details

Status: implemented. The Graphics panel shows per-GPU load, VRAM usage, driver
and firmware identification, temperature/power/clocks, and a fan field that
reads `n/a` because drm-kmod 3.54 exposes no fan reading. The data sources below
were checked on this machine before implementation.

### Data sources (checked on this machine, RX 6600 / amdgpu)

The card is driven by `amdgpu.ko` + `drm.ko` (drm-kmod 3.54.0), attached as
`drmn0` under `vgapci0`. Two independent sources exist:

- **drm-kmod sysctls** under `sys.device.drmnN.*` (world-readable, no device
  access): `gpu_busy_percent`, `mem_busy_percent`, `pp_dpm_sclk` / `mclk` /
  `fclk` / `socclk` / `dcefclk` / `pcie`, `power_dpm_state`,
  `power_dpm_force_performance_level`, `pp_features`, `pp_cur_state`,
  `vbios_version` (`113-2447LHM-WD1`), and a full `fw_version.*` set (SMC
  `0x003b3200`, SOS, ASD, PFP, ME, MEC, RLC, SDMA, VCN, ...).
- **`DRM_IOCTL_AMDGPU_INFO`** on `/dev/dri/renderD128` (needs `video` group
  membership; this user is in `video`). Verified with a C probe: `MEMORY` gives
  `vram=8573157376` (~7.98 GiB), `cpu_accessible=8528154624`, `gtt=693637120`;
  `VRAM_USAGE` gives `used=693637120` (~661 MiB); `SENSOR` gives `temp=50000`
  (millidegrees C), `load` (percent), `avg_power`, `stable_sclk=1950`,
  `stable_mclk=676`; `FW_VERSION` for SMC matched the sysctl. The ioctl ABI is
  defined by `struct drm_amdgpu_info` (32 bytes) and `DRM_IOCTL_AMDGPU_INFO =
  0x80206445`.
  Note: `/dev/dri/card0` returns `EPERM` for these ioctls while a display server
  holds it; `/dev/dri/renderD128` is the node to use.

- **Load**: `AMDGPU_INFO_SENSOR_GPU_LOAD` (ioctl) or `gpu_busy_percent` (sysctl);
  memory-controller load `mem_busy_percent`.
- **Memory usage**: `AMDGPU_INFO_VRAM_USAGE` (used) + `AMDGPU_INFO_MEMORY`
  (VRAM total, CPU-accessible VRAM, GTT total).
- **Driver info**: `vbios_version`, `fw_version.*`, `power_dpm_state`,
  `pp_features`, the module list (`amdgpu.ko`, `drm.ko`) and the version line
  `Initialized amdgpu 3.54.0 ...` in `kern.msgbuf`.
- **Fan speed**: **not exposed**. `amdgpu_drm.h` has no `FANSPEED` sensor, and
  drm-kmod 3.54 registers no hwmon/fan sysctl on this ASIC (all 48
  `sys.device.drmn0.*` keys were enumerated). Plan: model the field, render
  `n/a` when unset, and leave a hook for a future hwmon/`fan1_input` interface.
- Extra metrics that come for free and are worth showing: GPU temperature,
  average power and the sclk/mclk clocks (skip `SENSOR_GFX_SCLK`, which returned
  a useless `1`; use `stable_sclk` or the `pp_dpm_sclk` sysctl).

### Module layout

- `src/bsdinfo/amdgpu_drm.nim` (raw FFI): the `DRM_IOCTL_AMDGPU_INFO` request
  number, the query and sensor constants, the 32-byte `drm_amdgpu_info` request
  struct and the result structs (`drm_amdgpu_info_vram_gtt`,
  `drm_amdgpu_info_vram_usage`). The constants are hard-coded from the stable DRM
  ABI (documented in `libdrm/amdgpu_drm.h`) so the build keeps needing only libc;
  `ioctl` itself is a libc call.
- `src/bsdinfo/gpu.nim`: extend `GpuInfo` with `GpuMetrics` and `GpuDriverInfo`,
  add `collectGpuMetrics` (ioctl, best-effort when the render node is missing)
  and `collectGpuDriverInfo` (sysctls + `kern.msgbuf`), and a pure
  `parseAmdgpuVersion` parser for the msgbuf line. The `drmnN` unit is found by
  probing `sys.device.drmnN.*` with `hasSysctl`, with `dev.amdgpu.N.*` as a
  fallback for older drm-kmod.

### Frontends

- GUI Graphics panel: per GPU, a load row (`LevelBar` + percent), a memory row
  (VRAM used/total with a bar, plus GTT), a temperature/power/clocks line, a
  fan line showing `n/a`, and driver-info lines (vbios, SMC firmware,
  power state).
- TUI Graphics section: the same values as extra lines.

### Tests

- `tests/test_gpu.nim`: `parseAmdgpuVersion` on a synthetic msgbuf; live checks
  that when a DRM device is found `vramTotal > 0`, `vramUsed <= vramTotal` and
  `temperatureC` is within 0..150 (or 0 when unavailable); the ioctl path
  degrades to zeroed metrics when `/dev/dri/renderD128` cannot be opened.
- `tests/test_format.nim`: keep the byte/percent formatters reused for memory.

### Edge cases

- No `amdgpu`/DRM device (other vendor, or the module is not loaded): the panel
  keeps the existing `pciconf` information and omits the metrics.
- Render node missing or permission denied (user not in `video`): fall back to
  the sysctl-only subset (load, clocks, driver info).
- More than one GPU: `drmnN` is matched per device; the ioctl path queries the
  first render node and is skipped with more than one GPU.
- Sensor unsupported on the ASIC (`GPU_INPUT_POWER` returned `EINVAL` here):
  treat `EINVAL`/`EPERM` as "unavailable", leave the field zero.


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

 
