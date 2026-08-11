import std/[os, osproc, parseopt]
import core/[errors, parser]
import visitors/[semantics, codegen]

proc main() =
  var
    filename: string

  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      # of "release", "r": release = true
      else: discard
    of cmdArgument:
      if filename == "": filename = key
    of cmdEnd: discard

  if filename == "":
    echo "Using: ", getAppFilename().extractFilename(), " <file>"
    return

  if not fileExists(filename):
    echo "Error: file not found - ", filename
    return

  let content = readFile(filename)
  var parser = newParser(content, filename)

  let code = parser.parse()

  block errorProne:
    if errors.errors.len != 0: break errorProne
    checkSemantics(code)

    if errors.errors.len != 0: break errorProne
    let code = generateCode(code)

    if errors.errors.len != 0: break errorProne
    
    let outputFile = filename.changeFileExt("")
    let nimFile = outputFile & ".nim"
    let exeFile = outputFile & (when defined(windows): ".exe" else: "")
    
    writeFile(nimFile, code)
    
    let nimCmd = "nim c -o:" & exeFile & " " & nimFile
    if execCmd(nimCmd) != 0:
      echo "Compilation failed [" & nimCmd & "]"

  if errors.errors.len != 0:
    for e in errors.errors:
      echo e.kind, ' ', e.message, ' ', e.args

when isMainModule:
  main()