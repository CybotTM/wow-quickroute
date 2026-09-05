local T, QR, MockWoW = ...

local function Isolated(fn)
    MockWoW:Reset()
    QR.PlayerInfo:InvalidateCache()
    local saved = {}
    local function set(owner, key, value)
        saved[#saved + 1] = { owner, key, owner[key] }
        owner[key] = value
    end
    local ok, err = pcall(fn, set)
    for index = #saved, 1, -1 do
        local entry = saved[index]
        entry[1][entry[2]] = entry[3]
    end
    MockWoW:Reset()
    QR.PlayerInfo:InvalidateCache()
    QR.PlayerInventory:ScanAll()
    if not ok then error(err) end
end

local function FindEntry(id)
    for _, entry in ipairs(QR.TeleportPanel:CollectAllTeleports()) do
        if entry.id == id then return entry end
    end
end

local function Race(set, token)
    set(_G, "UnitRace", function() return token, token end)
    QR.PlayerInfo:InvalidateCache()
end

T:run("Teleport eligibility: collected Peacebloom is unavailable to a non-Worgen", function(t)
    Isolated(function(set)
        Race(set, "Human")
        MockWoW.config.ownedToys[211788] = true
        -- An optimistic client answer cannot override the documented race gate.
        set(C_ToyBox, "IsToyUsable", function() return true end)
        QR.PlayerInventory:ScanAll()
        t:assertTrue(QR.PlayerInventory:HasTeleport(211788), "The account still owns Peacebloom")
        t:assertFalse(QR.PlayerInventory:GetAllTeleports()[211788].isUsable,
            "Collected Peacebloom cannot be used by a Human")
        t:assertEqual("STATUS_NA", FindEntry(211788).status.key,
            "The inventory does not advertise the racial toy as ready")
        local pc, graph = QR.PathCalculator, QR.Graph:New()
        graph:AddNode("Player Location", { mapID = 84, x = 0.5, y = 0.5 })
        set(pc, "graph", graph)
        -- A cached or integration-supplied usable flag cannot bypass the gate.
        set(QR.PlayerInventory, "GetAllTeleports", function()
            return { [211788] = { data = QR.TeleportItemsData[211788], sourceType = "toy", isUsable = true } }
        end)
        pc:AddPlayerTeleportEdges()
        t:assertNil(graph.edges["Player Location"]["Travel:GILNEAS"],
            "A Human cannot receive a Peacebloom teleport route")
    end)
end)

T:run("Teleport eligibility: a Worgen keeps ready and cooldown Peacebloom states", function(t)
    Isolated(function(set)
        Race(set, "Worgen")
        MockWoW.config.ownedToys[211788] = true
        QR.PlayerInventory:ScanAll()
        t:assertTrue(QR.PlayerInventory:GetAllTeleports()[211788].isUsable,
            "A Worgen can use collected Peacebloom")
        set(QR.CooldownTracker, "GetCooldown", function() return { ready = true, remaining = 0 } end)
        t:assertEqual("STATUS_READY", FindEntry(211788).status.key,
            "An eligible off-cooldown Worgen toy remains ready")
        set(QR.CooldownTracker, "GetCooldown", function() return { ready = false, remaining = 42 } end)
        local entry = FindEntry(211788)
        t:assertEqual("STATUS_ON_CD", entry.status.key, "Eligible toy retains its cooldown state")
        t:assertEqual(42, entry.cooldownRemaining, "Eligible toy retains the actual cooldown duration")
    end)
end)

T:run("Teleport eligibility: toy API rejection and unknown answers never appear ready", function(t)
    Isolated(function(set)
        Race(set, "Worgen")
        MockWoW.config.ownedToys[140192] = true
        local secret = {}
        set(_G, "issecretvalue", function(value) return value == secret end)
        for _, mode in ipairs({ "rejected", "unknown", "error", "secret" }) do
            set(C_ToyBox, "IsToyUsable", function()
                if mode == "rejected" then return false end
                if mode == "error" then error("toy data unavailable") end
                if mode == "secret" then return secret end
            end)
            QR.PlayerInventory:ScanAll()
            t:assertTrue(QR.PlayerInventory:HasTeleport(140192), "API " .. mode .. " does not erase ownership")
            t:assertFalse(QR.PlayerInventory:GetAllTeleports()[140192].isUsable,
                "API " .. mode .. " prevents route eligibility")
            t:assertEqual("STATUS_UNAVAILABLE", FindEntry(140192).status.key,
                "API " .. mode .. " is displayed without a green ready state")
        end
    end)
end)

T:run("Teleport eligibility: the mini panel excludes collected racial and rejected toys", function(t)
    Isolated(function(set)
        Race(set, "Human")
        MockWoW.config.ownedToys[211788] = true
        MockWoW.config.ownedToys[140192] = true
        set(C_ToyBox, "IsToyUsable", function(id) return id == 211788 end)
        local panel = QR.MiniTeleportPanel
        for _, key in ipairs({ "rows", "rowPool", "secureButtons" }) do set(panel, key, {}) end
        for _, key in ipairs({ "frame", "separator" }) do set(panel, key, nil) end
        panel:CreateFrame()
        panel:RefreshList()
        t:assertEqual(0, #panel.secureButtons, "No unusable toy gets an activation overlay in the mini panel")
        t:assertEqual(QR.L["MINI_PANEL_NO_TELEPORTS"], panel.rows[1].nameLabel:GetText(),
            "The mini panel excludes both the racial restriction and client-rejected toy")
        panel.frame:Hide()
    end)
end)

T:run("Teleport eligibility: legacy engineering metadata is enforced by the route guard", function(t)
    Isolated(function(set)
        set(QR.PlayerInfo, "HasEngineering", function() return false end)
        local pc, graph = QR.PathCalculator, QR.Graph:New()
        graph:AddNode("Player Location", { mapID = 84, x = 0.5, y = 0.5 })
        set(pc, "graph", graph)
        set(QR.PlayerInventory, "GetAllTeleports", function()
            return { [1] = { sourceType = "item", data = { mapID = 85, x = 0.5, y = 0.5,
                destination = "Engineering Landing", profession = "Engineering", type = "engineer" } } }
        end)
        pc:AddPlayerTeleportEdges()
        t:assertNil(graph.edges["Player Location"]["Engineering Landing"],
            "The profession field blocks routing even without requiresEngineering")
    end)
end)

T:run("Teleport eligibility: unknown race cannot grant Worgen-only access", function(t)
    Isolated(function(set)
        Race(set, nil)
        MockWoW.config.ownedToys[211788] = true
        QR.PlayerInventory:ScanAll()
        t:assertFalse(QR.PlayerInventory:GetAllTeleports()[211788].isUsable,
            "Missing race information never grants Worgen-only travel")
    end)
end)
