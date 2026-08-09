import std/[strutils]

type
  TypeKind* = enum
    typeUndefined

    typeInt64

    typeBool

    typeFunc

  Type* = ref object
    case kind*: TypeKind
    of typeFunc:
      argTypes*: seq[Type]
      returnType*: Type
    else: discard

let
  undefinedType* = Type(kind: typeUndefined)
  int64Type* = Type(kind: typeInt64)
  boolType* = Type(kind: typeBool)
var
  funcTypes*: seq[Type]

proc eq*(a: Type, b: Type): bool =
  if a == nil or b == nil: return false
  if a.kind != b.kind: return false
  if a.kind == typeFunc:
    if a.argTypes.len != b.argTypes.len: return false
    for i in 0..<a.argTypes.len:
      if not eq(a.argTypes[i], b.argTypes[i]): return false
    return eq(a.returnType, b.returnType)
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

proc getUndefinedType*(): Type {.inline.} = undefinedType
proc getInt64Type*():     Type {.inline.} = int64Type
proc getBoolType*():      Type {.inline.} = boolType

proc getFuncType*(argTypes: seq[Type], returnType: Type): Type =
  for funcType in funcTypes:
    if funcType.kind == typeFunc and funcType.argTypes == argTypes and eq(funcType.returnType, returnType):
      return funcType
  
  result = Type(kind: typeFunc, argTypes: argTypes, returnType: returnType)
  funcTypes.add(result)

proc `$`*(k: TypeKind): string =
  case k
  of typeUndefined: "undefined"
  of typeInt64:     "int64"

  of typeBool:      "bool"
  of typeFunc:      "T(T, ...)"

proc `$`*(t: Type): string =
  if t == nil: return "nilType"
  case t.kind
  of typeFunc:
    var args: seq[string]
    for arg in t.argTypes:
      args.add($arg)
    return $t.returnType & "(" & args.join(", ") & ")"
  else: return $t.kind