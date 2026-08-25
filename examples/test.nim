import /home/xlebore3o4ka/nimProjects/Onnim/src/std/[system, builtins]

var s_region = onnim_system_newArena()  # DEPRECATED

block transpiled:
  proc s_test(s_a: `Int`, s_b: `Int`): `Number` = 
    return s_a + s_b
  var s_testType: proc (a: `Int`, b: `Int`): `Number` = s_test
  