import std/[strutils]
import tokens

type
  TypeKind* = enum

    typeUnset

    typeBuiltin
    typeBase
    typeType

    typeFunc

  ArgType* = object
    name*: string
    argType*: Type
    mutable*: bool

  Type* = ref object
    token*: Token
    case kind*: TypeKind
    of typeFunc:
      argTypes*: seq[ArgType]
      returnType*: Type
    of typeBase, typeBuiltin:
      name*: string
    of typeType:
      baseType*: Type
    else: discard

proc eq*(a: Type, b: Type): bool =
  if a == nil or b == nil: return false
  if a.kind != b.kind: return false

  if a.kind in {typeBase, typeBuiltin}:
    return a.name == b.name

  if a.kind == typeFunc:
    if a.argTypes.len != b.argTypes.len: return false

    if a.argTypes != b.argTypes: return false

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

proc getUnsetType*(): Type {.inline.} =
  Type(kind: typeUnset)

proc getFuncType*(argTypes: seq[ArgType], returnType: Type): Type {.inline.} =
  Type(kind: typeFunc, argTypes: argTypes, returnType: returnType)

proc getBuiltinType*(name: string): Type {.inline.} =
  Type(kind: typeBuiltin, name: name)

proc getBaseType*(name: string): Type {.inline.} =
  Type(kind: typeBase, name: name)

proc getTypeType*(baseType: Type): Type {.inline.} =
  Type(kind: typeType, baseType: baseType)

proc getUnsetType*(token: Token): Type {.inline.} =
  Type(kind: typeUnset, token: token)

proc getFuncType*(token: Token, argTypes: seq[ArgType], returnType: Type): Type {.inline.} =
  Type(kind: typeFunc, token: token, argTypes: argTypes, returnType: returnType)

proc getBuiltinType*(token: Token): Type {.inline.} =
  Type(kind: typeBuiltin, token: token, name: token.lexeme)

proc getBaseType*(token: Token): Type {.inline.} =
  Type(kind: typeBase, token: token, name: token.lexeme)

proc getTypeType*(token: Token, baseType: Type): Type {.inline.} =
  Type(kind: typeType, token: token, baseType: baseType)

proc `$`*(k: TypeKind): string {.inline.} =
  case k
  of typeUnset:     "Unset"

  of typeBuiltin:   "builtin-type"
  of typeBase:      "base-type"
  of typeType:      "Type"

  of typeFunc:      "T(T args, ...)"

proc `$`*(t: Type): string 

proc `$`*(argTypes: seq[ArgType]): string =
  var args: seq[string]
  for arg in argTypes:
    let mutableSuffix = if arg.mutable: "$" else: "!"
    args.add($arg.argType & (if arg.name.len != 0: " " & arg.name else: "") & mutableSuffix)
  return "(" & args.join(", ") & ")"

proc `$`*(t: Type): string =
  if t == nil: return "nilType"
  case t.kind
  of typeBase, typeBuiltin:
    return $t.name
  of typeType:
    return "Type[" & $t.baseType & "]"
  of typeFunc:
    return $t.returnType & $t.argTypes
  else: return $t.kind