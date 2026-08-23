import /home/xlebore3o4ka/nimProjects/Onnim/src/std/[system]

var `SYMregion` = onnim_system_newArena()

block `transpiled`:
  onnim_system_region(`SYMA`):
    var `SYMx`: uint #[ptr int]# = onnim_system_addArena[int](`SYMA`, 10)
    var `SYMy`: uint #[ptr int]# = `SYMx`
    onnim_system_getArena[int](`SYMA`, `SYMy`) = onnim_system_getArena[int](`SYMA`, `SYMy`) + 1
    var `SYMb`: int = onnim_system_getArena[int](`SYMA`, `SYMx`)
    var `SYMc`: int = onnim_system_getArena[int](`SYMA`, `SYMy`)
    echo `SYMb`
    echo 
  quit(0)