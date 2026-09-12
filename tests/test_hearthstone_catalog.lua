local T, QR = ...
local areaNames = require("fixtures.hearthstone_area_names")

local function isolated(locale, body)
    local saved = {}
    local function replace(tbl, key, value)
        saved[#saved + 1] = { tbl, key, tbl[key] }
        tbl[key] = value
    end
    local name, calls = areaNames[locale][14771], 0
    replace(QR.db, "hearthstoneBinds", {})
    replace(QR.Hearthstone, "innIndex", nil)
    replace(QR.Hearthstone, "innIndexIncomplete", nil)
    replace(QR.PathCalculator, "graphDirty", false)
    replace(_G, "UnitGUID", function() return "Player-Catalog-Test" end)
    replace(_G, "GetBindLocation", function() return name end)
    replace(C_Map, "GetAreaInfo", function(id)
        calls = calls + 1
        return areaNames[locale][id]
    end)
    local ok, err = pcall(body, function(value) name = value end, function() return calls end)
    for i = #saved, 1, -1 do
        local entry = saved[i]
        entry[1][entry[2]] = entry[3]
    end
    if not ok then error(err) end
end

T:run("Hearthstone catalog: shipped records match the reviewed client-data snapshot", function(t)
    t:assertEqual("table", type(QR.HearthstoneLocations), "The real catalog loads through the addon manifest")
    if type(QR.HearthstoneLocations) ~= "table" then return end
    local ids, maps, positions, blockers = {}, {}, 0, 0
    for _, entry in ipairs(QR.HearthstoneLocations) do
        t:assert(type(entry.areaID) == "number" and entry.areaID > 0 and entry.areaID % 1 == 0,
            "Every record has an integer AreaTable ID")
        t:assertNil(ids[entry.areaID], "Area ID " .. tostring(entry.areaID) .. " is not repeated")
        ids[entry.areaID] = true
        for _, locale in ipairs({ "enUS", "deDE" }) do
            t:assertNotNil(areaNames[locale][entry.areaID], locale .. " contains client data for " .. entry.areaID)
        end
        if entry.ambiguous then
            blockers = blockers + 1
            t:assertNil(entry.mapID, "Blocked area " .. entry.areaID .. " cannot carry a route destination")
        else
            positions = positions + 1
            t:assert(type(entry.mapID) == "number" and entry.mapID > 0 and entry.mapID % 1 == 0,
                "Inn " .. entry.areaID .. " has an integer UI map ID")
            t:assert(type(entry.x) == "number" and entry.x >= 0 and entry.x <= 1
                and type(entry.y) == "number" and entry.y >= 0 and entry.y <= 1,
                "Inn " .. entry.areaID .. " has finite normalized coordinates")
            maps[entry.mapID] = true
        end
    end
    local mapCount = 0
    for _ in pairs(maps) do mapCount = mapCount + 1 end
    t:assertEqual(119, #QR.HearthstoneLocations, "The published 2026-09-12 snapshot has 119 records")
    t:assertEqual(58, positions, "The published snapshot has 58 sourced inn approximations")
    t:assertEqual(61, blockers, "The published snapshot preserves 61 explicit ambiguity/phase blockers")
    t:assertEqual(43, mapCount, "The published inn positions cover 43 distinct UI maps")
end)

for _, locale in ipairs({ "enUS", "deDE" }) do
    T:run("Hearthstone catalog: all real " .. locale .. " names build a complete reusable index", function(t)
        isolated(locale, function(bindTo, calls)
            local resolved = 0
            for _, entry in ipairs(QR.HearthstoneLocations) do
                local name = areaNames[locale][entry.areaID]
                bindTo(name)
                local point = QR.Hearthstone:GetDestination()
                if entry.ambiguous then
                    t:assertNil(point, locale .. " ambiguity blocker " .. entry.areaID .. " remains unresolved")
                else
                    t:assertNotNil(point, locale .. " sourced inn " .. entry.areaID .. " resolves before first use")
                    if point then
                        resolved = resolved + 1
                        t:assertEqual(entry.mapID, point.mapID, "Inn " .. entry.areaID .. " retains its source UI map")
                        t:assertEqual("INN_DATABASE", point.source, "Inn " .. entry.areaID .. " retains inferred provenance")
                        t:assertTrue(point.isApproximate, "Inn " .. entry.areaID .. " does not claim an exact landing")
                    end
                end
            end
            t:assertEqual(58, resolved, locale .. " resolves all 58 unambiguous snapshot bindings")
            t:assertEqual(119, calls(), "Each of the 119 real names is localized once for " .. locale)
            t:assertEqual(false, QR.Hearthstone.innIndexIncomplete, "The complete " .. locale .. " fixture permits inference")
            t:assertNil(next(QR.db.hearthstoneBinds), "Catalog lookups never save inferred character observations")
        end)
    end)

    T:run("Hearthstone catalog: " .. locale .. " Dornogal uses the sourced inn point", function(t)
        isolated(locale, function(bindTo)
            bindTo(areaNames[locale][14771])
            local point = QR.Hearthstone:GetDestination()
            t:assertNotNil(point, "Dornogal resolves from its real " .. locale .. " client label")
            if point then
                t:assertEqual(2339, point.mapID, "Dornogal uses the city UI map")
                t:assertEqual(0.4482, point.x, "Dornogal X is the pinned TWW_Dorn.lua:64 source point")
                t:assertEqual(0.4649, point.y, "Dornogal Y is the pinned TWW_Dorn.lua:64 source point")
            end
        end)
    end)
end

T:run("Hearthstone catalog: real German Morgenluft needs phase evidence", function(t)
    isolated("deDE", function(bindTo)
        t:assertEqual("Morgenluft", areaNames.deDE[3462], "Legacy AreaTable 3462 uses the client's German name")
        t:assertEqual("Morgenluft", areaNames.deDE[15995], "Midnight AreaTable 15995 has the same German name")
        bindTo(areaNames.deDE[15995])
        t:assertNil(QR.Hearthstone:GetDestination(), "The real catalog cannot infer which Morgenluft is bound")
        QR.db.hearthstoneBinds["Player-Catalog-Test"] = {
            mapID = 2395, x = 0.463, y = 0.460, bindName = "Morgenluft", source = "HEARTHSTONE_ARRIVAL",
        }
        -- Synthetic observation exercises precedence, not a claim of a verified landing.
        local point = QR.Hearthstone:GetDestination()
        t:assertEqual(2395, point and point.mapID, "A later character observation supplies the missing world-map evidence")
        t:assertEqual("HEARTHSTONE_ARRIVAL", QR.db.hearthstoneBinds["Player-Catalog-Test"].source,
            "Catalog lookup preserves the stronger observation's stored provenance")
    end)
end)
