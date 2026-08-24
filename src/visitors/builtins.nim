import std/[macros, strutils]

macro generateBuiltins*(body: untyped): untyped =
  var fields = nnkRecList.newTree()
  var objFields = newStmtList()
  var params: seq[NimNode] = @[]
  var strings: seq[string] = @[]
  
  for item in body:
    let name = item[0]
    let value = item[1]
    
    let strValue = value.strVal
    
    fields.add(nnkIdentDefs.newTree(nnkPostfix.newTree(ident("*"), name), ident("S"), newEmptyNode()))
    params.add(ident($name & "Sym"))
    objFields.add(newAssignment(nnkDotExpr.newTree(ident("result"), name), params[^1]))
    strings.add(strValue % ["`" & $name & "`"])
  
  let body = nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), fields)
  let procArgs = nnkArgList.newTree(params)
  
  var resultString = strings.join("\n")
  
  result = quote do:
    type Builtins*[S] {.inject.} = ref `body`
    
    proc newBuiltins*[S](`procArgs`: S): Builtins[S] =
      new(result)
      `objFields`

    proc generateBuiltins*(): string =
      `resultString`

generateBuiltins:
  Int    = "type $#* = int"
  Number = "type $#* = int"
  Bool   = "type $#* = bool"