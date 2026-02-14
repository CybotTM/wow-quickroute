-------------------------------------------------------------------------------
-- test_dungeonpicker.lua
-- Tests for DungeonPicker: popup panel for browsing dungeon/raid instances
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function resetState()
    MockWoW:Reset()
    MockWoW.config.inCombatLockdown = false
    MockWoW.config.playedSounds = {}

    -- Reset DungeonPicker state
    QR.DungeonPicker.frame = nil
    QR.DungeonPicker.isShowing = false
    QR.DungeonPicker.rows = {}
    QR.DungeonPicker.rowPool = {}
    QR.DungeonPicker.collapsedTiers = {}

    -- Ensure DungeonData is initialized
    local DD = QR.DungeonData
    DD.instances = {}
    DD.byZone = {}
    DD.byTier = {}
    DD.tierNames = {}
    DD.numTiers = 0
    DD.scanned = false
    DD.entrancesScanned = false
    DD:Initialize()
end

-------------------------------------------------------------------------------
-- 1. Module Structure
-------------------------------------------------------------------------------

T:run("DungeonPicker: module exists", function(t)
    t:assertNotNil(QR.DungeonPicker, "QR.DungeonPicker exists")
end)

T:run("DungeonPicker: has expected methods", function(t)
    local DP = QR.DungeonPicker
    t:assertNotNil(DP.CreatePickerFrame, "CreatePickerFrame exists")
    t:assertNotNil(DP.Show, "Show exists")
    t:assertNotNil(DP.Hide, "Hide exists")
    t:assertNotNil(DP.Toggle, "Toggle exists")
    t:assertNotNil(DP.RefreshList, "RefreshList exists")
    t:assertNotNil(DP.SelectInstance, "SelectInstance exists")
    t:assertNotNil(DP.RegisterCombat, "RegisterCombat exists")
    t:assertNotNil(DP.Initialize, "Initialize exists")
end)

-------------------------------------------------------------------------------
-- 2. Frame Creation
-------------------------------------------------------------------------------

T:run("DungeonPicker: CreatePickerFrame creates a frame", function(t)
    resetState()
    local DP = QR.DungeonPicker

    local frame = DP:CreatePickerFrame()
    t:assertNotNil(frame, "Frame created")
    t:assertNotNil(DP.frame, "Frame stored on module")
end)

T:run("DungeonPicker: frame is initially hidden", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:CreatePickerFrame()
    t:assertFalse(DP.frame:IsShown(), "Frame is hidden after creation")
    t:assertFalse(DP.isShowing, "isShowing is false initially")
end)

T:run("DungeonPicker: frame has title", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:CreatePickerFrame()
    t:assertNotNil(DP.frame.title, "Frame has title FontString")
end)

T:run("DungeonPicker: frame has search box", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:CreatePickerFrame()
    t:assertNotNil(DP.frame.searchBox, "Frame has search EditBox")
end)

T:run("DungeonPicker: frame has scroll frame", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:CreatePickerFrame()
    t:assertNotNil(DP.frame.scrollFrame, "Frame has ScrollFrame")
    t:assertNotNil(DP.frame.scrollChild, "Frame has scrollChild")
end)

T:run("DungeonPicker: frame has backdrop with muted border", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:CreatePickerFrame()
    local bc = DP.frame._backdropBorderColor
    if bc then
        -- Muted border color: (0.4, 0.4, 0.4, 0.8)
        t:assertTrue(bc[1] < 0.5, "Border R < 0.5 (muted)")
        t:assertTrue(bc[2] < 0.5, "Border G < 0.5 (muted)")
    end
end)

T:run("DungeonPicker: CreatePickerFrame is idempotent", function(t)
    resetState()
    local DP = QR.DungeonPicker

    local frame1 = DP:CreatePickerFrame()
    local frame2 = DP:CreatePickerFrame()
    t:assert(frame1 == frame2, "Second call returns same frame")
end)

-------------------------------------------------------------------------------
-- 3. Show / Hide / Toggle
-------------------------------------------------------------------------------

