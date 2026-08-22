{.push checks: off.}

const onnim_system_ARENA_INITIAL_SIZE = 4096

type
  onnim_system_Arena* = object
    size*: uint = onnim_system_ARENA_INITIAL_SIZE
    len*: uint = 0
    arena*: ptr UncheckedArray[byte]

proc onnim_system_addArena*[T](arena: var onnim_system_Arena, value: T): ptr T =
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

template onnim_system_addArena*[T](value: T): ptr T = onnim_system_addArena(onnim_system_CurrentArena, value)

template onnim_system_newArena*(size: uint = onnim_system_ARENA_INITIAL_SIZE): onnim_system_Arena =
  onnim_system_Arena(arena: cast[ptr UncheckedArray[byte]](alloc(size)))

template onnim_system_killArena*(arena: var onnim_system_Arena) =
  if arena.arena != nil:
    dealloc(arena.arena)
    arena.arena = nil 

var onnim_system_CurrentArena*: onnim_system_Arena = onnim_system_newArena()

{.pop.}