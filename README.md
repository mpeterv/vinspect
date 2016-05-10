# vinspect

vinspect is a library for interactive inspection of complex Lua values.
It visualizes them via ncurses and allows browsing table structures using mouse and keyboard.

vinspect depends on [lcurses](https://github.com/lcurses/lcurses) 9.0.0 or newer.

## Installation

Use [LuaRocks](https://luarocks.org/) and run `[sudo] luarocks install vinspect`.

## Usage

```
require "vinspect" (value)
```

This expression transforms the terminal into an interface for browsing `value`.


```lua
require "vinspect" (_G)
```

```
. - table: 0x82b75c0 (#0, 37 pairs)
<1>{
  _VERSION = "Lua 5.3",
  assert = <function 1>,
  collectgarbage = <function 2>,
  dofile = <function 3>,
  error = <function 4>,
  getmetatable = <function 5>,
  ipairs = <function 6>,
  load = <function 7>,
  loadfile = <function 8>,
  next = <function 9>,
  pairs = <function 10>,
  pcall = <function 11>,
  print = <function 12>,
  rawequal = <function 13>,
  rawget = <function 14>,
  rawlen = <function 15>,
  rawset = <function 16>,
  require = <function 17>,
  select = <function 18>,
  setmetatable = <function 19>,
  tonumber = <function 20>,
  tostring = <function 21>,
...
```

The first line on the screen is a header, the second is a window showing the value.
The window can be scrolled using keyboard.

To jump to a value, simply click on it or anywhere on the line containing it. For lines
with key-value pairs, click on the equals sign or after it to jump to the value and click before
the sign to show the key. To go back, use `Backspace` or click on the header or on empty line. See below for a full list of controls.

The header shows path from the initial value to the current one, as well as its type and size for strings and tables.
Other properties, such as metatables and upvalues, may be shown in the main window after the value.
These properties are also clickable.

```
.io.stdout - userdata: 0x82b8f30
<userdata 1>
<metatable> = <1>{
  __gc = <function 1>,
  __name = "FILE*",
  __tostring = <function 2>,
  close = <function 3>,
  flush = <function 4>,
  lines = <function 5>,
  read = <function 6>,
  seek = <function 7>,
  setvbuf = <function 8>,
  write = <function 9>,
  __index = <table 1>
}
<tostring> = "file (0xb770aa20)"
```

To close the interface, press `q`.

## Keyboard controls

| Keys                                                       | Action                                               |
| ---------------------------------------------------------- | ---------------------------------------------------- |
| `q`                                                        | Exit                                                 |
| Arrow keys, `Page Down`, `Page Up`, `Home`, `End`, `Enter` | Scroll the main window                               |
| `1` - `9`                                                  | Set number of nested tables that will be shown fully |
| `0`                                                        | Show all tables fully                                |
| `Backspace`, `Shift` left arrow key                        | Go back                                              |
| `Shift` right arrow key                                    | Go forward                                           |

## Reference

```lua
local vinspect = require "vinspect"
```

### vinspect.inspect(value, options)

Converts `value` to string. If `options` is truthy, it should be a table, its possible fields:

| Option name | Meaning                                          |Default |
| ----------- | ------------------------------------------------ | ------ |
| `indent`    | Number of spaces used to indent nested tables    | `2`    |
| `depth`     | Number of nested tables that will be shown fully | `2`    |

Examples:

```lua
print(vinspect.inspect({foo = {bar = {baz = {}}}}))
```

```
{
  foo = {
    bar = {...}
  }
}
```

```lua
print(vinspect.inspect({foo = {bar = {baz = {}}}}, {indent = 4}))
```

```
{
    foo = {
        bar = {...}
    }
}
```

```lua
print(vinspect.inspect({foo = {bar = {baz = {}}}}, {depth = 3}))
```

```
{
  foo = {
    bar = {
      baz = {}
    }
  }
}
```

### vinspect.vinspect(value, options)

Shows `value` using a terminal interface. Accepts same options as `vinspect.vinspect`.

### vinspect(value, options)

Alias for `vinspect.vinspect(value, options)`

### vinspect._VERSION

vinspect version in `MAJOR.MINOR.PATCH` format.
