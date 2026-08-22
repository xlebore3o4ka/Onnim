import /home/xlebore3o4ka/nimProjects/Onnim/src/std/[system]

var region = onnim_system_newArena()

block `transpiled`:
  var `ident_x`: uint #[ptr int]# = onnim_system_addArena[int](region, 10)
  var `ident_y`: int = onnim_system_getArena[int](region, `ident_x`)
  onnim_system_getArena[int](region, `ident_x`) = 5
