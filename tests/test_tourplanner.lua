local T, QR = ...

T:run("TourPlanner: exact tour avoids greedy nearest-stop trap", function(t)
    local order, cost, method = QR.TourPlanner:Solve({ [0]={1,2,4}, [1]={0,100,100}, [2]={1,0,1}, [3]={1,1,0} }, 3)
    t:assertEqual(2, order[1], "tour starts at second-nearest stop")
    t:assertEqual(1, order[3], "expensive outgoing stop is visited last")
    t:assertEqual(4, cost, "whole trip costs four instead of 102")
    t:assertEqual("exact", method, "small tour has exact matrix solution")
end)

T:run("TourPlanner: directed disconnected edges never erase pending stops", function(t)
    local order, cost = QR.TourPlanner:Solve({[0]={1,2,3},[1]={[2]=1},[2]={[3]=1}}, 3)
    t:assertEqual(3, #order, "one-way chain visits every stop")
    t:assertEqual(3, cost, "one-way chain cost is three")
    t:assertNil(QR.TourPlanner:Solve({[0]={1,2},[1]={},[2]={}}, 2), "unconnected tour cannot claim success")
end)

T:run("TourPlanner: exact solver agrees with exhaustive asymmetric reference", function(t)
    for seed = 1, 12 do
        local matrix, count = {}, 6
        for a = 0, count do
            matrix[a] = {}
            for b = 1, count do matrix[a][b] = ((a*17 + b*31 + seed*a*b*7) % 43) + 1 end
        end
        local best, used = math.huge, {}
        local function visit(previous, depth, value)
            if depth == count then best = math.min(best, value); return end
            for nextStop = 1, count do
                if not used[nextStop] then
                    used[nextStop] = true
                    visit(nextStop, depth+1, value+matrix[previous][nextStop])
                    used[nextStop] = nil
                end
            end
        end
        visit(0, 0, 0)
        local _, cost = QR.TourPlanner:Solve(matrix, count)
        t:assertEqual(best, cost, "exact cost matches independent exhaustive search for seed " .. seed)
    end
end)

T:run("TourPlanner: large tours preserve all stops and yield bounded work", function(t)
    local matrix, ticks = {}, 0
    for a = 0, 20 do
        matrix[a] = {}
        for b = 1, 20 do matrix[a][b] = math.abs(a-b) + 1 end
    end
    local order, cost, method = QR.TourPlanner:Solve(matrix, 20, function() ticks = ticks + 1 end)
    t:assertEqual(20, #order, "all twenty destinations appear")
    t:assertEqual(40, cost, "ascending tour has expected total")
    t:assertEqual("heuristic", method, "large tour does not claim global optimality")
    t:assertGreaterThan(ticks, 0, "solver offers yield checkpoints")
    local seen = {}
    for _, index in ipairs(order) do seen[index] = true end
    t:assertTableCount(seen, 20, "destinations appear exactly once")
end)
