#!/usr/bin/env python3
"""Render the current route, teleport inventory, quick list and quest gallery.

Uses render_player_review's CLI and explicit simulated collection/locale. The
route uses the shipped Aberrus entrance; the quest view uses the simulator's
declared The Lost Expedition quest and C_QuestLog waypoint. Player position is
an explicit input, while graph costs, route steps, names, icons and recommended
quest teleports come from the actual addon. Nothing is cropped or drawn later.
All scenes retain UIParent-owned secure buttons by remaining unfiltered.
"""
import importlib.util
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]

SETUP = r'''
        QR_DOC.HideOverlapping({"PlayerFrame", "TargetFrame", "PartyFrame", "CompactRaidFrameManager", "GameMenuFrame"})
        QR.db.windowScale = 1.3
        QR.db.autoWaypoint = false
        QR.db.useIconButtons = false
        local position = {mapID=84,x=.4965,y=.8725}
        C_Map.GetBestMapForUnit = function(unit)
            if unit == "player" then return position.mapID end
        end
        C_Map.GetPlayerMapPosition = function(mapID, unit)
            if unit == "player" and mapID == position.mapID then
                return CreateVector2D(position.x,position.y)
            end
        end
        local function settle(action)
            local after, pending = C_Timer.After, {}
            C_Timer.After = function(delay, callback)
                if delay == 0 then pending[#pending+1] = callback else after(delay, callback) end
            end
            local ok, err = pcall(function()
                action()
                for _=1,100 do
                    local callback = table.remove(pending,1)
                    if not callback then return end
                    callback()
                end
                error("Gallery scene exceeded its callback budget")
            end)
            C_Timer.After = after
            if not ok then error(err) end
        end
        QR_DOC.RebuildGraph()
'''

ROUTE = SETUP + r'''
        QR_DOC.HideOverlapping({"ObjectiveTrackerFrame"})
        local entrance = QR.DungeonData:GetInstance(1208)
        assert(entrance and entrance.zoneMapID == 2133 and entrance.x and entrance.y,
            "Expected shipped Aberrus entrance")
        settle(function() QR.DestinationSearch:SelectResult(entrance) end)
        assert(#QR.UI.stepLabels > 1, "Aberrus example must show the computed travel steps")
        assert(QR.UI.frame.timeLabel:GetText():find("%d"), "The route must have a computed estimate")
'''

TELEPORTS = SETUP + r'''
        QR_DOC.HideOverlapping({"ObjectiveTrackerFrame"})
        QR.db.availabilityFilter = "usable"
        QR.db.groupByDestination = true
        QR.TeleportPanel.availabilityFilter = "usable"
        QR.TeleportPanel.groupByDestination = true
        QR.MainFrame:Show("teleports")
        assert(QR.TeleportPanel.frame:IsShown(), "Actual teleport tab must be visible")
        QR_DOC.Reposition()
'''

QUICK = SETUP + r'''
        QR_DOC.HideOverlapping({"ObjectiveTrackerFrame", "MinimapCluster"})
        QR.MiniTeleportPanel:Show()
        local frame = QR.MiniTeleportPanel.frame
        frame:SetScale(1.5)
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        assert(#QR.MiniTeleportPanel.rows > 0, "Quick list must contain actual inventory rows")
        QR_DOC.Reposition()
'''

QUEST = SETUP + r'''
        -- The native simulator tracker owns this explicit example quest.
        -- Its title/waypoint/objectives are not replaced by this renderer.
        position.mapID, position.x, position.y = 630, .40, .40
        QR_DOC.RebuildGraph()
        local questID = 80000
        local waypoint = QR.WaypointIntegration:GetQuestWaypoint(questID, true)
        assert(waypoint and waypoint.mapID and waypoint.x and waypoint.y,
            "Simulator quest must expose its actual C_QuestLog waypoint")
        local title = C_QuestLog.GetTitleForQuestID(questID)
        assert(title and title ~= "", "Simulator quest must have its seeded title")
        settle(function()
            QR.DestinationSearch:SelectResult({questID=questID,name=title})
            QR.QuestTeleportButtons:RefreshButtons()
        end)
        local main = QR.MainFrame.frame
        main:ClearAllPoints()
        main:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 36, -110)
        ObjectiveTrackerFrame:Show()
        QR.QuestTeleportButtons:OnUpdate(1)
        local button = QR.QuestTeleportButtons.activeButtons[questID]
        assert(button and button:IsShown(), "Quest example must show its computed teleport recommendation")
        assert(#QR.UI.stepLabels > 0, "Quest example must show its computed route")
        QR_DOC.Reposition()
'''


def main():
    spec = importlib.util.spec_from_file_location(
        "render_player_review", REPO / "scripts/render_player_review.py"
    )
    renderer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(renderer)
    renderer.__doc__ = __doc__
    renderer.VIEWS = {
        "gallery-route": ("", ROUTE, 1600, 1000),
        "gallery-teleports": ("", TELEPORTS, 1600, 1000),
        "gallery-quick": ("", QUICK, 1366, 768),
        "gallery-quest": ("", QUEST, 1600, 1000),
    }
    renderer.main()


if __name__ == "__main__":
    main()