T:run("DungeonPicker: Show creates frame and shows it", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:Show()
    t:assertNotNil(DP.frame, "Frame created on Show")
    t:assertTrue(DP.frame:IsShown(), "Frame is shown after Show()")
    t:assertTrue(DP.isShowing, "isShowing is true after Show()")
end)

T:run("DungeonPicker: Hide hides the frame", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:Show()
    DP:Hide()
    t:assertFalse(DP.frame:IsShown(), "Frame is hidden after Hide()")
    t:assertFalse(DP.isShowing, "isShowing is false after Hide()")
end)

T:run("DungeonPicker: Toggle opens then closes", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:Toggle()
    t:assertTrue(DP.isShowing, "isShowing true after first Toggle")

    DP:Toggle()
    t:assertFalse(DP.isShowing, "isShowing false after second Toggle")
end)

T:run("DungeonPicker: Show in combat prints message and does not show", function(t)
    resetState()
    local DP = QR.DungeonPicker

    MockWoW.config.inCombatLockdown = true
    DP:Show()
    -- Should not be showing (combat lockdown)
    t:assertFalse(DP.isShowing, "isShowing false during combat")
end)

T:run("DungeonPicker: Show anchors to button when provided", function(t)
    resetState()
    local DP = QR.DungeonPicker

    local button = CreateFrame("Button")
    button:SetSize(100, 22)
    DP:Show(button)
    t:assertTrue(DP.isShowing, "Picker is showing after Show with anchor button")
end)

-------------------------------------------------------------------------------
-- 4. Tier Headers
-------------------------------------------------------------------------------

T:run("DungeonPicker: tier headers populated from DungeonData", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:Show()

    -- Check for tier header rows (rows with gold-colored text)
    local headerCount = 0
    for _, row in ipairs(DP.rows) do
        if row.nameLabel then
            local text = row.nameLabel:GetText() or ""
            -- Headers have the tier name (e.g. "Classic", "The War Within")
            if text:find("Classic") or text:find("The War Within") then
                headerCount = headerCount + 1
            end
        end
    end
    -- Mock has 2 tiers
    t:assertGreaterThan(headerCount, 0, "At least 1 tier header found (got " .. headerCount .. ")")
end)

T:run("DungeonPicker: tiers displayed newest first", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:Show()

    -- Find indices of tier headers
    local twwIndex, classicIndex = nil, nil
    for i, row in ipairs(DP.rows) do
        if row.nameLabel then
            local text = row.nameLabel:GetText() or ""
            if text:find("The War Within") then
                twwIndex = i
            elseif text:find("Classic") then
                classicIndex = i
            end
        end
    end

    if twwIndex and classicIndex then
        t:assertGreaterThan(classicIndex, twwIndex,
            "TWW header appears before Classic (TWW@" .. twwIndex .. ", Classic@" .. classicIndex .. ")")
    else
        t:assert(twwIndex ~= nil or classicIndex ~= nil, "At least one tier header found")
    end
end)

T:run("DungeonPicker: collapsing a tier hides its instances", function(t)
    resetState()
    local DP = QR.DungeonPicker

    -- Collapse tier 1 (Classic) before showing
    DP.collapsedTiers[1] = true
    DP:Show()

    -- Classic tier should be collapsed: only header, no instance rows
    local classicHeaderFound = false
    local rfcFound = false
    for _, row in ipairs(DP.rows) do
        if row.nameLabel then
            local text = row.nameLabel:GetText() or ""
            if text:find("Classic") then
                classicHeaderFound = true
            end
            if text:find("Ragefire") then
                rfcFound = true
            end
        end
    end

    t:assertTrue(classicHeaderFound, "Classic header still visible when collapsed")
    t:assertFalse(rfcFound, "RFC hidden when Classic tier is collapsed")
end)

-------------------------------------------------------------------------------
-- 5. Instance Rows
-------------------------------------------------------------------------------

