import std/[strutils]
import tokens

type
  TypeKind* = enum
    typeUndefined

    typeInt

    typeBool

    typeFunc
    typePtr

    typeRegion

  Type* = ref object
    case kind*: TypeKind
    of typeFunc:
      argTypes*: seq[Type]
      returnType*: Type
    of typePtr:
      ptrBase*: Type
      ptrRegion*: Type
    of typeRegion:
      regionName*: Token
    else: discard

let
  undefinedType* = Type(kind: typeUndefined)
  int64Type* = Type(kind: typeInt)
  boolType* = Type(kind: typeBool)
var
  funcTypes*: seq[Type]
  ptrTypes*: seq[Type]
  regionTypes*: seq[Type]

proc eq*(a: Type, b: Type): bool =
  if a == nil or b == nil: return false
  if a.kind != b.kind: return false

  if a.kind == typeFunc:
    if a.argTypes.len != b.argTypes.len: return false

    for i in 0..<a.argTypes.len:
      if not eq(a.argTypes[i], b.argTypes[i]): return false

    return eq(a.returnType, b.returnType)

  if a.kind == typePtr:
    return eq(a.ptrBase, b.ptrBase) and eq(a.ptrRegion, b.ptrRegion)

  if a.kind == typeRegion:
    return a.regionName == b.regionName

  return true

proc eq*(a: Type, b: TypeKind): bool {.inline.} =
  if a == nil: return false
  a.kind == b

proc eq*(a: TypeKind, b: Type): bool {.inline.} =
  if b == nil: return false
  a == b.kind

proc eq*(a: TypeKind, b: TypeKind): bool {.inline.} =
  a == b

proc neq*(a: Type | TypeKind, b: Type | TypeKind): bool {.inline.} =
  not eq(a, b)

proc getFuncType*(argTypes: seq[Type], returnType: Type): Type =
  for funcType in funcTypes:
    if funcType.argTypes == argTypes and eq(funcType.returnType, returnType):
      return funcType
  
  result = Type(kind: typeFunc, argTypes: argTypes, returnType: returnType)
  funcTypes.add(result)

proc getPtrType*(baseType: Type, region: Type): Type =
  for ptrType in ptrTypes:
    if eq(ptrType.ptrBase, baseType) and eq(ptrType.ptrRegion, region):
      return ptrType
  
  result = Type(kind: typePtr, ptrBase: baseType, ptrRegion: region)
  ptrTypes.add(result)

proc getRegionType*(name: Token): Type =
  for regionType in regionTypes:
    if regionType.regionName.lexeme == name.lexeme:
      return regionType
  
  result = Type(kind: typeRegion, regionName: name)
  regionTypes.add(result)

proc `$`*(k: TypeKind): string =
  case k
  of typeUndefined: "unset"
  of typeInt:       "int"

  of typeBool:      "bool"
  of typeFunc:      "T(T, ...)"
  of typePtr:       "T*"

  of typeRegion:    "region"

proc `$`*(t: Type): string =
  if t == nil: return "nilType"
  case t.kind
  of typeFunc:
    var args: seq[string]
    for arg in t.argTypes:
      args.add($arg)
    return (if t.returnType.neq typeUndefined: $t.returnType else: "_") & "(" & args.join(", ") & ")"
  of typePtr:
    return $t.ptrBase & "^" & $t.ptrRegion.regionName.lexeme
  of typeRegion:
    return "region " & $t.regionName.lexeme
  else: return $t.kind