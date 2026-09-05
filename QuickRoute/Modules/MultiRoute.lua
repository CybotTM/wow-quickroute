-- MultiRoute.lua
-- Bounded waypoint trips. Replan each leg from the actual player position so
-- consumed teleports and current cooldowns are not reused as if still ready.
local ADDON_NAME, QR = ...
local type, pairs, ipairs, pcall = type, pairs, ipairs, pcall
local tonumber, tostring = tonumber, tostring
local format, gsub = string.format, string.gsub
local sort, remove = table.sort, table.remove
local huge = math.huge

QR.MultiRoute = { stops = {}, completed = 0, generation = 0, MAX_STOPS = 20 }
local MR = QR.MultiRoute

local function finite(value)
    return not (issecretvalue and issecretvalue(value))
        and type(value) == "number" and value == value and value > -huge and value < huge
end

local function validStop(stop)
    return type(stop) == "table" and finite(stop.mapID) and stop.mapID > 0
        and stop.mapID % 1 == 0 and finite(stop.x) and stop.x >= 0 and stop.x <= 1
        and finite(stop.y) and stop.y >= 0 and stop.y <= 1
end

local function title(stop)
    -- Imported text is literal display data, never executable commands or links.
    return gsub(tostring(stop.title or format("%d: %.1f, %.1f", stop.mapID, stop.x*100, stop.y*100)):sub(1, 160), "|", "||")
end

