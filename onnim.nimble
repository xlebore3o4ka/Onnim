# Package

version       = "0.1.0"
author        = "xlebore3o4ka"
description   = "-"
license       = "AGPL-3.0-or-later"
srcDir        = "src"
binDir        = "bin"
bin           = @["onnim"]

# Dependencies

requires "nim >= 2.2.10"

task myRun, "Run with debug flags":
  exec "nimble run --debugger:native --stacktrace:on --linetrace:on --define:debug -- " & commandLineParams.join(" ")