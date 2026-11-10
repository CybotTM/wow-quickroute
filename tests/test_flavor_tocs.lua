-------------------------------------------------------------------------------
-- test_flavor_tocs.lua
-- QuickRoute.toc (retail) and QuickRoute_Camelot.toc (WoW Forever) load the same
-- code over two data sets. This file runs in the retail suite and checks that
-- the retail load is unaffected by the second TOC, and that the two data sets
-- define the same tables, so every consumer finds what it reads on either.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

local addonDir = "QuickRoute/"
local loader = package.loaded["addon_loader"]

local function readFile(path)
    local handle = io.open(path, "r")
    if not handle then return nil end
    local content = handle:read("*a")
    handle:close()
    return content
end

local function metadata(toc)
    local meta = {}
    for line in (readFile(addonDir .. toc) or ""):gmatch("[^\r\n]+") do
        local key, value = line:match("^##%s*([^:]+):%s*(.-)%s*$")
        if key then meta[key] = value end
    end
    return meta
end

--- Load the Data\ files a TOC lists into a fresh namespace, as the client would.
local function loadDataSet(toc)
    local files = loader:ReadTocFiles(addonDir .. toc) or {}
    local ns, failures = {}, {}
    for _, file in ipairs(files) do
        if file:match("^Data/") then
            local chunk, err = loadfile(addonDir .. file)
            local ok, runErr = false, err
            if chunk then ok, runErr = pcall(chunk, "QuickRoute", ns) end
            if not ok then failures[#failures + 1] = file .. ": " .. tostring(runErr) end
        end
    end
    return ns, failures
end

T:run("Flavor TOCs: the retail suite loads QuickRoute.toc and no Forever data", function(t)
    t:assertEqual("QuickRoute.toc", loader.toc, "TOC the retail suite loaded")
    local forever = {}
    for _, file in ipairs(loader.files) do
        if file:match("^Data/Forever/") then forever[#forever + 1] = file end
    end
    t:assertEqual(0, #forever, "Data/Forever files in the retail load (" .. table.concat(forever, ", ") .. ")")
    t:assertFalse(QR.IsForever, "QR.IsForever on a client without WOW_PROJECT_CAMELOT")
    t:assertNotNil(QR.FlightPoints[84], "retail Stormwind (84) flight master")
    t:assertNil(QR.FlightPoints[1453], "no Forever Stormwind (1453) entry in the retail data")
    t:assertNotNil(QR.PhasePanel, "the retail TOC still loads PhasePanel")
    -- The route tab creates its phase button only when PhasePanel is loaded;
    -- on retail it must still be there.
    QR.MainFrame:Show()
    t:assertNotNil(QR.UI.frame and QR.UI.frame.phaseButton, "phase button on the retail route tab")
    QR.MainFrame:Hide()
end)

T:run("Flavor TOCs: QuickRoute_Camelot.toc carries the retail metadata and interface 16001", function(t)
    local retail, forever = metadata("QuickRoute.toc"), metadata("QuickRoute_Camelot.toc")
    t:assertEqual("16001", forever.Interface, "Camelot TOC interface")
    for key, value in pairs(retail) do
        if key ~= "Interface" then
            t:assertEqual(value, forever[key], "Camelot TOC ## " .. key)
        end
    end
    for key in pairs(forever) do
        t:assertNotNil(retail[key], "## " .. key .. " also in QuickRoute.toc")
    end
end)

T:run("Flavor TOCs: both TOCs load the same code; only PhasePanel is left out of Camelot", function(t)
    local function code(toc)
        local set = {}
        for _, file in ipairs(loader:ReadTocFiles(addonDir .. toc) or {}) do
            if not file:match("^Data/") then set[file] = true end
        end
        return set
    end
    local retail, forever = code("QuickRoute.toc"), code("QuickRoute_Camelot.toc")
    local missing, extra = {}, {}
    for file in pairs(retail) do
        if not forever[file] and file ~= "Modules/PhasePanel.lua" then missing[#missing + 1] = file end
    end
    for file in pairs(forever) do
        if not retail[file] then extra[#extra + 1] = file end
    end
    t:assertNil(forever["Modules/PhasePanel.lua"], "Camelot TOC loads PhasePanel")
    t:assertEqual(0, #missing, "retail code files missing from Camelot (" .. table.concat(missing, ", ") .. ")")
    t:assertEqual(0, #extra, "Camelot code files not in retail (" .. table.concat(extra, ", ") .. ")")
end)

T:run("Flavor TOCs: both data sets define the same QR tables with the same types", function(t)
    local retail, retailFailures = loadDataSet("QuickRoute.toc")
    local forever, foreverFailures = loadDataSet("QuickRoute_Camelot.toc")
    t:assertEqual(0, #retailFailures, "retail data files that failed (" .. table.concat(retailFailures, "; ") .. ")")
    t:assertEqual(0, #foreverFailures, "Forever data files that failed (" .. table.concat(foreverFailures, "; ") .. ")")
    local count = 0
    for key, value in pairs(retail) do
        count = count + 1
        t:assertEqual(type(value), type(forever[key]), "QR." .. key .. " type in the Forever data")
    end
    for key, value in pairs(forever) do
        t:assertEqual(type(value), type(retail[key]), "QR." .. key .. " type in the retail data")
    end
    t:assertGreaterThan(count, 25, "QR keys the retail data files define")
end)
