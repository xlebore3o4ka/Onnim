import /home/xlebore3o4ka/nimProjects/Onnim/src/std/[system, builtins]

var s_region = onnim_system_newArena()  # DEPRECATED

block transpiled:
  onnim_system_region(r):
    var s_counter: uint #[ptr `Number`]# = onnim_system_addArena[`Number`](s_r, 0)
    proc s_increment(s_c: var uint #[ptr `Number`]#): `Number` = 
      onnim_system_getArena[`Number`](s_r, s_c) = onnim_system_getArena[`Number`](s_r, s_c) + 1
      return onnim_system_getArena[`Number`](s_r, s_c)
    s_write(s_increment(s_counter))
    s_write(s_increment(s_counter))
    s_write(s_increment(s_counter))
  