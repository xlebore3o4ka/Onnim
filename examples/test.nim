import /home/xlebore3o4ka/nimProjects/Onnim/src/std/[system]

var `ident_region` = onnim_system_newArena()

block `transpiled`:
  onnim_system_region(`SYMt`):
    var `SYMx`: uint #[ptr int]# = onnim_system_addArena[int](`SYMt`, 10)
  onnim_system_region(`SYMt`):
    var `SYMx`: uint #[ptr int]# = onnim_system_addArena[int](`SYMt`, 10)
  quit(0)