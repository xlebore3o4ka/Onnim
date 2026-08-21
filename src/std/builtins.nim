import macros

macro `debug`*(args: varargs[string, `$`]): untyped =
  result = args[0]
  for i in 1..<args.len:
    result = quote do: `result` & `args[i]`
  result = quote do:
    stdout.write(`result`)