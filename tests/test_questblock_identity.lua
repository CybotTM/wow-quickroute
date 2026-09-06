local T, QR, MockWoW = ...

local function withTracker(modules, fn)
    local original = _G.ObjectiveTrackerFrame
    _G.ObjectiveTrackerFrame = { modules = modules }
    local ok, err = pcall(fn)
    _G.ObjectiveTrackerFrame = original
    if not ok then error(err, 0) end
end

local function block(id)
    return { id = id, HeaderText = {} }
end

local function nativeModule(tag, trackedBlock)
    return {
        tag = tag,
        GetTag = function(self) return self.tag end,
        EnumerateActiveBlocks = function(_, callback) callback(trackedBlock) end,
    }
end

for _, questKind in ipairs({ "ordinary", "campaign" }) do
    for _, otherKind in ipairs({ "achievement", "recipe" }) do
        T:run("CollectQuestBlocks: " .. questKind .. " quest wins " .. otherKind .. " ID collisions in either order", function(t)
            local quest, other = block(10001), block(10001)
            -- CampaignQuestObjectiveTracker inherits the ordinary quest mixin's
            -- "quest" tag. Native achievement and recipe modules are untagged.
            local questModule = nativeModule("quest", quest)
            if questKind == "campaign" then
                -- The campaign module inherits GetTag from its quest mixin.
                local inherited = questModule.GetTag
                questModule.GetTag = nil
                setmetatable(questModule, { __index = { GetTag = inherited } })
            end
            local otherModule = nativeModule(nil, other)
            for _, modules in ipairs({ { questModule, otherModule }, { otherModule, questModule } }) do
                withTracker(modules, function()
                    local blocks, recognised = QR.QuestTeleportButtons:CollectQuestBlocks()
                    t:assertEqual(quest, blocks[10001], "The " .. questKind .. " quest keeps its own block")
                    t:assertTrue(recognised, "Both native providers were read successfully")
                end)
            end
        end)
    end
end

T:run("CollectQuestBlocks: explicit nonquest modules cannot replace untagged compatibility blocks", function(t)
    local quest, other = block(10002), block(10002)
    local legacy = { usedBlocks = { [10002] = quest } }
    for _, tag in ipairs({ "achievement", "recipe" }) do
        local unrelated = nativeModule(tag, other)
        for _, modules in ipairs({ { legacy, unrelated }, { unrelated, legacy } }) do
            withTracker(modules, function()
                local blocks, recognised = QR.QuestTeleportButtons:CollectQuestBlocks()
                t:assertEqual(quest, blocks[10002], "Explicit " .. tag .. " IDs do not enter the quest namespace")
                t:assertTrue(recognised, "The compatible quest provider remains readable")
            end)
        end
    end
end)

T:run("CollectQuestBlocks: excluded nonquest enumerators cannot make the quest set incomplete", function(t)
    local quest = block(10003)
    local unrelated = {
        tag = "achievement",
        EnumerateActiveBlocks = function() error("Unrelated tracker unavailable") end,
    }
    withTracker({ nativeModule("quest", quest), unrelated }, function()
        local blocks, recognised = QR.QuestTeleportButtons:CollectQuestBlocks()
        t:assertEqual(quest, blocks[10003], "The native quest block remains available")
        t:assertTrue(recognised, "An excluded provider does not invalidate the quest set")
    end)
end)

T:run("CollectQuestBlocks: unreadable tags do not claim a complete quest set", function(t)
    local quest, other = block(10004), block(10004)
    local unreadable = nativeModule(nil, other)
    unreadable.GetTag = function() error("Tag temporarily unavailable") end
    withTracker({ nativeModule("quest", quest), unreadable }, function()
        local blocks, recognised = QR.QuestTeleportButtons:CollectQuestBlocks()
        t:assertEqual(quest, blocks[10004], "Unreadable identity cannot overwrite the known quest")
        t:assertFalse(recognised, "An unknown module identity is reported as incomplete")
    end)
end)

T:run("CollectQuestBlocks: a secret module tag is not inspected or enumerated", function(t)
    local originalSecret = _G.issecretvalue
    local secretTag = {}
    _G.issecretvalue = function(value) return value == secretTag end
    local quest = block(10006)
    local unrelated = nativeModule(secretTag, block(10006))
    local enumerated = false
    unrelated.EnumerateActiveBlocks = function() enumerated = true end
    local ok, err = pcall(function()
        withTracker({ nativeModule("quest", quest), unrelated }, function()
            local blocks, recognised = QR.QuestTeleportButtons:CollectQuestBlocks()
            t:assertEqual(quest, blocks[10006], "Secret module identity cannot replace the public quest")
            t:assertFalse(enumerated, "The module with secret identity is not queried")
            t:assertFalse(recognised, "The unknown module identity is reported as incomplete")
        end)
    end)
    _G.issecretvalue = originalSecret
    if not ok then error(err, 0) end
end)

T:run("CollectQuestBlocks: a hidden achievement collision does not hide a visible quest button", function(t)
    local qtb = QR.QuestTeleportButtons
    local originalActive, originalElapsed = qtb.activeButtons, qtb.updateElapsed
    local originalCombat = MockWoW.config.inCombatLockdown
    local quest = CreateFrame("Frame", nil, UIParent)
    quest.id, quest.HeaderText = 10005, {}
    quest.GetLeft = function() return 900 end
    quest.GetTop = function() return 500 end
    quest.GetBottom = function() return 470 end
    quest:Show()
    local achievement = CreateFrame("Frame", nil, UIParent)
    achievement.id, achievement.HeaderText = 10005, {}
    achievement:Hide()
    local button = CreateFrame("Button", nil, UIParent)
    button:Show()
    qtb.activeButtons, qtb.updateElapsed = { [10005] = button }, 0
    MockWoW.config.inCombatLockdown = false
    local ok, err = pcall(function()
        withTracker({ nativeModule("quest", quest), nativeModule(nil, achievement) }, function()
            qtb:OnUpdate(1)
            t:assertTrue(button:IsShown(), "The button stays visible beside its visible quest")
            local _, _, _, x = button:GetPoint()
            t:assertNotNil(x, "The button receives its quest anchor despite the hidden achievement")
        end)
    end)
    qtb.activeButtons, qtb.updateElapsed = originalActive, originalElapsed
    MockWoW.config.inCombatLockdown = originalCombat
    quest:Hide()
    button:Hide()
    if not ok then error(err, 0) end
end)
