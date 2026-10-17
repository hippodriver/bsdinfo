import std/unittest

import bsdinfo/format

suite "formatBytes":
  test "bytes below 1 KiB are shown verbatim":
    check formatBytes(0) == "0 B"
    check formatBytes(512) == "512 B"

  test "scales to binary units":
    check formatBytes(1024) == "1.0 KiB"
    check formatBytes(1024 * 1024) == "1.0 MiB"
    check formatBytes(1024 * 1024 * 1024) == "1.0 GiB"
    check formatBytes(64'u64 * 1024 * 1024 * 1024) == "64.0 GiB"

suite "formatMhz":
  test "keeps MHz below 1000":
    check formatMhz(799) == "799 MHz"

  test "switches to GHz at 1000":
    check formatMhz(1000) == "1.00 GHz"
    check formatMhz(2900) == "2.90 GHz"

suite "formatPercent":
  test "one decimal place":
    check formatPercent(0.0) == "0.0%"
    check formatPercent(42.3) == "42.3%"
    check formatPercent(100.0) == "100.0%"

suite "formatRate":
  test "zero and fractional rates":
    check formatRate(0.0) == "0 B/s"
    check formatRate(1536.0) == "1.5 KiB/s"

suite "formatLinkSpeed":
  test "zero is unknown":
    check formatLinkSpeed(0) == "n/a"

  test "scales to decimal units":
    check formatLinkSpeed(100'u64) == "100 bit/s"
    check formatLinkSpeed(1_000'u64) == "1.0 kbit/s"
    check formatLinkSpeed(1_000_000_000'u64) == "1.0 Gbit/s"
