import /home/xlebore3o4ka/nimProjects/Onnim/src/std/[system]

var `ident_region` = onnim_system_newArena()

block `transpiled`:
  onnim_system_region(`ident_a`):
    onnim_system_region(`ident_b`):
      var `ident_x`: uint #[ptr int]# = onnim_system_addArena[int](`ident_a`, 1)
  var `ident_y`: int = 10
  quit(0)