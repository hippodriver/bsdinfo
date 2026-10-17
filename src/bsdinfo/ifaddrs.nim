## Raw bindings to the FreeBSD `getifaddrs` interface-listing call.
##
## `getifaddrs` walks every network interface and returns one entry per address
## plus, for the `AF_LINK` entry, a pointer to a `struct if_data` holding the
## byte, packet and link-speed counters.

type
  IfSockAddr* {.importc: "struct sockaddr", header: "<sys/socket.h>", bycopy.} = object
    ## Only the address family is read directly; `getnameinfo` formats addresses.
    sa_len* {.importc: "sa_len".}: uint8
    sa_family* {.importc: "sa_family".}: uint8

  IfSockAddrDl* {.importc: "struct sockaddr_dl", header: "<net/if_dl.h>", bycopy.} = object
    ## Link-level address: `sdl_data` holds the interface name then the hardware
    ## address, each `sdl_nlen` / `sdl_alen` bytes long.
    sdl_len* {.importc: "sdl_len".}: uint8
    sdl_family* {.importc: "sdl_family".}: uint8
    sdl_index* {.importc: "sdl_index".}: uint16
    sdl_type* {.importc: "sdl_type".}: uint8
    sdl_nlen* {.importc: "sdl_nlen".}: uint8
    sdl_alen* {.importc: "sdl_alen".}: uint8
    sdl_slen* {.importc: "sdl_slen".}: uint8
    sdl_data* {.importc: "sdl_data".}: array[46, char]

  IfData* {.importc: "struct if_data", header: "<net/if.h>", bycopy.} = object
    ## Only the fields `bsdinfo` reads are declared; the compiler uses the real
    ## C layout.
    ifi_mtu* {.importc: "ifi_mtu".}: uint32
    ifi_baudrate* {.importc: "ifi_baudrate".}: uint64
    ifi_ipackets* {.importc: "ifi_ipackets".}: uint64
    ifi_opackets* {.importc: "ifi_opackets".}: uint64
    ifi_ibytes* {.importc: "ifi_ibytes".}: uint64
    ifi_obytes* {.importc: "ifi_obytes".}: uint64

  IfAddrs* {.importc: "struct ifaddrs", header: "<ifaddrs.h>", bycopy.} = object
    ifa_next* {.importc: "ifa_next".}: ptr IfAddrs
    ifa_name* {.importc: "ifa_name".}: cstring
    ifa_flags* {.importc: "ifa_flags".}: cuint
    ifa_addr* {.importc: "ifa_addr".}: ptr IfSockAddr
    ifa_netmask* {.importc: "ifa_netmask".}: ptr IfSockAddr
    ifa_ifu* {.importc: "ifa_ifu".}: ptr IfSockAddr
    ifa_data* {.importc: "ifa_data".}: pointer

var
  AF_INET* {.importc, header: "<sys/socket.h>".}: cint
  AF_INET6* {.importc, header: "<sys/socket.h>".}: cint
  AF_LINK* {.importc, header: "<sys/socket.h>".}: cint

  IFF_UP* {.importc, header: "<net/if.h>".}: cuint
  IFF_LOOPBACK* {.importc, header: "<net/if.h>".}: cuint
  IFF_RUNNING* {.importc, header: "<net/if.h>".}: cuint

  NI_NUMERICHOST* {.importc, header: "<netdb.h>".}: cint

proc getifaddrs*(ifap: ptr ptr IfAddrs): cint
  {.importc, header: "<ifaddrs.h>".}

proc freeifaddrs*(ifa: ptr IfAddrs)
  {.importc, header: "<ifaddrs.h>".}

proc getnameinfo*(sa: ptr IfSockAddr, salen: cuint, host: pointer,
                  hostlen: cuint, serv: pointer, servlen: cuint,
                  flags: cint): cint
  {.importc, header: "<netdb.h>".}
