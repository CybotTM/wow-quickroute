-- MultiRoute.lua
-- Bounded waypoint trips. Replan each leg from the actual player position so
-- consumed teleports and current cooldowns are not reused as if still ready.
local ADDON_NAME, QR = ...
local type, pairs, ipairs, pcall = type, pairs, ipairs, pcall
local tonumber, tostring = tonumber, tostring
local format, gsub = string.format, string.gsub
local sort, remove, concat = table.sort, table.remove, table.concat
local resume, create, yield, status = coroutine.resume, coroutine.create, coroutine.yield, coroutine.status
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
        and (stop.title == nil or (type(stop.title) == "string" and #stop.title <= 160))
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
    self:Save()
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

local function playerPosition()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local ok, point = pcall(function()
        local mapID = C_Map.GetBestMapForUnit("player")
        local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        if not position then return end
        local x, y = position:GetXY()
        local stop = { mapID = mapID, x = x, y = y }
        if validStop(stop) then return stop end
    end)
    return ok and point or nil
end

function MR:OptimizeTour(restarts)
    local origin = playerPosition()
    if not origin then return self:SelectNext(true) end
    self.generation = self.generation + 1
    local generation, count = self.generation, #self.stops
    self.busy, self.currentIndex = true, nil
    local calculator = QR.PathCalculator
    if calculator.CreateRouteContext then
        local ok, context = pcall(calculator.CreateRouteContext, calculator, { excludeCooldowns = true })
        if ok and context then calculator = context end
    end
    local matrix, from, destination, done = {}, 0, 1, 0
    local points = { [0] = origin }
    for i, stop in ipairs(self.stops) do points[i] = stop end
    local function finish(order, cost, method)
        if self.generation ~= generation then return end
        local current = playerPosition()
        if not current or current.mapID ~= origin.mapID or math.abs(current.x-origin.x) > 0.005 or math.abs(current.y-origin.y) > 0.005 then
            if current and (restarts or 0) < 1 then return self:OptimizeTour(1) end
            self.planCost, self.planMethod = nil, "live-next"
            return self:SelectNext(true)
        end
        if order then
            local sorted = {}
            for i, index in ipairs(order) do sorted[i] = self.stops[index] end
            self.stops, self.planCost, self.planMethod = sorted, cost, method
            self:Save()
            self:SelectNext(true, true)
        else
            -- A cooldown-free matrix may be disconnected even though the
            -- current character can teleport out. Retain every destination and
            -- identify the live next-leg fallback instead of claiming a tour.
            self.planCost, self.planMethod = nil, "live-next"
            self:SelectNext(true)
        end
    end
    local function solve()
        local worker = create(function()
            return QR.TourPlanner:Solve(matrix, count, function() yield() end)
        end)
        local function advance()
            if self.generation ~= generation then return end
            local ok, order, cost, method = resume(worker)
            if not ok then finish(nil); return end
            if status(worker) == "dead" then finish(order, cost, method)
            else C_Timer.After(0, advance) end
        end
        advance()
    end
    local function calculateOne()
        if self.generation ~= generation then return end
        if from > count then solve(); return end
        matrix[from] = matrix[from] or {}
        if from ~= destination then
            local a, b = points[from], points[destination]
            local ok, result = pcall(calculator.CalculatePathFrom, calculator,
                a.mapID, a.x, a.y, b.mapID, b.x, b.y, { excludeCooldowns = true })
            matrix[from][destination] = ok and result and finite(result.totalTime)
                and result.totalTime >= 0 and result.totalTime or huge
            done = done + 1
            self.message = format(QR.L["MULTI_MATRIX_PROGRESS"], done, count*count)
            self:UpdateStatus()
        end
        destination = destination + 1
        if destination > count then from, destination = from + 1, 1 end
        C_Timer.After(0, calculateOne)
    end
    C_Timer.After(0, calculateOne)
end

function MR:SelectNext(skipOptimization, ordered)
    if #self.stops == 0 then return end
    if self.fastestNext and not skipOptimization and QR.PathCalculator.CalculatePathFrom then
        return self:OptimizeTour()
    end
    self.generation = self.generation + 1
    local generation = self.generation
    self.busy, self.currentIndex = true, nil
    self.message = QR.L["CALCULATING"]
    self:UpdateStatus()
    local index, bestIndex, bestResult, bestCost = 1, nil, nil, huge
    local count = self.fastestNext and not ordered and #self.stops or math.min(1, #self.stops)
    local origin, restarts = count > 1 and playerPosition() or nil, 0
    local function calculateOne()
        if self.generation ~= generation then return end
        if count > 1 then
            local current = playerPosition()
            local changed = current and origin and (current.mapID ~= origin.mapID
                or math.abs(current.x - origin.x) > 0.001 or math.abs(current.y - origin.y) > 0.001)
            if not current or not origin or (changed and restarts >= 2) then
                self.busy, self.currentIndex = false, nil
                self.message = QR.L[changed and "MULTI_POSITION_CHANGED" or "DESTINATION_UNAVAILABLE"]
                self:UpdateStatus()
                return
            end
            if changed then
                -- Compare every candidate from the same origin. Refreshing
                -- only the previous winner can retain the wrong destination.
                origin, restarts = current, restarts + 1
                index, bestIndex, bestResult, bestCost = 1, nil, nil, huge
            end
        end
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
    self:Save()
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
    self.planCost, self.planMethod = nil, nil
    self:Save()
    self.message = QR.L["MULTI_EMPTY"]
    self:UpdateStatus()
end

function MR:CancelSelection()
    self.generation = self.generation + 1
    self.busy = false
end

function MR:Save()
    local guid = UnitGUID and UnitGUID("player")
    if (issecretvalue and issecretvalue(guid)) or type(guid) ~= "string" or not QR.db then return end
    QR.db.multiRouteTrips = type(QR.db.multiRouteTrips) == "table" and QR.db.multiRouteTrips or {}
    if #self.stops == 0 then QR.db.multiRouteTrips[guid] = nil; return end
    local stops = {}
    for i, stop in ipairs(self.stops) do
        stops[i] = { mapID = stop.mapID, x = stop.x, y = stop.y, title = stop.title }
    end
    QR.db.multiRouteTrips[guid] = { stops = stops, completed = self.completed, optimize = self.fastestNext }
end

function MR:Initialize()
    local guid = UnitGUID and UnitGUID("player")
    if (issecretvalue and issecretvalue(guid)) or type(guid) ~= "string" then return end
    local trips = QR.db and QR.db.multiRouteTrips
    local saved = type(trips) == "table" and guid and trips[guid]
    if type(saved) ~= "table" or type(saved.stops) ~= "table" or #saved.stops < 1 or #saved.stops > self.MAX_STOPS then return end
    local copy = {}
    for _, stop in ipairs(saved.stops) do
        if not validStop(stop) then trips[guid] = nil; return end
        copy[#copy+1] = { mapID = stop.mapID, x = stop.x, y = stop.y, title = stop.title }
    end
    local completed = saved.completed
    if not finite(completed) or completed < 0 or completed > self.MAX_STOPS or completed % 1 ~= 0 then completed = 0 end
    self.stops, self.completed, self.total = copy, completed, completed + #copy
    self.fastestNext, self.message = saved.optimize ~= false, QR.L["MULTI_RESUME"]
    self.currentIndex, self.busy = nil, false
end

function MR:UpdateStatus()
    local message = self.message or QR.L["MULTI_EMPTY"]
    if self.planCost and not self.busy then
        message = message .. "\n" .. format(QR.L["MULTI_TOUR_ESTIMATE"],
            QR.CooldownTracker:FormatTime(self.planCost), QR.L[self.planMethod == "exact" and "MULTI_EXACT" or "MULTI_HEURISTIC"])
    elseif self.planMethod == "live-next" and not self.busy then
        message = message .. "\n" .. QR.L["MULTI_LIVE_FALLBACK"]
    end
    if self.statusLabel then self.statusLabel:SetText(message) end
    if self.itinerary then
        local lines = {}
        for i, stop in ipairs(self.stops) do
            local marker = self.currentIndex == i and "> " or ""
            lines[i] = format("%s%d. %s", marker, self.completed + i, title(stop))
        end
        self.itinerary:SetText(#lines > 0 and concat(lines, "\n\n") or QR.L["MULTI_EMPTY"])
        local height = math.max(214, self.itinerary:GetStringHeight() + 12)
        self.itinerary:SetHeight(height)
        self.itineraryBody:SetHeight(height)
    end
end

function MR:Show()
    if InCombatLockdown() then QR:Print(QR.L["CANNOT_USE_IN_COMBAT"]); return end
    if not self.frame then
        local L = QR.L
        local frame = QR.CreateStandardWindow({ name = "QuickRouteMultiRouteFrame", title = L["MULTI_TITLE"], width = 580, height = 650 })
        self.frame = frame
        local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", 16, -42)
        hint:SetWidth(548)
        hint:SetJustifyH("LEFT")
        hint:SetText(L["MULTI_HINT"])
        local inputSurface = frame:CreateTexture(nil, "BACKGROUND")
        inputSurface:SetPoint("TOPLEFT", 12, -92)
        inputSurface:SetSize(546, 144)
        inputSurface:SetColorTexture(0, 0, 0, 0.25)
        local scroll = CreateFrame("ScrollFrame", "QuickRouteMultiRouteScroll", frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -100)
        scroll:SetSize(526, 130)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        if edit.SetJustifyV then edit:SetJustifyV("TOP") end
        if edit.SetTextInsets then edit:SetTextInsets(6, 6, 6, 6) end
        edit:SetAutoFocus(false)
        edit:SetFontObject("ChatFontNormal")
        edit:SetWidth(520)
        edit:SetHeight(130)
        edit:SetMaxLetters(8192)
        edit:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
        scroll:SetScrollChild(edit)
        QR.SkinScrollBar(scroll)
        self.editBox = edit
        if #self.stops > 0 then
            local lines = {}
            for i, stop in ipairs(self.stops) do
                lines[i] = format("/way #%d %.2f %.2f %s", stop.mapID, stop.x*100, stop.y*100, stop.title or "")
            end
            edit:SetText(concat(lines, "\n"))
        end
        local mode = QR.CreateModernCheckbox(frame, 20)
        mode:SetPoint("TOPLEFT", 16, -240)
        mode:SetChecked(self.fastestNext ~= false)
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", mode, "RIGHT", 8, 0)
        label:SetSize(510, 32)
        label:SetJustifyH("LEFT")
        label:SetText(L["MULTI_FASTEST_NEXT"])
        local itineraryTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        itineraryTitle:SetPoint("TOPLEFT", 16, -282)
        itineraryTitle:SetText(L["MULTI_ITINERARY"])
        local itineraryScroll = CreateFrame("ScrollFrame", "QuickRouteMultiItinerary", frame, "UIPanelScrollFrameTemplate")
        itineraryScroll:SetPoint("TOPLEFT", 16, -306)
        itineraryScroll:SetSize(526, 214)
        local itineraryBody = CreateFrame("Frame", nil, itineraryScroll)
        itineraryBody:SetSize(520, 214)
        local itinerary = itineraryBody:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        itinerary:SetPoint("TOPLEFT")
        itinerary:SetWidth(520)
        itinerary:SetJustifyH("LEFT")
        itinerary:SetJustifyV("TOP")
        itineraryScroll:SetScrollChild(itineraryBody)
        QR.SkinScrollBar(itineraryScroll)
        self.itinerary = itinerary
        itineraryBody:SetScript("OnSizeChanged", function() itinerary:SetWidth(itineraryBody:GetWidth()) end)
        self.itineraryBody = itineraryBody
        local function button(text, x, callback)
            local btn = QR.CreateModernButton(frame, 132, 26)
            btn:SetPoint("BOTTOMLEFT", x, 80)
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
        button(L["MULTI_TOMTOM"], 154, function() start(self:CollectTomTomWaypoints()) end)
        button(L["MULTI_NEXT"], 292, function() self:Next() end)
        button(L["MULTI_CLEAR"], 430, function() self:Clear() end)
        self.statusLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        self.statusLabel:SetPoint("BOTTOMLEFT", 16, 14)
        self.statusLabel:SetSize(548, 54)
        self.statusLabel:SetJustifyH("LEFT")
    end
    QR.FitWindowScale(self.frame, QR.db and QR.db.windowScale or 1)
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
