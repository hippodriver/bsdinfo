import std/unittest

import bsdinfo/disk

suite "collectFileSystems":
  let fileSystems = collectFileSystems()

  test "at least one filesystem is mounted":
    check fileSystems.len > 0

  test "mount points and types are populated":
    for fs in fileSystems:
      check fs.mountPoint.len > 0
      check fs.fsType.len > 0

  test "usage is consistent":
    for fs in fileSystems:
      check fs.usedPercent >= 0.0
      check fs.usedPercent <= 100.0
      check fs.usedBytes + fs.freeBytes == fs.totalBytes

  test "the root filesystem is present":
    var foundRoot = false
    for fs in fileSystems:
      if fs.mountPoint == "/":
        foundRoot = true
    check foundRoot

suite "collectDiskDevices":
  let devices = collectDiskDevices()

  test "devices have names":
    for device in devices:
      check device.name.len > 0

  test "at least one device reports a positive size":
    var foundSized = false
    for device in devices:
      if device.mediasizeBytes > 0:
        foundSized = true
    check foundSized

suite "collectDisks":
  test "aggregates filesystems and devices":
    let disks = collectDisks()
    check disks.fileSystems.len > 0
    check disks.devices.len > 0
