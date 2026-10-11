import std/parseopt

import bsdinfo/gui
import bsdinfo/tui

when isMainModule:
  var useTui = false
  var parser = initOptParser()
  for kind, key, val in parser.getopt():
    case kind
    of cmdLongOption:
      case key
      of "tui": useTui = true
      of "gui": useTui = false
      else: discard
    else: discard

  if useTui:
    runTui()
  else:
    runGui()