T:run("DungeonPicker: instance rows show names", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:Show()

    -- Find Ragefire Chasm row
    local foundRFC = false
    for _, row in ipairs(DP.rows) do
        if row.nameLabel then
            local text = row.nameLabel:GetText() or ""
            if text:find("Ragefire Chasm") then
                foundRFC = true
            end
        end
    end
    t:assertTrue(foundRFC, "Ragefire Chasm row found in picker")
end)

T:run("DungeonPicker: raid rows show Raid tag", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:Show()

    -- Find Molten Core row (raid)
    local foundRaidTag = false
    for _, row in ipairs(DP.rows) do
        if row.nameLabel and row.tagLabel then
            local name = row.nameLabel:GetText() or ""
            local tag = row.tagLabel:GetText() or ""
            if name:find("Molten Core") then
                -- Tag should contain "Raid" (possibly with color codes)
                local L = QR.L
                local raidTag = L["DUNGEON_RAID_TAG"] or "Raid"
                foundRaidTag = tag:find(raidTag) ~= nil
            end
        end
    end
    t:assertTrue(foundRaidTag, "Molten Core row has Raid tag")
end)

T:run("DungeonPicker: dungeon rows show Dungeon tag", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:Show()

    local foundDungeonTag = false
    for _, row in ipairs(DP.rows) do
        if row.nameLabel and row.tagLabel then
            local name = row.nameLabel:GetText() or ""
            local tag = row.tagLabel:GetText() or ""
            if name:find("Ragefire Chasm") then
                local L = QR.L
                local dungeonTag = L["DUNGEON_TAG"] or "Dungeon"
                foundDungeonTag = tag:find(dungeonTag) ~= nil
            end
        end
    end
    t:assertTrue(foundDungeonTag, "RFC row has Dungeon tag")
end)

-------------------------------------------------------------------------------
-- 6. Search Filtering
-------------------------------------------------------------------------------

T:run("DungeonPicker: search 'rage' finds Ragefire Chasm", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:Show()

    -- Set search text
    DP.frame.searchBox:SetText("rage")
    -- Trigger refresh (normally OnTextChanged does this)
    DP:RefreshList()

    local foundRFC = false
    for _, row in ipairs(DP.rows) do
        if row.nameLabel then
            local text = row.nameLabel:GetText() or ""
            if text:find("Ragefire") then
                foundRFC = true
            end
        end
    end
    t:assertTrue(foundRFC, "Search 'rage' finds Ragefire Chasm")
end)

T:run("DungeonPicker: search 'zzz' finds nothing", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:Show()

    DP.frame.searchBox:SetText("zzz")
    DP:RefreshList()

    -- Should show "No matching instances" message
    local foundNoResults = false
    for _, row in ipairs(DP.rows) do
        if row.nameLabel then
            local text = row.nameLabel:GetText() or ""
            local L = QR.L
            local noResultsText = L["DUNGEON_PICKER_NO_RESULTS"] or "No matching instances"
            if text:find(noResultsText) then
                foundNoResults = true
            end
        end
    end
    t:assertTrue(foundNoResults, "Search 'zzz' shows no results message")
end)

T:run("DungeonPicker: search is case-insensitive", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:Show()

    -- Search with uppercase
    DP.frame.searchBox:SetText("RAGEFIRE")
    DP:RefreshList()

    local foundRFC = false
    for _, row in ipairs(DP.rows) do
        if row.nameLabel then
            local text = row.nameLabel:GetText() or ""
            if text:find("Ragefire") then
                foundRFC = true
            end
        end
    end
    t:assertTrue(foundRFC, "Case-insensitive search finds Ragefire")
end)

