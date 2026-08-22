{.push checks: off.}

const onnim_system_ARENA_INITIAL_SIZE = 4096

type
  onnim_system_Arena* = object
    size*: uint = onnim_system_ARENA_INITIAL_SIZE
    len*: uint = 0
    arena*: ptr UncheckedArray[byte]

proc onnim_system_addArena*[T](arena: var onnim_system_Arena, value: T): uint =
  const align = uint(alignof(T)) - 1
  arena.len = (arena.len + align) and not align

  let newLen = arena.len + uint(sizeof(T))
  if unlikely(newLen > arena.size):
    let newSize = newLen * 2
    arena.arena = cast[ptr UncheckedArray[byte]](realloc(arena.arena, newSize))
    arena.size = newSize
  
  let idx = arena.len
  cast[ptr T](addr arena.arena[idx])[] = value
  arena.len = newLen
  return idx

proc onnim_system_getArena*[T](arena: var onnim_system_Arena, index: uint): var T {.inline.} =
  if index + uint(sizeof(T)) <= arena.len:
    return cast[ptr T](addr arena.arena[index])[]
  raise newException(IndexDefect, "Index out of bounds")

template onnim_system_newArena*(size: uint = onnim_system_ARENA_INITIAL_SIZE): onnim_system_Arena =
  onnim_system_Arena(arena: cast[ptr UncheckedArray[byte]](alloc(size)))

template onnim_system_killArena*(onnim_arena: var onnim_system_Arena) =
  if onnim_arena.arena != nil:
    dealloc(onnim_arena.arena)
    onnim_arena.arena = nil

import macros

macro onnim_system_region*(name: untyped, regionBlock: untyped): untyped =
  return quote do:
    block:
      var `name` = onnim_system_newArena()
      `regionBlock`
      onnim_system_killArena(`name`)

{.pop.}