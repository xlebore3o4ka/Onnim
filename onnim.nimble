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

task allFiles, "Save all files content to file all_files.txt":
  let ignoredPathes = @["./bin/*", "./.git/*", "./examples/*"]
  let ignoredNames  = @["all_files.txt", "LICENSE"]
  
  var pathFilters = ""
  for p in ignoredPathes:
    pathFilters &= " -not -path \"" & p & "\""
  
  var nameFilters = ""
  for n in ignoredNames:
    nameFilters &= " -not -name \"" & n & "\""
  
  let cmd = "find . -type f" & pathFilters & nameFilters & " -exec sh -c 'echo \"=== Файл: {} ===\" && cat {} && echo \"\"' \\; > all_files.txt"
  
  exec cmd

task gitChanges, "Save all changes to file gitchanges.txt":
  exec "git diff > gitchanges.txt"
