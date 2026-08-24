import /home/xlebore3o4ka/nimProjects/Onnim/src/std/[system, builtins]

var s_region = onnim_system_newArena()  # DEPRECATED

block transpiled:
  var s_x: `Int` = 10
  var s_f: `Bool` = false
  if s_x > 5:
    s_f = true
  else:
    s_x = 5
  