local M = {}

--- Copies every table in `...` into `target`, later tables winning on key
--- collisions. `target` is filled in place (it may be a config_builder object,
--- which validates keys on assignment) and returned.
--- @param target table
--- @param ... table[]
--- @return table
function M.merge(target, ...)
  local args = table.pack(...)

  for i = 1, args.n do
    if type(args[i]) == 'string' then
      error(args[i])
    end
    for k, v in pairs(args[i]) do
      target[k] = v
    end
  end

  return target
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
    for k, v in pairs(o) do
      if type(k) ~= 'number' then
        k = '"' .. tostring(k) .. '"'
      end
      s = s .. l .. '[' .. tostring(k) .. '] = ' .. M.dump(v, level + 1) .. ',\n'
    end
    return s .. c
  else
    return tostring(o)
  end
end

return M
