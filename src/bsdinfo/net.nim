## Network information: interfaces and addresses, name servers, the default
## gateway, per-interface throughput and nearby wireless networks.
##
## Interfaces, addresses and byte counters come from `getifaddrs(2)`; name
## servers from `/etc/resolv.conf`; the gateway from `route(8)` and the wireless
## details from `ifconfig(8)`.

import std/[monotimes, osproc, strutils, times]

import ./ifaddrs

type
  IpAddress* = object
    family*: string      ## "inet" or "inet6"
    address*: string
    netmask*: string

  NetInterface* = object
    name*: string
    mac*: string
    flags*: uint32
    mtu*: int
    linkSpeedBps*: uint64
    addresses*: seq[IpAddress]
    rxBytes*: uint64
    txBytes*: uint64

  InterfaceRate* = object
    name*: string
    rxBytesPerSec*: float
    txBytesPerSec*: float

  WlanInterface* = object
    name*: string
    ssid*: string
    status*: string

  WlanNetwork* = object
    ssid*: string
    bssid*: string
    channel*: string
    rate*: string
    signal*: string
    caps*: seq[string]

  NetworkInfo* = object
    interfaces*: seq[NetInterface]
    rates*: seq[InterfaceRate]
    nameServers*: seq[string]
    searchDomains*: seq[string]
    gateway*: string
    gatewayInterface*: string
    wlanInterfaces*: seq[WlanInterface]
    wlanNetworks*: seq[WlanNetwork]

  NetCounters = tuple[name: string, rx: uint64, tx: uint64]

  NetLoadSampler* = object
    ## Holds the previous per-interface byte counters and the sample time so
    ## throughput can be computed as a delta between refreshes.
    prev: seq[NetCounters]
    lastSample: MonoTime
    primed*: bool

proc isUp*(iface: NetInterface): bool =
  (iface.flags and uint32(IFF_UP)) != 0

proc isRunning*(iface: NetInterface): bool =
  (iface.flags and uint32(IFF_RUNNING)) != 0

proc isLoopback*(iface: NetInterface): bool =
  (iface.flags and uint32(IFF_LOOPBACK)) != 0

proc sockAddrToString(sa: ptr IfSockAddr): string =
  if sa == nil:
    return ""
  var buf: array[128, char]
  if getnameinfo(sa, cuint(sa.sa_len), addr buf[0], cuint(buf.len), nil, 0,
                 NI_NUMERICHOST) != 0:
    return ""
  result = $cast[cstring](addr buf[0])

proc linkAddress(sa: ptr IfSockAddr): string =
  ## MAC address from an `AF_LINK` `struct sockaddr_dl`.
  if sa == nil:
    return ""
  let dl = cast[ptr IfSockAddrDl](sa)
  if dl.sdl_alen == 0:
    return ""
  let start = int(dl.sdl_nlen)
  let stop = min(start + int(dl.sdl_alen), dl.sdl_data.len)
  for i in start ..< stop:
    if i > start:
      result.add ':'
    result.add toHex(byte(dl.sdl_data[i]), 2).toLowerAscii()

proc collectInterfaces*(): seq[NetInterface] =
  ## Enumerate interfaces with their addresses, MAC and counters.
  var head: ptr IfAddrs
  if getifaddrs(addr head) != 0:
    return @[]
  defer: freeifaddrs(head)

  var it = head
  while it != nil:
    let name = if it.ifa_name != nil: $it.ifa_name else: ""
    var index = -1
    for i in 0 ..< result.len:
      if result[i].name == name:
        index = i
        break
    if index < 0:
      result.add NetInterface(name: name, flags: uint32(it.ifa_flags))
      index = result.len - 1

    if it.ifa_addr != nil:
      let family = int(it.ifa_addr.sa_family)
      if family == int(AF_LINK):
        result[index].mac = linkAddress(it.ifa_addr)
        if it.ifa_data != nil:
          let data = cast[ptr IfData](it.ifa_data)
          result[index].mtu = int(data.ifi_mtu)
          result[index].linkSpeedBps = data.ifi_baudrate
          result[index].rxBytes = data.ifi_ibytes
          result[index].txBytes = data.ifi_obytes
      elif family == int(AF_INET) or family == int(AF_INET6):
        let address = sockAddrToString(it.ifa_addr)
        if address.len > 0:
          result[index].addresses.add IpAddress(
            family: if family == int(AF_INET): "inet" else: "inet6",
            address: address,
            netmask: sockAddrToString(it.ifa_netmask))

    it = it.ifa_next

proc parseResolvConf*(content: string):
    tuple[nameServers, searchDomains: seq[string]] =
  ## Extract `nameserver`, `search` and `domain` lines from `resolv.conf`.
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line[0] in {'#', ';'}:
      continue
    let fields = line.splitWhitespace()
    if fields.len < 2:
      continue
    case fields[0]
    of "nameserver":
      result.nameServers.add fields[1]
    of "search":
      for i in 1 ..< fields.len:
        result.searchDomains.add fields[i]
    of "domain":
      result.searchDomains.add fields[1]
    else:
      discard

proc collectNameServers*(): tuple[nameServers, searchDomains: seq[string]] =
  ## Read `/etc/resolv.conf`; returns empty sequences if it is missing.
  try:
    result = parseResolvConf(readFile("/etc/resolv.conf"))
  except IOError, OSError:
    discard

proc parseRouteGetDefault*(output: string):
    tuple[gateway, interfaceName: string] =
  ## Extract `gateway:` and `interface:` from `route -n get default`.
  for line in output.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("gateway:"):
      result.gateway = trimmed["gateway:".len .. ^1].strip()
    elif trimmed.startsWith("interface:"):
      result.interfaceName = trimmed["interface:".len .. ^1].strip()

