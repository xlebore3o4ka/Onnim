import /home/xlebore3o4ka/nimProjects/Onnim/src/std/[system, builtins]

var s_region = onnim_system_newArena()  # DEPRECATED

block transpiled:
  var s_x: proc (a: `Int`, b: `Int`): `Int` = proc (s_a: `Int`, s_b: `Int`): `Int` = 
    return s_a + s_b
  