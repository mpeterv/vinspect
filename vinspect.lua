local curses = require "curses"
local mouse = require "vinspect.mouse"

local rawlen = rawget(_G, "rawlen") or function(t) return #t end
local mtype = rawget(math, "type") or function() return "integer" end

local vinspect = {
   _VERSION = "0.0.2"
}

local escaped_chars = {
   ["\\"] = "\\\\",
   ["\a"] = "\\a", 
   ["\b"] = "\\b",
   ["\f"] = "\\f",
   ["\n"] = "\\n",
   ["\r"] = "\\r",
   ["\t"] = "\\t",
   ["\v"] = "\\v"
}

local function escape_char(c)
   return escaped_chars[c] or ("\\%d"):format(c:byte())
end

local function quote_string(str)
   local escaped = str:gsub("[^\32-\126]", escape_char)

   if escaped:find('"') and not escaped:find("'") then
      return "'" .. escaped .. "'"
   else
      return '"' .. escaped:gsub('"', '\\"') .. '"'
   end
end

local function is_integer(n)
   return n == math.floor(n) and n ~= 1/0 and n ~= -1/0
end

local function format_number(n)
   if n ~= n then
      return "NaN"
   elseif n == 1/0 then
      return "Inf"
   elseif n == -1/0 then
      return "-Inf"
   else
      local formatted

      if is_integer(n) and mtype(n) == "integer" then
         formatted = ("%d"):format(n)
      else
         formatted = ("%.17g"):format(n)
      end

      if mtype(n) == "float" and not formatted:find("%.") then
         -- Number is internally a float but looks like an integer.
         -- Insert ".0" after first run of digits.
         return (formatted:gsub("(%d+)(.?)", "%1.0%2", 1))
      else
         return formatted
      end
   end
end

local standard_types = {
   number = 1,
   boolean = 2,
   string = 3,
   table = 5,
   ["function"] = 6,
   userdata = 7,
   thread = 8
}

local function raw_type(value)
   local type_ = type(value)

   if standard_types[type_] then
      return type_
   elseif pcall(next, value) then
      return "table"
   elseif type(type_) == "string" then
      return (type_:gsub("[^\32-\126]", ""))
   else
      return "unknown"
   end
end

local function record_comparator(record1, record2)
   local priority1, priority2 = record1[6], record2[6]

   if priority1 == priority2 then
      local key_type = record1[3]

      if key_type == "string" or key_type == "number" then
         return record1[2] < record2[2]
      elseif key_type == "boolean" then
         -- Put true before false.
         return record1[2]
      else
         -- Use order in which keys appeared during iteration.
         return record1[1] < record2[1]
      end
   else
      return priority1 < priority2
   end
end

local function get_pair_records(t)
   local records = {}
   local i = 1
   local length = rawlen(t)

   for key in next, t do
      local value = rawget(t, key)
      local record = {i, key, raw_type(key), value, raw_type(value)}
      local in_array_part = (record[3] == "number") and (1 <= key) and (key <= length) and is_integer(key)
      -- Keys from array part go first, then go standard types, then custom types.
      record[6] = in_array_part and 0 or standard_types[record[3]] or 9
      records[i] = record
      i = i + 1

      if record[3] == "string" and record[5] == "table" then
         -- Put string keys with table values after other string keys.
         record[6] = record[6] + 1
      end
   end

   table.sort(records, record_comparator)
   return records
end

local function put_str(state, str)
   table.insert(state.line.buffer, str)
end

local function put_line(state, upper)
   local line = {buffer = {}, upper = upper}
   state.line = line
   table.insert(state.lines, line)
end