function MR:ParseWaypoints(text)
    if type(text) ~= "string" or #text > 8192 then return nil, QR.L["MULTI_INVALID"] end
    local stops = {}
    for line in text:gmatch("[^\r\n;]+") do
        if line:find("%S") then
            local mapID, x, y, label = line:match("^%s*/way%s+#?(%d+)%s+([%d%.]+)%s+([%d%.]+)%s*(.-)%s*$")
            local stop = { mapID = tonumber(mapID), x = tonumber(x), y = tonumber(y), title = label }
            if stop.x then stop.x = stop.x / 100 end
            if stop.y then stop.y = stop.y / 100 end
            if not validStop(stop) then return nil, QR.L["MULTI_INVALID"] end
            if stop.title == "" then stop.title = nil end
            stops[#stops + 1] = stop
            if #stops > self.MAX_STOPS then return nil, QR.L["MULTI_LIMIT"] end
        end
    end
    if #stops == 0 then return nil, QR.L["MULTI_INVALID"] end
    return stops
end

function MR:CollectTomTomWaypoints()
    if not (TomTom and type(TomTom.waypoints) == "table") then return nil, QR.L["MULTI_NO_TOMTOM"] end
    local stops, inspected = {}, 0
    -- TomTom's active waypoint registry is mapID -> key -> {mapID, x, y, title}.
    -- Read only: never remove or change the player's TomTom collection.
    for _, mapStops in pairs(TomTom.waypoints) do
        if type(mapStops) == "table" then
            for _, waypoint in pairs(mapStops) do
                inspected = inspected + 1
                if inspected > 2000 then return nil, QR.L["MULTI_LIMIT"] end
                if type(waypoint) == "table" and waypoint.from ~= "QuickRoute"
                    and not (type(waypoint.title) == "string" and waypoint.title:match("^QR: ")) then
                    local stop = { mapID = waypoint[1], x = waypoint[2], y = waypoint[3], title = waypoint.title }
                    if validStop(stop) then
                        stops[#stops + 1] = stop
                        if #stops > self.MAX_STOPS then return nil, QR.L["MULTI_LIMIT"] end
                    end
                end
            end
        end
    end
    if #stops == 0 then return nil, QR.L["MULTI_NO_TOMTOM"] end
    sort(stops, function(a, b)
        if a.mapID ~= b.mapID then return a.mapID < b.mapID end
        if a.x ~= b.x then return a.x < b.x end
        if a.y ~= b.y then return a.y < b.y end
        return title(a) < title(b)
    end)
    return stops
end

function MR:Start(stops, fastestNext)
    if type(stops) ~= "table" or #stops == 0 or #stops > self.MAX_STOPS then
        return false, QR.L["MULTI_LIMIT"]
    end
    local copy = {}
    for _, stop in ipairs(stops) do
        if not validStop(stop) then return false, QR.L["MULTI_INVALID"] end
        copy[#copy + 1] = { mapID = stop.mapID, x = stop.x, y = stop.y, title = stop.title }
    end
    if QR.ServiceRouter and QR.ServiceRouter.CancelCurrencyRouting then
        QR.ServiceRouter:CancelCurrencyRouting()
    end
    self:Clear()
    self.stops, self.fastestNext = copy, fastestNext ~= false
    self.total = #copy
    self:SelectNext()
    return true
end

function MR:DisplayRoute(stop, result)
    local waypoint = { mapID = stop.mapID, x = stop.x, y = stop.y, title = title(stop) }
    if QR.db then QR.db.lastDestination = waypoint end
    result.waypoint, result.waypointSource = waypoint, "map_click"
    if QR.UI then
        QR.UI._pendingPOIRoute = result
        QR.UI:Show()
    end
end

function MR:SelectNext()
    self.generation = self.generation + 1
    local generation = self.generation
    self.busy, self.currentIndex = true, nil
    self.message = QR.L["CALCULATING"]
    self:UpdateStatus()
    local index, bestIndex, bestResult, bestCost = 1, nil, nil, huge
    local count = self.fastestNext and #self.stops or math.min(1, #self.stops)
    local function calculateOne()
        if self.generation ~= generation then return end
        if index > count then
            -- Selection spans frames; refresh the winning leg from the current
            -- player/cooldown state before presenting an executable route.
            if bestIndex then
                local stop = self.stops[bestIndex]
                local ok, result = pcall(QR.PathCalculator.CalculatePath, QR.PathCalculator, stop.mapID, stop.x, stop.y)
                if ok and result and finite(result.totalTime) and result.totalTime >= 0 then
                    bestResult = result
                else
                    bestIndex = nil
                end
            end
            self.busy, self.currentIndex = false, bestIndex
            if bestIndex then
                self.message = format(QR.L["MULTI_PROGRESS"], self.completed + 1, self.total, title(self.stops[bestIndex]))
                self:DisplayRoute(self.stops[bestIndex], bestResult)
            else
                self.message = QR.L["NO_PATH_FOUND"]
            end
            self:UpdateStatus()
            return
        end
        local stop = self.stops[index]
        local ok, result = pcall(QR.PathCalculator.CalculatePath, QR.PathCalculator, stop.mapID, stop.x, stop.y)
        if ok and result and finite(result.totalTime) and result.totalTime >= 0 and result.totalTime < bestCost then
            bestIndex, bestResult, bestCost = index, result, result.totalTime
        end
        index = index + 1
        C_Timer.After(0, calculateOne)
    end
    -- One destination per frame keeps long lists from monopolizing a UI frame.
    C_Timer.After(0, calculateOne)
end

function MR:Next()
    if self.busy then return false end
    if self.currentIndex then
        remove(self.stops, self.currentIndex)
        self.completed = self.completed + 1
        self.currentIndex = nil
    end
    if #self.stops == 0 then
        self.message = QR.L["MULTI_COMPLETE"]
        self:UpdateStatus()
    else
        self:SelectNext()
    end
    return true
end

function MR:Clear()
    self.generation = self.generation + 1
    self.stops, self.completed, self.total = {}, 0, 0
    self.currentIndex, self.busy = nil, false
    self.message = QR.L["MULTI_HINT"]
    self:UpdateStatus()
end

function MR:CancelSelection()
    self.generation = self.generation + 1
    self.busy = false
end

function MR:UpdateStatus()
    if self.statusLabel then self.statusLabel:SetText(self.message or QR.L["MULTI_HINT"]) end
end

function MR:Show()
    if InCombatLockdown() then QR:Print(QR.L["CANNOT_USE_IN_COMBAT"]); return end
    if not self.frame then
        local L = QR.L
        local frame = QR.CreateStandardWindow({ name = "QuickRouteMultiRouteFrame", title = L["MULTI_TITLE"], width = 540, height = 410 })
        self.frame = frame
        local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", 16, -42)
        hint:SetWidth(508)
        hint:SetJustifyH("LEFT")
        hint:SetText(L["MULTI_HINT"])
        local scroll = CreateFrame("ScrollFrame", "QuickRouteMultiRouteScroll", frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -100)
        scroll:SetSize(486, 158)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject("ChatFontNormal")
        edit:SetWidth(480)
        edit:SetHeight(158)
        edit:SetMaxLetters(8192)
        edit:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
        scroll:SetScrollChild(edit)
        QR.SkinScrollBar(scroll)
        self.editBox = edit
        local mode = QR.CreateModernCheckbox(frame, 20)
        mode:SetPoint("TOPLEFT", 16, -270)
        mode:SetChecked(true)
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", mode, "RIGHT", 8, 0)
        label:SetSize(476, 32)
        label:SetJustifyH("LEFT")
        label:SetText(L["MULTI_FASTEST_NEXT"])
        local function button(text, x, callback)
            local btn = QR.CreateModernButton(frame, 120, 26)
            btn:SetPoint("BOTTOMLEFT", x, 58)
            btn:SetText(text)
            btn:SetScript("OnClick", function()
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                if InCombatLockdown() then return end
                callback()
            end)
            return btn
        end
        local function start(stops, err)
            if stops then
                edit:ClearFocus()
                self:Start(stops, mode:GetChecked())
            else
                self.message = err
                self:UpdateStatus()
            end
        end
        button(L["MULTI_START"], 16, function() start(self:ParseWaypoints(edit:GetText())) end)
        button(L["MULTI_TOMTOM"], 144, function() start(self:CollectTomTomWaypoints()) end)
        button(L["MULTI_NEXT"], 272, function() self:Next() end)
        button(L["MULTI_CLEAR"], 400, function() self:Clear() end)
        self.statusLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        self.statusLabel:SetPoint("BOTTOMLEFT", 16, 14)
        self.statusLabel:SetSize(508, 38)
        self.statusLabel:SetJustifyH("LEFT")
    end
    self.frame:SetScale(QR.db and QR.db.windowScale or 1)
    self:UpdateStatus()
    self.frame:Show()
end

_G.SLASH_QRMULTI1 = "/qrmulti"
SlashCmdList["QRMULTI"] = function(message)
    local command = type(message) == "string" and message:match("^%s*(.-)%s*$") or ""
    if command == "next" then MR:Next()
    elseif command == "clear" then MR:Clear()
    elseif command == "tomtom" then
        local stops, err = MR:CollectTomTomWaypoints()
        if stops then MR:Start(stops, true) else QR:Print(err) end
    else MR:Show() end
end
