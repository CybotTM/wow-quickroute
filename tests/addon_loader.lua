-------------------------------------------------------------------------------
-- addon_loader.lua
-- Simulates the WoW addon loading process for standalone testing.
-- Creates the addon namespace and loads files in .toc order.
-------------------------------------------------------------------------------

local AddonLoader = {}

--- Load the addon files in .toc order, simulating the WoW loading process.
-- Each .lua file is loaded with the addon name and namespace table as
-- the varargs (...), matching WoW's behavior of:
--   local ADDON_NAME, namespace = ...
--
-- @param MockWoW table The mock framework (must be installed already)
-- @param options table Optional overrides: { addonName, quiet }
-- @return table The QR addon namespace
function AddonLoader:Load(MockWoW, options)
    options = options or {}
    local addonName = options.addonName or "QuickRoute"
    local quiet = options.quiet or false
    local addonDir = options.addonDir

    if not addonDir then
        -- Derive from package path - assume tests/ is alongside QuickRoute/
        local info = debug.getinfo(1, "S")
        local thisFile = info.source:gsub("^@", "")
        local testsDir = thisFile:match("(.*/)")
        addonDir = testsDir .. "../QuickRoute/"
    end

    -- Create the addon namespace table
    local QR = {}

    -- File load order from .toc (excluding embeds.xml and test files)
    local files = {
        "Localization.lua",
        "Utils/Colors.lua",
        "Utils/WindowFactory.lua",
        "Utils/PlayerInfo.lua",
        "Data/TeleportItems.lua",
        "Data/Portals.lua",
        "Data/ZoneAdjacency.lua",
        "Data/DungeonEntrances.lua",
        "Core/Graph.lua",
        "Core/TravelTime.lua",
        "Core/PathCalculator.lua",
        "Modules/PlayerInventory.lua",
        "Modules/CooldownTracker.lua",
        "Modules/WaypointIntegration.lua",
        "Modules/MainFrame.lua",
        "Modules/TeleportPanel.lua",
        "Modules/SecureButtons.lua",
        "Modules/UI.lua",
        "Modules/MinimapButton.lua",
        "Modules/MiniTeleportPanel.lua",
        "Modules/MapSidebar.lua",
        "Modules/MapTeleportButton.lua",
        "Modules/POIRouting.lua",
        "Modules/DungeonData.lua",
        "Modules/DungeonPicker.lua",
        "Modules/QuestTeleportButtons.lua",
        "Modules/SettingsPanel.lua",
        "QuickRoute.lua",
    }

    -- Load each file, passing (ADDON_NAME, QR) as varargs
    local loadedCount = 0
    local failedFiles = {}

    for _, relPath in ipairs(files) do
        local fullPath = addonDir .. relPath

        -- Load the file as a function
        local chunk, err = loadfile(fullPath)
        if not chunk then
            if not quiet then
                print("[LOADER] FAILED to load: " .. relPath .. " - " .. tostring(err))
            end
            failedFiles[#failedFiles + 1] = { path = relPath, error = err }
        else
            -- Execute with addon name and namespace as varargs
            -- WoW passes these as ... to each addon file
            local ok, runErr = pcall(chunk, addonName, QR)
            if not ok then
                if not quiet then
                    print("[LOADER] ERROR executing: " .. relPath .. " - " .. tostring(runErr))
                end
                failedFiles[#failedFiles + 1] = { path = relPath, error = runErr }
            else
                loadedCount = loadedCount + 1
                if not quiet then
                    print("[LOADER] Loaded: " .. relPath)
                end
            end
        end
    end

    if not quiet then
        print(string.format("[LOADER] Loaded %d/%d files (%d failures)",
            loadedCount, #files, #failedFiles))
    end

    -- Store metadata
    self.addonName = addonName
    self.namespace = QR
    self.loadedCount = loadedCount
    self.totalFiles = #files
    self.failedFiles = failedFiles

    return QR
end

--- Simulate the ADDON_LOADED event (triggers QR:Initialize)
-- @param MockWoW table The mock framework
function AddonLoader:FireAddonLoaded(MockWoW)
    MockWoW:FireEvent("ADDON_LOADED", self.addonName)
end

--- Simulate the PLAYER_LOGIN event (triggers QR:OnPlayerLogin)
-- Note: C_Timer.After is mocked to execute immediately, so the
-- deferred initialization will run synchronously.
-- @param MockWoW table The mock framework
function AddonLoader:FirePlayerLogin(MockWoW)
    MockWoW:FireEvent("PLAYER_LOGIN")
end

--- Perform full addon initialization: ADDON_LOADED + PLAYER_LOGIN
-- @param MockWoW table The mock framework
function AddonLoader:InitializeAddon(MockWoW)
    self:FireAddonLoaded(MockWoW)
    self:FirePlayerLogin(MockWoW)
end

--- Get the addon namespace
-- @return table The QR namespace
function AddonLoader:GetNamespace()
    return self.namespace
end

--- Check if all files loaded successfully
-- @return boolean True if no failures
function AddonLoader:AllFilesLoaded()
    return #self.failedFiles == 0
end

--- Get load status summary
-- @return string Human-readable status
function AddonLoader:GetStatus()
    if self:AllFilesLoaded() then
        return string.format("All %d files loaded successfully", self.loadedCount)
    end
    local failNames = {}
    for _, f in ipairs(self.failedFiles) do
        failNames[#failNames + 1] = f.path
    end
    return string.format("%d/%d files loaded, failures: %s",
        self.loadedCount, self.totalFiles, table.concat(failNames, ", "))
end

return AddonLoader
