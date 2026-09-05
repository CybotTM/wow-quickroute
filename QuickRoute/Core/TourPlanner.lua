-- TourPlanner.lua
-- Directed, open tours: exact Held-Karp for up to ten stops, bounded multi-start
-- search for larger lists. Missing paths stay infinite; no stop is discarded.
local ADDON_NAME, QR = ...
local huge, floor = math.huge, math.floor
local type = type

QR.TourPlanner = {}
local TP = QR.TourPlanner

function TP:Solve(matrix, count, checkpoint)
    if type(matrix) ~= "table" or type(count) ~= "number" or count < 1 or count > 20 or count % 1 ~= 0 then return nil end
    local operations = 0
    local function tick()
        operations = operations + 1
        if checkpoint and operations % 256 == 0 then checkpoint() end
    end
    local function cost(a, b)
        local value = matrix[a] and matrix[a][b]
        if type(value) ~= "number" or value ~= value or value < 0 or value == huge then return huge end
        return value
    end
    if count <= 10 then
        local bits, dp, prev = {}, {}, {}
        for i = 1, count do
            bits[i] = 2 ^ (i-1)
            dp[bits[i]], prev[bits[i]] = { [i] = cost(0, i) }, { [i] = 0 }
        end
        local full = 2 ^ count - 1
        for mask = 1, full do
            local row = dp[mask]
            if row then
                for last = 1, count do
                    local base = row[last]
                    if base and base < huge then
                        for nextStop = 1, count do
                            tick()
                            if floor(mask / bits[nextStop]) % 2 == 0 then
                                local nextMask = mask + bits[nextStop]
                                local candidate = base + cost(last, nextStop)
                                dp[nextMask], prev[nextMask] = dp[nextMask] or {}, prev[nextMask] or {}
                                if candidate < (dp[nextMask][nextStop] or huge) then
                                    dp[nextMask][nextStop], prev[nextMask][nextStop] = candidate, last
                                end
                            end
                        end
                    end
                end
            end
        end
        local best, last = huge, nil
        for i = 1, count do
            local value = dp[full] and dp[full][i] or huge
            if value < best then best, last = value, i end
        end
        if not last then return nil end
        local order, mask = {}, full
        for i = count, 1, -1 do
            order[i] = last
            local previous = prev[mask][last]
            mask, last = mask - bits[last], previous
        end
        return order, best, "exact"
    end

    local function total(order)
        local value, previous = 0, 0
        for i = 1, #order do value, previous = value + cost(previous, order[i]), order[i] end
        return value
    end
    local bestOrder, bestCost
    -- Try every first stop, then improve with directed segment reversals. Costs
    -- are recomputed because portals make the distance matrix asymmetric.
    for first = 1, count do
        local order, used = { first }, { [first] = true }
        while #order < count do
            local nearest, nearestCost = nil, huge
            for candidate = 1, count do
                tick()
                local value = cost(order[#order], candidate)
                if not used[candidate] and value < nearestCost then nearest, nearestCost = candidate, value end
            end
            if not nearest then break end
            order[#order+1], used[nearest] = nearest, true
        end
        if #order == count then
            local value = total(order)
            for _ = 1, 3 do
                local improved = false
                for left = 1, count-1 do
                    for right = left+1, count do
                        tick()
                        local candidate = {}
                        for i = 1, count do candidate[i] = order[i] end
                        for i = left, right do candidate[i] = order[right - i + left] end
                        local candidateCost = total(candidate)
                        if candidateCost < value then order, value, improved = candidate, candidateCost, true end
                    end
                end
                if not improved then break end
            end
            if value < (bestCost or huge) then bestOrder, bestCost = order, value end
        end
    end
    return bestOrder, bestCost, "heuristic"
end
