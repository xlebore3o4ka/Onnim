{.push checks: off.}

const ONNIM_ARENA_INITIAL_SIZE = 4096

type
  OnnimArena* = object
    size*: uint = ONNIM_ARENA_INITIAL_SIZE
    len*: uint = 0
    arena*: ptr UncheckedArray[byte]

proc onnim_addArena*[T](arena: var OnnimArena, value: T): ptr T =
  const align = uint(alignof(T)) - 1
  arena.len = (arena.len + align) and not align

  let newLen = arena.len + uint(sizeof(T))
  if unlikely(newLen > arena.size):
    let newSize = newLen * 2
    arena.arena = cast[ptr UncheckedArray[byte]](realloc(arena.arena, newSize))
    arena.size = newSize
  
  result = cast[ptr T](addr arena.arena[arena.len])
  result[] = value
  arena.len = newLen

template onnim_addArena*[T](value: T): ptr T = onnim_addArena(onnimCurrentArena, value)

template onnim_newArena*(size: uint = ONNIM_ARENA_INITIAL_SIZE): OnnimArena =
  OnnimArena(arena: cast[ptr UncheckedArray[byte]](alloc(size)))

template onnim_killArena*(arena: var OnnimArena) =
  if arena.arena != nil:
    dealloc(arena.arena)
    arena.arena = nil 

var onnimCurrentArena*: OnnimArena = onnim_newArena()

{.pop.}