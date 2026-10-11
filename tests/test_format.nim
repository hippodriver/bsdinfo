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