local function get_pos(state)
   return {#state.lines, #state.line.buffer}
end

local function get_ref(state, value, type_)
   return state.refs[type_] and state.refs[type_][value]
end

local function add_ref(state, value, type_)
   local refs = state.refs
   refs[type_] = refs[type_] or {n = 0}
   refs[type_].n = refs[type_].n + 1
   refs[type_][value] = refs[type_].n
   return refs[type_].n
end

local function str_ref(ref, type_)
   return ("<%s %d>"):format(type_, ref)
end

-- Forward declaration.
local put_value

local function put_key(state, key, type_)
   if type_ == "string" and key:find("^[_%a][_%w]*$") then
      state.line.key = key
      return put_str(state, key)
   else
      put_str(state, "[")
      put_value(state, key, type_, true)
      put_str(state, "]")
   end
end

local function collapsed_table_end(t)
   return next(t) == nil and "}" or "...}"
end

local function put_pair_record(state, record, upper_line)
   local key, key_type = record[2], record[3]
   local value, value_type = record[4], record[5]

   put_line(state, upper_line)
   state.line.key, state.line.value = key, value
   put_str(state, state.indent:rep(state.level))
   put_key(state, key, key_type)
   put_str(state, " = ")
   state.line.equals = #state.line.buffer
   put_value(state, value, value_type)
   put_str(state, ",")
   state.line.key, state.line.value = key, value
end

local function put_table(state, t, is_key)
   local ref = get_ref(state, t, "table")

   if ref then
      put_str(state, "")

      if not state.table_repetitions[ref] then
         -- This is the second time this table is encountered.
         table.insert(state.repeating_tables, ref)
         state.table_repetitions[ref] = {}
      end

      table.insert(state.table_repetitions[ref], get_pos(state))
      return
   end

   put_str(state, "{")
   ref = add_ref(state, t, "table")
   state.table_starts[ref] = get_pos(state)

   if is_key or state.level >= state.max_level then
      put_str(state, collapsed_table_end(t))
      return
   end

   state.level = state.level + 1
   local first_line = state.line
   local records = get_pair_records(t)

   for _, record in ipairs(records) do
      put_pair_record(state, record, first_line)
   end

   state.level = state.level - 1

   if #records ~= 0 then
      -- Replace extra comma with last newline.
      table.remove(state.line.buffer)
      put_line(state, first_line.upper)
      put_str(state, state.indent:rep(state.level))
   end

   put_str(state, "}")
end

function put_value(state, value, type_, is_key)
   if type_ == "nil" then
      return put_str(state, "nil")
   elseif type_ == "boolean" then
      return put_str(state, value and "true" or "false")
   elseif type_ == "number" then
      return put_str(state, format_number(value))
   elseif type_ == "string" then
      return put_str(state, quote_string(value))
   elseif type_ == "table" then
      return put_table(state, value, is_key)
   else
      local ref = get_ref(state, value, type_) or add_ref(state, value, type_)
      return put_str(state, str_ref(ref, type_))
   end
end

local function prefix_part(state, pos, prefix)
   local line, part = pos[1], pos[2]
   local buffer = state.lines[line].buffer
   buffer[part] = prefix .. buffer[part]
end

local function new_state(options)
   return {
      lines = {},
      refs = {},
      repeating_tables = {},
      table_starts = {},
      table_repetitions = {},
      property_root = {},
      level = 0,
      max_level = options.depth,
      indent = (" "):rep(options.indent)
   }
end

local function compress_refs(state)
   table.sort(state.repeating_tables)
   local new_ref = 1

   for _, ref in ipairs(state.repeating_tables) do
      prefix_part(state, state.table_starts[ref], "<" .. tostring(new_ref) .. ">")

      for _, pos in ipairs(state.table_repetitions[ref]) do
         prefix_part(state, pos, str_ref(new_ref, "table"))
      end

      new_ref = new_ref + 1
   end
end

local function put_property(state, name, value, collapse, trace_name)
   trace_name = trace_name or name
   name = "<" .. name .. ">"
   trace_name = "<" .. trace_name .. ">"
   put_line(state, state.property_root)
   put_str(state, name .. " = ")
   state.line.value, state.line.trace = value, trace_name
   put_value(state, value, raw_type(value), collapse)
   state.line.value, state.line.trace = value, trace_name
end

local function value_to_lines(value, options)
   local state = new_state(options)

   local type_ = raw_type(value)
   put_line(state)
   put_value(state, value, type_)

   local mt = debug.getmetatable(value)

   if mt ~= nil then
      put_property(state, "metatable", mt, false, "mt")

      local tostring_metamethod = rawget(mt, "__tostring")

      if tostring_metamethod ~= nil then
         local ok, res = pcall(tostring_metamethod, value)
         put_property(state, "tostring", ok and res or nil, true)

         if not ok then
            state.line.buffer[#state.line.buffer] = "<error>"
         end
      end
   end

   if type_ == "function" then
      local info = debug.getinfo(value)

      if info.short_src then
         put_property(state, "source", info.short_src)

         if info.linedefined and info.linedefined > 0 and info.lastlinedefined and info.lastlinedefined > 0 then
            put_property(state, "first line", info.linedefined)
            put_property(state, "last line", info.lastlinedefined)
         end
      end

      -- TODO: use C API to check if a function is a C function.
      if info.short_src ~= "[C]" and info.nparams then
         put_property(state, "args", info.nparams)
         put_property(state, "vararg", info.isvararg)
      end

      if info.nups then
         put_property(state, "upvalues", info.nups)

         for i = 1, info.nups do
            local name, upvalue = debug.getupvalue(value, i)

            if name then
               put_property(state, "upvalue " .. name, upvalue, true, "up " .. name)
            end
         end
      end
   end

   compress_refs(state)
   return state.lines
end

local function normalize_options(options)
   return {
      depth = options and options.depth or 2,
      indent = options and options.indent or 2
   }
end

-- Converts a value to string.
-- Accepts options .depth and .indent.
function vinspect.inspect(value, options)
   local lines = value_to_lines(value, normalize_options(options))

   for i, line in ipairs(lines) do
      lines[i] = table.concat(line.buffer)
   end

   return table.concat(lines, "\n")
end

local function npairs(t)
   local i = 0

   for _ in next, t do
      i = i + 1
   end

   if i == 1 then
      return "1 pair"
   else
      return tostring(i) .. " pairs"
   end
end

local function get_trace(viewer)
   local deltas = {}

   for i = 2, viewer.current_i do
      table.insert(deltas, viewer.history[i].delta)
   end

   local trace = table.concat(deltas)

   if trace:sub(1, 1) ~= "." then
      trace = "." .. trace
   end

   return trace
end

local function get_header(value)
   local type_ = raw_type(value)
   local header = type_

   if type_ == "number" then
      local mtype_ = mtype(value)

      if mtype_ == "integer" and not is_integer(value) then
         mtype_ = "float"
      end

      header = header .. " (" .. mtype_ .. ")"
   elseif type_ == "string" then
      header = header .. " (#" .. tostring(#value) .. ")"
   elseif type_ ~= "nil" and type_ ~= "boolean" then
      local mt = debug.getmetatable(value)
      debug.setmetatable(value, nil)
      header = tostring(value)
      debug.setmetatable(value, mt)

      if type_ == "table" then
         header = header .. " (#" .. tostring(rawlen(value)) .. ", " .. npairs(value) .. ")"
      end
   end

   return header
end

local function reload_value(viewer)
   local value = viewer.current.value
   viewer.trace = get_trace(viewer)
   viewer.header = get_header(value)
   viewer.lines = value_to_lines(value, viewer.options)
   viewer.rows = #viewer.lines
   viewer.columns = 0

   for _, line in ipairs(viewer.lines) do
      if line.equals then
         line.str = table.concat(line.buffer, nil, 1, line.equals - 1)
         line.equals_column = #line.str + 2
         line.str = line.str .. table.concat(line.buffer, nil, line.equals)
      else
         line.str = table.concat(line.buffer)
         line.equals_column = 0
      end

      viewer.columns = math.max(viewer.columns, #line.str)
   end

   viewer.screen:clear()
   viewer.screen:refresh()

   if not viewer.pad then
      viewer.pad = curses.newpad(viewer.rows, viewer.columns)
      viewer.pad:keypad(1)
   else
      viewer.pad:clear()
      viewer.pad:resize(viewer.rows, viewer.columns)
   end

   for i, line in ipairs(viewer.lines) do
      viewer.pad:mvaddstr(i - 1, 0, line.str)
   end
end

local function render(viewer, max_y, max_x)
   local trace
   local trace_limit = max_x - 2 - #" - " - #viewer.header

   if #viewer.trace > trace_limit then
      trace = "..." .. viewer.trace:sub(#viewer.trace - trace_limit + #"...")
   end

   viewer.screen:mvaddstr(0, 0, (trace or viewer.trace) .. " - " .. viewer.header)
   viewer.screen:refresh()
   viewer.pad:prefresh(viewer.current.top, viewer.current.left, 1, 0, max_y - 1, max_x - 2)
end

local function push_value(viewer, value, delta)
   viewer.current_i = viewer.current_i + 1
   viewer.depth = viewer.current_i

   viewer.current = {
      value = value,
      delta = delta,
      top = 0,
      left = 0
   }

   viewer.history[viewer.current_i] = viewer.current
   reload_value(viewer)
end

local function pop_value(viewer)
   if viewer.current_i > 1 then
      viewer.current_i = viewer.current_i - 1
      viewer.current = viewer.history[viewer.current_i]
      reload_value(viewer)
   end
end

local function unpop_value(viewer)
   if viewer.current_i ~= viewer.depth then
      viewer.current_i = viewer.current_i + 1
      viewer.current = viewer.history[viewer.current_i]
      reload_value(viewer)
   end
end

local function repr_delta_part(is_key, line)
   if is_key then
      return "<key>"
   elseif line.trace then
      return line.trace
   else
      local key = line.key
      local type_ = raw_type(key)

      if type_ == "string" then
         if key:find("^[_%a][_%w]*$") then
            return "." .. key
         else
            return "[" .. quote_string(key) .. "]"
         end
      elseif type_ == "table" then
         return "[{" .. collapsed_table_end(key) .. "]"
      elseif type_ == "number" then
         return "[" .. format_number(key) .. "]"
      elseif type_ == "boolean" then
         return "[" .. tostring(key) .. "]"
      else
         return "[" .. type_ .. "]"
      end
   end
end

local function trace_delta(line, is_key)
   if not line.upper then
      return ""
   else
      return trace_delta(line.upper) .. repr_delta_part(is_key, line)
   end
end

-- Returns boolean indicating whether need to keep running.
local function handle_ch(viewer, ch)
   local max_y, max_x = viewer.screen:getmaxyx()

   if not ch then
      return true
   elseif ch == ("q"):byte() then
      return false
   elseif ch == curses.KEY_UP then
      viewer.current.top = viewer.current.top - 1
   elseif ch == curses.KEY_DOWN or ch == ("\r"):byte() then
      viewer.current.top = viewer.current.top + 1
   elseif ch == curses.KEY_LEFT then
      viewer.current.left = viewer.current.left - viewer.options.indent
   elseif ch == curses.KEY_RIGHT then
      viewer.current.left = viewer.current.left + viewer.options.indent
   elseif ch == curses.KEY_HOME then
      viewer.current.top = 0
   elseif ch == curses.KEY_END then
      viewer.current.top = viewer.rows - max_y + 1
   elseif ch == curses.KEY_PPAGE then
      viewer.current.top = viewer.current.top - max_y
   elseif ch == curses.KEY_NPAGE then
      viewer.current.top = viewer.current.top + max_y
   elseif ch == mouse.KEY_MOUSE then
      local x, y = mouse.get_coords()

      if not x then
         return true
      end

      local column = x + viewer.current.left + 1
      local line_nr = y + viewer.current.top

      if y == 0 or line_nr > #viewer.lines then
         pop_value(viewer)
      else
         local line = viewer.lines[line_nr]

         if line.value == nil then
            return true
         end

         local new_value
         local is_key

         if line.equals and column < line.equals_column then
            is_key = true
            new_value = line.key
         else
            new_value = line.value
         end

         push_value(viewer, new_value, trace_delta(line, is_key))
      end
   elseif ch >= ("0"):byte() and ch <= ("9"):byte() then
      local new_depth = ch - ("0"):byte()

      if new_depth == 0 then
         viewer.options.depth = math.huge
      else
         viewer.options.depth = new_depth
      end

      reload_value(viewer)
   elseif ch == curses.KEY_BACKSPACE or ch == curses.KEY_SLEFT then
      pop_value(viewer)
   elseif ch == curses.KEY_SRIGHT then
      unpop_value(viewer)
   else
      return true
   end

   viewer.current.top = math.max(math.min(viewer.current.top, viewer.rows - max_y + 1), 0)
   viewer.current.left = math.max(math.min(viewer.current.left, viewer.columns - max_x + 1), 0)
   render(viewer, max_y, max_x)
   return true
end

local function loop(viewer)
   while handle_ch(viewer, viewer.pad:getch()) do end
end

local function error_handler(err)
   return err .. "\noriginal " .. debug.traceback("", 2):sub(2)
end

local function with_screen(func)
   local screen = curses.initscr()
   curses.cbreak(true)
   curses.echo(false)
   curses.nl(false)
   curses.curs_set(0)
   mouse.init()
   screen:clear()
   screen:refresh()

   local ok, err = xpcall(function() func(screen) end, error_handler)

   curses.cbreak(false)
   curses.echo(true)
   curses.nl(true)
   curses.curs_set(1)
   mouse.close()
   curses.endwin()

   if not ok then
      error(err, 0)
   end
end

-- Visualizes a value using ncurses.
-- Accepts options .depth and .indent.
function vinspect.vinspect(value, options)
   with_screen(function(screen)
      local viewer = {
         history = {},
         depth = 0,
         current_i = 0,
         options = normalize_options(options),
         screen = screen
      }

      push_value(viewer, value)
      render(viewer, screen:getmaxyx())
      loop(viewer)
   end)
end

setmetatable(vinspect, {__call = function(self, value, options)
   self.vinspect(value, options)
end})

return vinspect