T:run("DungeonPicker: search expands collapsed tiers with matches", function(t)
    resetState()
    local DP = QR.DungeonPicker

    -- Collapse tier 1 (Classic)
    DP.collapsedTiers[1] = true
    DP:Show()

    -- RFC should be hidden when collapsed with no search
    local rfcBefore = false
    for _, row in ipairs(DP.rows) do
        if row.nameLabel and (row.nameLabel:GetText() or ""):find("Ragefire") then
            rfcBefore = true
        end
    end
    t:assertFalse(rfcBefore, "RFC hidden in collapsed tier before search")

    -- Search for "rage" should show RFC despite collapsed tier
    DP.frame.searchBox:SetText("rage")
    DP:RefreshList()

    local rfcAfter = false
    for _, row in ipairs(DP.rows) do
        if row.nameLabel and (row.nameLabel:GetText() or ""):find("Ragefire") then
            rfcAfter = true
        end
    end
    t:assertTrue(rfcAfter, "RFC visible when searching despite collapsed tier")
end)

T:run("DungeonPicker: empty search shows all instances", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:Show()

    -- Count rows with empty search (all instances + headers)
    local totalRowsNoSearch = #DP.rows

    -- Set search to empty
    DP.frame.searchBox:SetText("")
    DP:RefreshList()

    local totalRowsEmptySearch = #DP.rows
    t:assertEqual(totalRowsNoSearch, totalRowsEmptySearch,
        "Empty search shows same rows as no search")
end)

-------------------------------------------------------------------------------
-- 7. Instance Selection
-------------------------------------------------------------------------------

T:run("DungeonPicker: selecting instance triggers routing", function(t)
    resetState()
    local DP = QR.DungeonPicker

    -- Track POIRouting calls
    local routeCalled = false
    local routeMapID, routeX, routeY
    local origRoute = QR.POIRouting.RouteToMapPosition
    QR.POIRouting.RouteToMapPosition = function(self, mapID, x, y)
        routeCalled = true
        routeMapID = mapID
        routeX = x
        routeY = y
    end

    DP:Show()

    -- Select RFC (has coordinates from mock data)
    local rfc = QR.DungeonData:GetInstance(226)
    if rfc then
        DP:SelectInstance({
            name = rfc.name,
            zoneMapID = rfc.zoneMapID,
            x = rfc.x,
            y = rfc.y,
        })

        t:assertTrue(routeCalled, "POIRouting:RouteToMapPosition was called")
        t:assertEqual(rfc.zoneMapID, routeMapID, "Route mapID matches RFC zone")
        t:assertEqual(rfc.x, routeX, "Route x matches RFC entrance")
        t:assertEqual(rfc.y, routeY, "Route y matches RFC entrance")
    end

    -- Restore
    QR.POIRouting.RouteToMapPosition = origRoute
end)

T:run("DungeonPicker: selecting instance closes picker", function(t)
    resetState()
    local DP = QR.DungeonPicker

    -- Stub routing to avoid side effects
    local origRoute = QR.POIRouting.RouteToMapPosition
    QR.POIRouting.RouteToMapPosition = function() end

    DP:Show()
    t:assertTrue(DP.isShowing, "Picker is showing")

    DP:SelectInstance({
        name = "Test",
        zoneMapID = 85,
        x = 0.5,
        y = 0.5,
    })

    t:assertFalse(DP.isShowing, "Picker closed after selection")

    QR.POIRouting.RouteToMapPosition = origRoute
end)

T:run("DungeonPicker: selecting instance without coords shows message", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:Show()

    -- Select an instance without coordinates
    DP:SelectInstance({
        name = "Missing Instance",
    })

    -- Should not crash and picker should close
    t:assertFalse(DP.isShowing, "Picker closed even without coords")
end)

T:run("DungeonPicker: SelectInstance with nil does not crash", function(t)
    resetState()
    local DP = QR.DungeonPicker

    local ok, err = pcall(function()
        DP:SelectInstance(nil)
    end)
    t:assertTrue(ok, "SelectInstance(nil) does not crash: " .. tostring(err))
end)

-------------------------------------------------------------------------------
-- 8. ESC to Close (UISpecialFrames)
-------------------------------------------------------------------------------

T:run("DungeonPicker: frame registered in UISpecialFrames", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:CreatePickerFrame()

    local found = false
    for _, name in ipairs(UISpecialFrames) do
        if name == "QRDungeonPickerFrame" then
            found = true
            break
        end
    end
    t:assertTrue(found, "QRDungeonPickerFrame in UISpecialFrames")
end)

