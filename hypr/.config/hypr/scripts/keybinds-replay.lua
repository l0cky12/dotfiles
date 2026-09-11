-- Evaluate keybindings.lua with a non-mutating Hyprland facade and emit the
-- bind metadata that `hyprctl binds` loses for Lua dispatchers.
local keybindings = assert(arg[1], "keybindings.lua path is required")
local hypr_root = assert(arg[2], "Hyprland config root is required")

local modifiers = { SHIFT = 1, CTRL = 4, CONTROL = 4, ALT = 8, SUPER = 64 }

local function split_keys(keys)
    local modmask, key = 0, ""
    for part in tostring(keys or ""):gmatch("[^+]+") do
        local value = part:gsub("^%s+", ""):gsub("%s+$", "")
        local modifier = modifiers[value:upper()]
        if modifier then
            modmask = modmask + modifier
        else
            key = value
        end
    end
    return modmask, key
end

local function json_string(value)
    return '"' .. tostring(value or "")
        :gsub("\\", "\\\\"):gsub('"', '\\"')
        :gsub("\b", "\\b"):gsub("\f", "\\f")
        :gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t") .. '"'
end

local function lua_literal(value)
    local kind = type(value)
    if kind == "string" then
        return string.format("%q", value)
    elseif kind == "number" or kind == "boolean" then
        return tostring(value)
    elseif kind == "nil" then
        return "nil"
    elseif kind ~= "table" then
        return "nil"
    end

    local parts, keys = {}, {}
    local array_length = #value
    for index = 1, array_length do
        parts[#parts + 1] = lua_literal(value[index])
    end
    for key in pairs(value) do
        if not (type(key) == "number" and key >= 1 and key <= array_length
                and math.floor(key) == key) then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    for _, key in ipairs(keys) do
        local prefix = type(key) == "string" and key:match("^[%a_][%w_]*$")
            and (key .. " = ") or ("[" .. lua_literal(key) .. "] = ")
        parts[#parts + 1] = prefix .. lua_literal(value[key])
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local function expression(path, ...)
    local args = {}
    for index = 1, select("#", ...) do
        args[index] = lua_literal(select(index, ...))
    end
    return path .. "(" .. table.concat(args, ", ") .. ")"
end

local function action(dispatcher, argument)
    return { __keybind_action = true, dispatcher = dispatcher, arg = argument or "" }
end

local function proxy(path)
    return setmetatable({ path = path }, {
        __index = function(self, key) return proxy(self.path .. "." .. tostring(key)) end,
        __call = function(self, ...)
            local first = ...
            if self.path == "hl.dsp.exec_cmd" and type(first) == "string" then
                return action("exec", first)
            elseif self.path == "hl.dsp.window.close" then
                return action("killactive", "")
            elseif self.path == "hl.dsp.exit" then
                return action("exit", "")
            end
            local call = expression(self.path, ...)
            return action("lua", call)
        end,
    })
end

local noop
noop = setmetatable({}, {
    __index = function() return noop end,
    __call = function() return noop end,
})

local rows = {}
local dispatched = nil
hl = setmetatable({
    dsp = proxy("hl.dsp"),
    dispatch = function(value) dispatched = value end,
    bind = function(keys, bind_action, opts)
        opts = opts or {}
        local resolved = bind_action
        if type(bind_action) == "function" then
            dispatched = nil
            local ok = pcall(bind_action)
            if ok then resolved = dispatched end
        end
        local dispatcher, argument = "", ""
        if type(resolved) == "table" and resolved.__keybind_action then
            dispatcher, argument = resolved.dispatcher, resolved.arg
        elseif type(resolved) == "string" and resolved ~= "" then
            dispatcher, argument = "exec", resolved
        end
        local modmask, key = split_keys(keys)
        rows[#rows + 1] = {
            modmask = modmask,
            description = opts.description or "",
            key = key,
            dispatcher = dispatcher,
            arg = argument,
        }
        return noop
    end,
    get_config = function() return nil end,
}, { __index = function() return noop end })

package.path = hypr_root .. "/?.lua;" .. package.path
local ok, err = pcall(dofile, keybindings)
if not ok then
    io.stderr:write("keybindings replay failed: " .. tostring(err) .. "\n")
    os.exit(1)
end

io.write("[")
for index, row in ipairs(rows) do
    if index > 1 then io.write(",") end
    io.write(string.format(
        '{"modmask":%d,"description":%s,"key":%s,"dispatcher":%s,"arg":%s}',
        row.modmask, json_string(row.description), json_string(row.key),
        json_string(row.dispatcher), json_string(row.arg)))
end
io.write("]\n")
