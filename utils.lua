local wezterm = require 'wezterm'
local M = {}

--- Merges two tables, overwriting common elements from table_b
--- @param ... table[]
--- @return table
function M.merge(...)
   local args = table.pack(...)
   local merged = {}

   for i = 1, args.n do
      if type(args[i]) == 'string' then
         error(args[i])
      end
      for k, v in pairs(args[i]) do
         merged[k] = v
      end
   end

   return merged
end

--- @param module string
--- @return any
function M.req(module)
   local m = require(module)
   return m
end

--- Returns a new list with function applied to each element of the list
--- @generic T
--- @generic G
--- @param list T[]
--- @param func fun(t: T): G
--- @return G[]
function M.map(list, func)
   local mapped = {}
   for i, v in ipairs(list) do
      mapped[i] = func(v)
   end

   return mapped
end

function M.dump(o, level)
  -- a shitty pretty print implementation
  level = level or 0
  if type(o) == 'table' then
    local l = string.rep('  ', level)
    local s = l .. '{\n'
    local c = l .. '}'
    for k,v in pairs(o) do
      if type(k) ~= 'number' then
        k = '"'..tostring(k)..'"'
      end
      s = s .. l .. '['..tostring(k)..'] = ' .. my_utils.dump(v, level + 1) .. ',\n'
    end
    return s .. c
   else
    return tostring(o)
   end
end


return M