-------------------------------------------------------------------------------
-- 9. Combat Hiding
-------------------------------------------------------------------------------

T:run("DungeonPicker: combat callback hides picker", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:RegisterCombat()
    DP:Show()
    t:assertTrue(DP.isShowing, "Picker is showing before combat")

    -- Simulate entering combat via the centralized combat frame handler
    -- (MockWoW:Reset clears eventFrames, so we invoke the handler directly)
    MockWoW.config.inCombatLockdown = true
    local handler = QR.combatFrame and QR.combatFrame:GetScript("OnEvent")
    if handler then
        handler(QR.combatFrame, "PLAYER_REGEN_DISABLED")
    end

    t:assertFalse(DP.isShowing, "Picker hidden after combat starts")
end)

T:run("DungeonPicker: OnHide syncs isShowing", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:Show()
    t:assertTrue(DP.isShowing, "isShowing true after Show")

    -- Simulate frame being hidden (e.g., by ESC)
    DP.frame:Hide()
    t:assertFalse(DP.isShowing, "isShowing false after frame:Hide() (OnHide sync)")
end)

-------------------------------------------------------------------------------
-- 10. UX Consistency
-------------------------------------------------------------------------------

T:run("DungeonPicker: tooltip branding on instance row", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:Show()

    -- Find an instance row (not a header) and trigger OnEnter
    local tooltipBranded = false
    for _, row in ipairs(DP.rows) do
        if row.nameLabel then
            local text = row.nameLabel:GetText() or ""
            if text:find("Ragefire") then
                -- Trigger OnEnter
                local onEnter = row:GetScript("OnEnter")
                if onEnter then
                    MockWoW.config.tooltipHideCalls = 0
                    GameTooltip._calls = {}
                    onEnter(row)
                    -- Check AddTooltipBranding was called by looking for our brand line
                    for _, call in ipairs(GameTooltip._calls or {}) do
                        if call.method == "AddLine" and call.text then
                            local lineText = tostring(call.text)
                            if lineText:find("QuickRoute") then
                                tooltipBranded = true
                            end
                        end
                    end
                end
                break
            end
        end
    end
    t:assertTrue(tooltipBranded, "Instance row tooltip has QR branding")
end)

T:run("DungeonPicker: GameTooltip_Hide on instance row OnLeave", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:Show()

    for _, row in ipairs(DP.rows) do
        if row.nameLabel then
            local text = row.nameLabel:GetText() or ""
            if text:find("Ragefire") then
                local onLeave = row:GetScript("OnLeave")
                if onLeave then
                    local before = MockWoW.config.tooltipHideCalls or 0
                    onLeave(row)
                    local after = MockWoW.config.tooltipHideCalls or 0
                    t:assertGreaterThan(after, before, "GameTooltip_Hide called on OnLeave")
                end
                break
            end
        end
    end
end)

T:run("DungeonPicker: PlaySound on instance row click", function(t)
    resetState()
    local DP = QR.DungeonPicker

    -- Stub routing
    local origRoute = QR.POIRouting.RouteToMapPosition
    QR.POIRouting.RouteToMapPosition = function() end

    DP:Show()

    for _, row in ipairs(DP.rows) do
        if row.nameLabel then
            local text = row.nameLabel:GetText() or ""
            if text:find("Ragefire") then
                MockWoW.config.playedSounds = {}
                local onClick = row:GetScript("OnClick")
                if onClick then
                    onClick(row)
                end
                t:assertGreaterThan(#MockWoW.config.playedSounds, 0,
                    "PlaySound called on instance click")
                break
            end
        end
    end

    QR.POIRouting.RouteToMapPosition = origRoute
end)

T:run("DungeonPicker: PlaySound on tier header click", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:Show()

    for _, row in ipairs(DP.rows) do
        if row.nameLabel then
            local text = row.nameLabel:GetText() or ""
            if text:find("Classic") then
                MockWoW.config.playedSounds = {}
                local onClick = row:GetScript("OnClick")
                if onClick then
                    onClick(row)
                end
                t:assertGreaterThan(#MockWoW.config.playedSounds, 0,
                    "PlaySound called on tier header click")
                break
            end
        end
    end
end)

