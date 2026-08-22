import /home/xlebore3o4ka/nimProjects/Onnim/src/std/[system]

var `ident_region` = onnim_system_newArena()

block `transpiled`:
  var `ident_x`: uint #[ptr int]# = onnim_system_addArena[int](`ident_region`, 10)
  var `ident_y`: uint #[ptr int]# = onnim_system_addArena[int](`ident_region`, 10)
  var `ident_a`: int = onnim_system_getArena[int](`ident_region`, `ident_x` + 1000000)
  quit(0)