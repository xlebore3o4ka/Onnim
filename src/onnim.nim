import std/[os, parseopt]
import core/[errors, parser]
import visitors/[semantics]

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

  let expression = parser.parse()

  block errorProne:
    if errors.errors.len != 0: break errorProne
    checkSemantics(expression)

    # if errors.errors.len != 0: break errorProne
    # let code = generate(expression, release)

    # if errors.errors.len != 0: break errorProne
    
    # let outputFile = filename.changeFileExt("")
    # let cFile = outputFile & ".c"
    # let exeFile = outputFile & (when defined(windows): ".exe" else: "")
    
    # writeFile(cFile, code)
    
    # let gccCmd = "gcc -O" & (if release: "2 -s" else: "0") & " -o " & exeFile & " " & cFile
    # if execCmd(gccCmd) != 0:
    #   echo "Compilation failed"

  if errors.errors.len != 0:
    for e in errors.errors:
      echo e.kind, ' ', e.message, ' ', e.args

when isMainModule:
  main()