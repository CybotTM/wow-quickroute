-- export_data_json.lua
-- Load the Data\ files a TOC lists, the way the client does, and print the
-- resulting QR tables as JSON. Functions are left out.
--
-- Used by scripts/generate_forever_data.py to read the retail data without
-- parsing Lua in Python. Lua 5.1, no dependencies.
--
-- Usage: lua5.1 scripts/export_data_json.lua QuickRoute/QuickRoute.toc
--
-- JSON objects cannot carry number keys, so every key is written with its Lua
-- type: "n:84" is the number 84, "s:name" the string "name". The reader in
-- the generator turns them back.

local tocPath = arg[1]
if not tocPath then
    io.stderr:write("usage: lua5.1 export_data_json.lua <path to .toc>\n")
    os.exit(2)
end
local addonDir = tocPath:match("^(.*[/\\])") or "./"

local handle = io.open(tocPath, "r")
if not handle then
    io.stderr:write("cannot open " .. tocPath .. "\n")
    os.exit(2)
end
local files = {}
for line in handle:lines() do
    line = line:gsub("\r$", "")
    if line:match("^Data[\\/].+%.lua$") then
        files[#files + 1] = line:gsub("\\", "/")
    end
end
handle:close()
if #files == 0 then
    io.stderr:write("no Data\\ files listed in " .. tocPath .. "\n")
    os.exit(1)
end

-- The data files only touch QR at load time; nothing they run at file scope
-- calls the WoW API. A missing global would raise here, which is wanted.
local QR = {}
for _, rel in ipairs(files) do
    local chunk, err = loadfile(addonDir .. rel)
    if not chunk then
        io.stderr:write("load failed: " .. rel .. ": " .. tostring(err) .. "\n")
        os.exit(1)
    end
    local ok, runErr = pcall(chunk, "QuickRoute", QR)
    if not ok then
        io.stderr:write("run failed: " .. rel .. ": " .. tostring(runErr) .. "\n")
        os.exit(1)
    end
end

local escapes = {
    ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
    ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}
local function str(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        return escapes[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function num(n)
    if n ~= n or n == math.huge or n == -math.huge then
        error("non-finite number")
    end
    if n == math.floor(n) and math.abs(n) < 2 ^ 53 then
        return string.format("%d", n)
    end
    return string.format("%.17g", n)
end

local encode
local function key(k)
    local t = type(k)
    if t == "number" then return str("n:" .. num(k)) end
    if t == "string" then return str("s:" .. k) end
    error("unsupported key type " .. t)
end

encode = function(v, seen)
    local t = type(v)
    if t == "string" then return str(v) end
    if t == "number" then return num(v) end
    if t == "boolean" then return v and "true" or "false" end
    if t == "table" then
        if seen[v] then error("cycle in data") end
        seen[v] = true
        local keys = {}
        for k, item in pairs(v) do
            if type(item) ~= "function" then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b)
            local ta, tb = type(a), type(b)
            if ta ~= tb then return ta < tb end
            return a < b
        end)
        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts + 1] = key(k) .. ":" .. encode(v[k], seen)
        end
        seen[v] = nil
        return "{" .. table.concat(parts, ",") .. "}"
    end
    error("unsupported value type " .. t)
end

io.write(encode(QR, {}), "\n")
