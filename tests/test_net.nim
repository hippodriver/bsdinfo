import std/unittest

import bsdinfo/net

suite "collectInterfaces":
  let interfaces = collectInterfaces()

  test "at least one interface is present":
    check interfaces.len > 0

  test "interface names are non-empty":
    for iface in interfaces:
      check iface.name.len > 0

  test "the loopback interface is present and up":
    var foundLoopback = false
    for iface in interfaces:
      if iface.isLoopback:
        foundLoopback = true
        check iface.isUp
    check foundLoopback

  test "at least one interface has an address":
    var foundAddress = false
    for iface in interfaces:
      if iface.addresses.len > 0:
        foundAddress = true
    check foundAddress

  test "addresses are well formed":
    for iface in interfaces:
      for address in iface.addresses:
        check address.family in ["inet", "inet6"]
        check address.address.len > 0

suite "parseResolvConf":
  test "reads nameservers, search and domain lines":
    let conf = "# comment\n" &
               "nameserver 192.168.1.1\n" &
               "nameserver 8.8.8.8   # inline comment\n" &
               "search example.com lan\n" &
               "domain local\n"
    let parsed = parseResolvConf(conf)
    check parsed.nameServers == @["192.168.1.1", "8.8.8.8"]
    check parsed.searchDomains == @["example.com", "lan", "local"]

  test "ignores blank and comment lines":
    let parsed = parseResolvConf("\n;\nnameserver 10.0.0.1\n")
    check parsed.nameServers == @["10.0.0.1"]

  test "collectNameServers matches the real file":
    let parsed = collectNameServers()
    check parsed.nameServers == parseResolvConf(readFile("/etc/resolv.conf")).nameServers

suite "parseRouteGetDefault":
  test "extracts the gateway and interface":
    let output = "   route to: default\n" &
                 "destination: default\n" &
                 "       mask: default\n" &
                 "    gateway: 192.168.1.1\n" &
                 "  interface: igc0\n" &
                 "      flags: <UP,GATEWAY,DONE,STATIC>\n"
    let parsed = parseRouteGetDefault(output)
    check parsed.gateway == "192.168.1.1"
    check parsed.interfaceName == "igc0"

suite "parseIfconfigStatus":
  test "extracts the ssid and status":
    let output = "wlan0: flags=8843<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST> mtu 1500\n" &
                 "\tether 00:11:22:33:44:55\n" &
                 "\tstatus: associated\n" &
                 "\tssid mywifi channel 6 (2437 MHz 11g) bssid 00:11:22:33:44:55\n"
    let status = parseIfconfigStatus(output)
    check status.ssid == "mywifi"
    check status.status == "associated"

suite "parseIfconfigScan":
  test "parses one entry per access point":
    let output = "SSID/MESH ID    BSSID              CHAN RATE   S:N     INT CAPS\n" &
                 "mywifi          00:11:22:33:44:55    6   54M  -45:-96  100 EP   RSN WPA\n" &
                 "Neighbour       66:77:88:99:aa:bb   11  130M  -70:-96  100 EPS  RSN\n"
    let networks = parseIfconfigScan(output)
    check networks.len == 2
    check networks[0].ssid == "mywifi"
    check networks[0].bssid == "00:11:22:33:44:55"
    check networks[0].channel == "6"
    check networks[0].rate == "54M"
    check networks[0].signal == "-45:-96"
    check networks[0].caps == @["EP", "RSN", "WPA"]
    check networks[1].ssid == "Neighbour"
    check networks[1].caps == @["EPS", "RSN"]

  test "an SSID containing spaces is preserved":
    let output = "SSID/MESH ID    BSSID              CHAN RATE   S:N     INT CAPS\n" &
                 "My Home WiFi    00:11:22:33:44:55    6   54M  -45:-96  100 EP\n"
    let networks = parseIfconfigScan(output)
    check networks.len == 1
    check networks[0].ssid == "My Home WiFi"

  test "an empty scan returns no networks":
    check parseIfconfigScan("").len == 0

suite "NetLoadSampler":
  let interfaces = collectInterfaces()

  test "the first sample primes the baseline":
    var sampler: NetLoadSampler
    let rates = sampleRates(sampler, interfaces)
    check rates.len == interfaces.len
    check sampler.primed == false
    for i, rate in rates:
      check rate.name == interfaces[i].name
      check rate.rxBytesPerSec == 0.0
      check rate.txBytesPerSec == 0.0

  test "a second sample reports non-negative rates":
    var sampler: NetLoadSampler
    discard sampleRates(sampler, interfaces)
    let rates = sampleRates(sampler, interfaces)
    check sampler.primed == true
    for rate in rates:
      check rate.rxBytesPerSec >= 0.0
      check rate.txBytesPerSec >= 0.0

suite "collectNetwork":
  test "aggregates interfaces, rates, gateway and nameservers":
    var sampler: NetLoadSampler
    let net = collectNetwork(sampler)
    check net.interfaces.len > 0
    check net.rates.len == net.interfaces.len
    check net.nameServers == collectNameServers().nameServers
    check net.gateway == collectGateway().gateway