proc collectGateway*(): tuple[gateway, interfaceName: string] =
  ## Read the default route using `route(8)`.
  try:
    let (output, exitCode) = execCmdEx("/sbin/route -n get default")
    if exitCode == 0:
      result = parseRouteGetDefault(output)
  except OSError:
    discard

const IfNameChars = {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '.', '_'}

proc isSafeIfName(name: string): bool =
  if name.len == 0 or name.len > 32:
    return false
  for c in name:
    if c notin IfNameChars:
      return false
  true

proc looksLikeBssid(field: string): bool =
  if field.len != 17:
    return false
  for i, c in field:
    if i mod 3 == 2:
      if c != ':':
        return false
    elif c notin {'0' .. '9', 'a' .. 'f', 'A' .. 'F'}:
      return false
  true

proc parseIfconfigStatus*(output: string): tuple[ssid, status: string] =
  ## Extract the `ssid` and `status` lines from `ifconfig <wlan>`.
  for line in output.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("status:"):
      result.status = trimmed["status:".len .. ^1].strip()
    elif trimmed.startsWith("ssid "):
      let fields = trimmed["ssid ".len .. ^1].splitWhitespace()
      if fields.len > 0:
        result.ssid = fields[0]

proc parseIfconfigScan*(output: string): seq[WlanNetwork] =
  ## Parse `ifconfig <wlan> list scan` into one entry per access point. The
  ## display columns are `SSID BSSID CHAN RATE S:N INT CAPS...`.
  for line in output.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0 or trimmed.startsWith("SSID"):
      continue
    let fields = trimmed.splitWhitespace()
    var bssidAt = -1
    for i, field in fields:
      if looksLikeBssid(field):
        bssidAt = i
        break
    if bssidAt < 0:
      continue
    var network = WlanNetwork(
      ssid: fields[0 ..< bssidAt].join(" "),
      bssid: fields[bssidAt])
    if bssidAt + 1 < fields.len:
      network.channel = fields[bssidAt + 1]
    if bssidAt + 2 < fields.len:
      network.rate = fields[bssidAt + 2]
    if bssidAt + 3 < fields.len:
      network.signal = fields[bssidAt + 3]
    if bssidAt + 5 < fields.len:
      network.caps = fields[bssidAt + 5 .. ^1]
    result.add network

proc collectWlan*(interfaces: seq[NetInterface]):
    tuple[wlanInterfaces: seq[WlanInterface], wlanNetworks: seq[WlanNetwork]] =
  ## Describe the `wlanN` clone interfaces and their cached scan results. The
  ## scan is not initiated here, so this needs no privileges.
  for iface in interfaces:
    if not iface.name.startsWith("wlan") or not isSafeIfName(iface.name):
      continue
    var wlan = WlanInterface(name: iface.name)
    try:
      let (statusOut, statusCode) = execCmdEx("/sbin/ifconfig " & iface.name)
      if statusCode == 0:
        let status = parseIfconfigStatus(statusOut)
        wlan.ssid = status.ssid
        wlan.status = status.status
      let (scanOut, scanCode) =
        execCmdEx("/sbin/ifconfig " & iface.name & " list scan")
      if scanCode == 0:
        result.wlanNetworks.add parseIfconfigScan(scanOut)
    except OSError:
      discard
    result.wlanInterfaces.add wlan

proc sampleRates*(sampler: var NetLoadSampler;
                  interfaces: seq[NetInterface]): seq[InterfaceRate] =
  ## Per-interface throughput since the previous call. The first call (or one
  ## after the interface set changed) primes the baseline and reports zero.
  result = newSeq[InterfaceRate](interfaces.len)
  let now = getMonoTime()

  var baseline = sampler.prev.len == interfaces.len
  if baseline:
    for i, iface in interfaces:
      if sampler.prev[i].name != iface.name:
        baseline = false
        break

  if not baseline:
    sampler.prev = newSeq[NetCounters](interfaces.len)
    for i, iface in interfaces:
      sampler.prev[i] = (iface.name, iface.rxBytes, iface.txBytes)
      result[i] = InterfaceRate(name: iface.name)
    sampler.lastSample = now
    sampler.primed = false
    return

  var seconds = (now - sampler.lastSample).inNanoseconds.float / 1_000_000_000.0
  if seconds <= 0.0:
    seconds = 1.0
  for i, iface in interfaces:
    let previous = sampler.prev[i]
    let rxDelta = if iface.rxBytes >= previous.rx: iface.rxBytes - previous.rx
                  else: 0'u64
    let txDelta = if iface.txBytes >= previous.tx: iface.txBytes - previous.tx
                  else: 0'u64
    result[i] = InterfaceRate(name: iface.name,
                              rxBytesPerSec: rxDelta.float / seconds,
                              txBytesPerSec: txDelta.float / seconds)
    sampler.prev[i] = (iface.name, iface.rxBytes, iface.txBytes)
  sampler.lastSample = now
  sampler.primed = true

proc collectNetwork*(sampler: var NetLoadSampler): NetworkInfo =
  ## Gather every network panel. Best-effort: missing utilities leave the
  ## corresponding field empty.
  result.interfaces = collectInterfaces()
  result.rates = sampleRates(sampler, result.interfaces)

  let nameServers = collectNameServers()
  result.nameServers = nameServers.nameServers
  result.searchDomains = nameServers.searchDomains

  let gateway = collectGateway()
  result.gateway = gateway.gateway
  result.gatewayInterface = gateway.interfaceName

  let wlan = collectWlan(result.interfaces)
  result.wlanInterfaces = wlan.wlanInterfaces
  result.wlanNetworks = wlan.wlanNetworks
