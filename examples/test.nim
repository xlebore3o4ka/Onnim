import /home/xlebore3o4ka/nimProjects/Onnim/src/std/[system, builtins]

var s_region = onnim_system_newArena()  # DEPRECATED

block transpiled:
  type `A` = proc (s_a: `Int`, s_c: `Int`): `Int`
  proc s_test(s_a: `Int`, s_b: `Int`): `Int` = 
    return s_a + s_b
  var s_add: `A` = s_test
  