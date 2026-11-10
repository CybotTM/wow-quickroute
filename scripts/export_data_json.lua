-- export_data_json.lua
-- Load the Data\ files a TOC lists, the way the client does, and print the
-- resulting QR tables as JSON. Functions are left out.
--
-- Used by scripts/generate_forever_data.py to read the retail data without
-- parsing Lua in Python. Lua 5.1, no dependencies.
--
-- Usage: lua5.1 scripts/export_data_json.lua QuickRoute/QuickRoute.toc
--        lua5.1 scripts/export_data_json.lua --zone-survey <SavedVariables/QuickRoute.lua>
--        lua5.1 scripts/export_data_json.lua --trace <SavedVariables/QuickRoute.lua>
--
-- The second form prints QuickRouteDB.zoneSurvey from a SavedVariables file,
-- for scripts/import_zone_survey.py. The third prints QuickRouteDB.trace, the
-- diagnostic trace, for scripts/export_trace.py: the ring buffer read back in
-- chronological order as `entries`, with the store's `client` and `dropped`.
-- The file is run in an empty environment: SavedVariables are plain
-- assignments, and nothing in it can reach a global.
--
-- JSON objects cannot carry number keys, so every key is written with its Lua
-- type: "n:84" is the number 84, "s:name" the string "name". The reader in
-- the generator turns them back.

local function fail(message, code)
    io.stderr:write(message .. "\n")
    os.exit(code or 1)
end

--- The QR namespace after running every Data\ file the TOC lists.
local function loadToc(tocPath)
    local addonDir = tocPath:match("^(.*[/\\])") or "./"
    local handle = io.open(tocPath, "r")
    if not handle then fail("cannot open " .. tocPath, 2) end
    local files = {}
    for line in handle:lines() do
        line = line:gsub("\r$", "")
        if line:match("^Data[\\/].+%.lua$") then
            files[#files + 1] = line:gsub("\\", "/")
        end
    end
    handle:close()
    if #files == 0 then fail("no Data\\ files listed in " .. tocPath) end

    -- The data files only touch QR at load time; nothing they run at file scope
    -- calls the WoW API. A missing global would raise here, which is wanted.
    local QR = {}
    for _, rel in ipairs(files) do
        local chunk, err = loadfile(addonDir .. rel)
        if not chunk then fail("load failed: " .. rel .. ": " .. tostring(err)) end
        local ok, runErr = pcall(chunk, "QuickRoute", QR)
        if not ok then fail("run failed: " .. rel .. ": " .. tostring(runErr)) end
    end
    return QR
end

--- QuickRouteDB.zoneSurvey from a SavedVariables file, or an empty table.
local function loadZoneSurvey(path)
    local chunk, err = loadfile(path)
    if not chunk then fail("cannot load " .. tostring(path) .. ": " .. tostring(err), 2) end
    local env = {}
    setfenv(chunk, env)
    local ok, runErr = pcall(chunk)
    if not ok then fail("cannot run " .. path .. ": " .. tostring(runErr)) end
    local db = env.QuickRouteDB
    local survey = type(db) == "table" and db.zoneSurvey
    return type(survey) == "table" and survey or {}
end

local function loadSavedVariables(path)
    local chunk, err = loadfile(path)
    if not chunk then fail("cannot load " .. tostring(path) .. ": " .. tostring(err), 2) end
    local env = {}
    setfenv(chunk, env)
    local ok, runErr = pcall(chunk)
    if not ok then fail("cannot run " .. path .. ": " .. tostring(runErr)) end
    return env.QuickRouteDB
end

--- QuickRouteDB.trace in chronological order. Diagnostics.lua writes it as a
-- ring buffer: `e` indexed 1..cap, `first` the oldest entry, `n` the count.
local function loadTrace(path)
    local db = loadSavedVariables(path)
    local store = type(db) == "table" and db.trace
    local result = { entries = {} }
    if type(store) ~= "table" or type(store.e) ~= "table" then return result end
    local cap, first, n = tonumber(store.cap), tonumber(store.first), tonumber(store.n)
    if not (cap and first and n) or cap < 1 then fail("malformed trace in " .. path) end
    for i = 0, n - 1 do
        local entry = store.e[((first - 1 + i) % cap) + 1]
        if type(entry) == "table" then result.entries[#result.entries + 1] = entry end
    end
    result.client = type(store.client) == "table" and store.client or nil
    result.dropped = tonumber(store.dropped) or 0
    result.cap = cap
    return result
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

local result
if arg[1] == "--zone-survey" then
    if not arg[2] then fail("usage: lua5.1 export_data_json.lua --zone-survey <file>", 2) end
    result = loadZoneSurvey(arg[2])
elseif arg[1] == "--trace" then
    if not arg[2] then fail("usage: lua5.1 export_data_json.lua --trace <file>", 2) end
    result = loadTrace(arg[2])
elseif arg[1] then
    result = loadToc(arg[1])
else
    fail("usage: lua5.1 export_data_json.lua <path to .toc> | --zone-survey <file> | --trace <file>", 2)
end
io.write(encode(result, {}), "\n")
