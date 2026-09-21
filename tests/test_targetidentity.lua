local T, QR = ...

-- A coordinate does not say what the player is supposed to do there. These are
-- the two checks that keep the distinction honest.

local ROLE = QR.TargetIdentity.ROLE

T:run("TargetIdentity: a quest in the log is an objective, one that is not is a reference", function(t)
    local saved = C_QuestLog.IsOnQuest
    C_QuestLog.IsOnQuest = function(questID) return questID == 4242 end
    t:assertEqual(ROLE.OBJECTIVE, QR.TargetIdentity:QuestRole(4242), "a quest in the log is an objective")
    t:assertEqual(ROLE.REFERENCE, QR.TargetIdentity:QuestRole(4243),
        "a quest that is not in the log is a known location, not a task")
    C_QuestLog.IsOnQuest = saved
end)

T:run("TargetIdentity: without the quest API nothing is claimed to be active", function(t)
    local saved = C_QuestLog.IsOnQuest
    C_QuestLog.IsOnQuest = nil
    t:assertFalse(QR.TargetIdentity:IsActiveObjective(4242), "no API, no claim of an active objective")
    t:assertEqual(ROLE.REFERENCE, QR.TargetIdentity:QuestRole(4242), "so the target is a reference")
    C_QuestLog.IsOnQuest = saved
end)

T:run("TargetIdentity: arriving completes nothing", function(t)
    t:assertFalse(QR.TargetIdentity:ArrivalCompletes(),
        "standing at a coordinate is not finishing the task there")
end)

T:run("TargetIdentity: every role has a word for it", function(t)
    for name, role in pairs(ROLE) do
        t:assertNotNil(QR.TargetIdentity:Describe(role), "role " .. name .. " has a label")
    end
    t:assertNil(QR.TargetIdentity:Describe("invented"), "an unknown role has none")
end)

T:run("TargetIdentity: the routing contract carries the role of the target", function(t)
    local pc = QR.PathCalculator
    local savedCalc, savedAfter = pc.CalculatePath, C_Timer.After
    local queue = {}
    C_Timer.After = function(_, callback) queue[#queue + 1] = callback end
    pc.CalculatePath = function() return { totalTime = 1, steps = {} } end
    local got
    QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5, role = ROLE.ACQUISITION },
        function(result) got = result end)
    while #queue > 0 do table.remove(queue, 1)() end
    pc.CalculatePath, C_Timer.After = savedCalc, savedAfter
    pc:CancelAsync()
    t:assertEqual(ROLE.ACQUISITION, got.target.role, "the role travels to the consumer")
    t:assertNotNil(got.target.roleLabel, "with a word the consumer can show")
    t:assertFalse(got.target.arrivalCompletes, "and the statement that arrival completes nothing")
end)

T:run("TargetIdentity: a request without a role defaults to a reference, never an objective", function(t)
    local pc = QR.PathCalculator
    local savedCalc, savedAfter = pc.CalculatePath, C_Timer.After
    local queue = {}
    C_Timer.After = function(_, callback) queue[#queue + 1] = callback end
    pc.CalculatePath = function() return { totalTime = 1, steps = {} } end
    local got
    QuickRouteAPI:CalculateRoute({ mapID = 84, x = 0.5, y = 0.5 }, function(result) got = result end)
    while #queue > 0 do table.remove(queue, 1)() end
    pc.CalculatePath, C_Timer.After = savedCalc, savedAfter
    pc:CancelAsync()
    t:assertEqual(ROLE.REFERENCE, got.target.role, "an unstated role is a known location")
end)