T:run("DungeonPicker: tooltip branding on tier header", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:Show()

    local tooltipBranded = false
    for _, row in ipairs(DP.rows) do
        if row.nameLabel then
            local text = row.nameLabel:GetText() or ""
            if text:find("Classic") then
                local onEnter = row:GetScript("OnEnter")
                if onEnter then
                    GameTooltip._calls = {}
                    onEnter(row)
                    for _, call in ipairs(GameTooltip._calls or {}) do
                        if call.method == "AddLine" and call.text then
                            local lineText = tostring(call.text)
                            if lineText:find("QuickRoute") then
                                tooltipBranded = true
                            end
                        end
                    end
                end
                break
            end
        end
    end
    t:assertTrue(tooltipBranded, "Tier header tooltip has QR branding")
end)

T:run("DungeonPicker: GameTooltip_Hide on tier header OnLeave", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:Show()

    for _, row in ipairs(DP.rows) do
        if row.nameLabel then
            local text = row.nameLabel:GetText() or ""
            if text:find("Classic") then
                local onLeave = row:GetScript("OnLeave")
                if onLeave then
                    local before = MockWoW.config.tooltipHideCalls or 0
                    onLeave(row)
                    local after = MockWoW.config.tooltipHideCalls or 0
                    t:assertGreaterThan(after, before, "GameTooltip_Hide called on tier header OnLeave")
                end
                break
            end
        end
    end
end)

T:run("DungeonPicker: title uses gold color", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:CreatePickerFrame()
    -- Title should have gold color (1, 0.82, 0)
    local title = DP.frame.title
    if title and title._textColorR then
        t:assertEqual(1, title._textColorR, "Title R = 1 (gold)")
        t:assertTrue(title._textColorG > 0.8 and title._textColorG < 0.85,
            "Title G ~= 0.82 (gold)")
        t:assertEqual(0, title._textColorB, "Title B = 0 (gold)")
    end
end)

-------------------------------------------------------------------------------
-- 11. Row Pool Management
-------------------------------------------------------------------------------

T:run("DungeonPicker: ReleaseAllRows clears rows", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:Show()
    t:assertGreaterThan(#DP.rows, 0, "Has rows after Show")

    DP:ReleaseAllRows()
    t:assertEqual(0, #DP.rows, "No rows after release")
end)

T:run("DungeonPicker: rows reused from pool", function(t)
    resetState()
    local DP = QR.DungeonPicker

    DP:Show()
    local poolSizeAfterFirst = #DP.rowPool

    -- Release and show again (should reuse pool)
    DP:ReleaseAllRows()
    DP:RefreshList()

    -- Pool should not grow beyond first allocation
    t:assertEqual(poolSizeAfterFirst, #DP.rowPool,
        "Pool size unchanged after reuse (was " .. poolSizeAfterFirst .. ", now " .. #DP.rowPool .. ")")
end)

-------------------------------------------------------------------------------
-- 12. No DungeonData graceful handling
-------------------------------------------------------------------------------

T:run("DungeonPicker: shows no results when DungeonData not scanned", function(t)
    resetState()
    local DP = QR.DungeonPicker

    -- Mark DungeonData as not scanned
    QR.DungeonData.scanned = false
    QR.DungeonData.instances = {}
    QR.DungeonData.byTier = {}
    QR.DungeonData.numTiers = 0

    DP:Show()

    local foundNoResults = false
    for _, row in ipairs(DP.rows) do
        if row.nameLabel then
            local text = row.nameLabel:GetText() or ""
            local L = QR.L
            if text:find(L["DUNGEON_PICKER_NO_RESULTS"]) then
                foundNoResults = true
            end
        end
    end
    t:assertTrue(foundNoResults, "Shows no results when DungeonData not scanned")
end)
