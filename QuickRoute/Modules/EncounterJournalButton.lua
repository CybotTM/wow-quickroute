-- EncounterJournalButton.lua
-- Adds a QuickRoute "Route to entrance" button on the Encounter Journal frame
-- when viewing a specific dungeon/raid instance.
local ADDON_NAME, QR = ...

-- Cache frequently-used globals
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local PlaySound = PlaySound

-------------------------------------------------------------------------------
-- EncounterJournalButton Module
-------------------------------------------------------------------------------
QR.EncounterJournalButton = {
    button = nil,
    initialized = false,
    hookedEJ = false,
}

local EJB = QR.EncounterJournalButton

-------------------------------------------------------------------------------
-- Button Creation
-------------------------------------------------------------------------------

--- Create the route button
-- @return Frame The created button
function EJB:CreateButton()
    if self.button then return self.button end

    local L = QR.L

    local btn = QR.CreateModernButton(UIParent, 120, 22)
    btn:SetText(L["DUNGEON_ROUTE_TO"])
    btn:Hide()

    -- OnClick: route to the current instance entrance
    btn:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
        EJB:RouteToCurrentInstance()
    end)

    -- OnEnter: show tooltip with branding
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["DUNGEON_ROUTE_TO"], 1, 1, 1, 1, true)
        GameTooltip:AddLine(L["EJ_ROUTE_BUTTON_TT"], 0.7, 0.7, 0.7, true)
        QR.AddTooltipBranding(GameTooltip)
        GameTooltip:Show()
    end)

    -- OnLeave: hide tooltip
    btn:SetScript("OnLeave", function()
        GameTooltip_Hide()
    end)

    -- Add micro icon for brand identification
    QR.AddMicroIcon(btn, 16)

    self.button = btn
    return btn
end

-------------------------------------------------------------------------------
-- Routing
-------------------------------------------------------------------------------

--- Route to the instance currently displayed in the Encounter Journal
function EJB:RouteToCurrentInstance()
    if not EncounterJournal then
        QR:Debug("EJB: EncounterJournal not available")
        return
    end

    local instanceID = EncounterJournal.instanceID
    if not instanceID then
        QR:Debug("EJB: No instanceID on EncounterJournal")
        return
    end

    if not (QR.DungeonData and QR.DungeonData.GetInstance) then
        QR:Debug("EJB: DungeonData not available")
        return
    end

    local inst = QR.DungeonData:GetInstance(instanceID)
    if not inst then
        QR:Debug("EJB: No data for instanceID " .. tostring(instanceID))
        return
    end

    if not inst.zoneMapID or not inst.x or not inst.y then
        QR:Debug("EJB: Missing coordinates for instanceID " .. tostring(instanceID))
        return
    end

    if QR.POIRouting and QR.POIRouting.RouteToMapPosition then
        QR.POIRouting:RouteToMapPosition(inst.zoneMapID, inst.x, inst.y)
    end
end

-------------------------------------------------------------------------------
-- Button Visibility
-------------------------------------------------------------------------------

--- Update button visibility based on EJ state
function EJB:UpdateButton()
    if not self.button then return end
    if InCombatLockdown() then return end

    -- Check if EJ exists and is shown
    if not EncounterJournal or not EncounterJournal:IsShown() then
        self.button:Hide()
        return
    end

    -- Check if there is a valid instance displayed
    local instanceID = EncounterJournal.instanceID
    if not instanceID then
        self.button:Hide()
        return
    end

    -- Check if DungeonData has data with coordinates for this instance
    if QR.DungeonData and QR.DungeonData.GetInstance then
        local inst = QR.DungeonData:GetInstance(instanceID)
        if inst and inst.zoneMapID and inst.x and inst.y then
            self.button:ClearAllPoints()
            self.button:SetPoint("TOPRIGHT", EncounterJournal, "TOPRIGHT", -20, -30)
            self.button:Show()
            return
        end
    end

    self.button:Hide()
end

-------------------------------------------------------------------------------
-- Encounter Journal Hooks
-------------------------------------------------------------------------------

--- Hook the Encounter Journal frame to track show/hide/instance changes
function EJB:HookEncounterJournal()
    if self.hookedEJ then return end
    if not EncounterJournal then return end

    -- Hook Show
    hooksecurefunc(EncounterJournal, "Show", function()
        EJB:UpdateButton()
    end)

    -- Hook Hide
    hooksecurefunc(EncounterJournal, "Hide", function()
        if EJB.button then
            EJB.button:Hide()
        end
    end)

    -- Hook EncounterJournal_DisplayInstance if it exists (Blizzard function)
    if EncounterJournal_DisplayInstance then
        hooksecurefunc("EncounterJournal_DisplayInstance", function()
            EJB:UpdateButton()
        end)
    end

    self.hookedEJ = true
    QR:Debug("EncounterJournalButton: hooked EJ")
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

--- Initialize the module
-- Creates the button and hooks EJ (or waits for it to load)
function EJB:Initialize()
    if self.initialized then return end
    self.initialized = true

    self:CreateButton()

    -- If EncounterJournal is already loaded, hook immediately
    if EncounterJournal then
        self:HookEncounterJournal()
    else
        -- Wait for Blizzard_EncounterJournal to load
        local eventFrame = CreateFrame("Frame")
        eventFrame:RegisterEvent("ADDON_LOADED")
        eventFrame:SetScript("OnEvent", function(frame, event, addonName)
            if addonName == "Blizzard_EncounterJournal" then
                frame:UnregisterEvent("ADDON_LOADED")
                EJB:HookEncounterJournal()
            end
        end)
    end

    QR:Debug("EncounterJournalButton initialized")
end
