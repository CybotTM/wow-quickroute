#!/usr/bin/env python3
"""Render active trip and phase-choice examples using actual QuickRoute controls.

The simulated character position is explicit. Stops come from ServicePOIs and
TravelPhaseGroups; no route, ordering, estimate or phase-change step is mocked.
The phase pair demonstrates the same classic-Uldum destination with opposite
session assumptions, while C_Map cannot report that remote zone's current art.

Uses render_player_review's arguments. Outputs remain in the requested review
folder; this script never replaces published screenshots or SavedVariables.
"""
import importlib.util
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]

HELPERS = r'''
        QR_DOC.HideOverlapping({"PlayerFrame", "TargetFrame", "ObjectiveTrackerFrame", "GameMenuFrame"})
        QR.db.windowScale = 1.1
        QR.db.autoWaypoint = false
        local position = {mapID=84,x=.4965,y=.8725}
        C_Map.GetBestMapForUnit = function(unit) if unit == "player" then return position.mapID end end
        C_Map.GetPlayerMapPosition = function(mapID, unit)
            if unit == "player" and mapID == position.mapID then return CreateVector2D(position.x,position.y) end
        end
        local function click(frame, text, rowY)
            for _, button in ipairs({frame:GetChildren()}) do
                if button.GetText and button:GetText() == text then
                    local _,_,_,_,y=button:GetPoint(1)
                    if not rowY or y == rowY then
                        local handler=button:GetScript("OnClick")
                        assert(handler,"Expected actual button callback for "..text)
                        handler(button,"LeftButton")
                        return button
                    end
                end
            end
            error("Actual control missing: "..text)
        end
        local function settle(action)
            local after,pending=C_Timer.After,{}
            C_Timer.After=function(delay,callback)
                if delay==0 then pending[#pending+1]=callback else after(delay,callback) end
            end
            local ok,err=pcall(function()
                action()
                for _=1,200 do
                    local callback=table.remove(pending,1)
                    if not callback then return end
                    callback()
                end
                error("Feature scene exceeded its callback budget")
            end)
            C_Timer.After=after
            if not ok then error(err) end
        end
        local function service(kind,mapID)
            for _,point in ipairs(QR.ServicePOIs[kind]) do
                if point.mapID == mapID then return point end
            end
            error("Verified service point missing")
        end
        local function sideBySide(other)
            local main=QR.MainFrame.frame
            main:ClearAllPoints()
            main:SetPoint("TOPLEFT",UIParent,"TOPLEFT",16,-80)
            main:SetScale(1.1)
            other:ClearAllPoints()
            other:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",-16,-80)
            other:SetScale(1.1)
            QR_DOC.Reposition()
        end
'''

TRIP = HELPERS + r'''
        -- All three service locations are read from the shipped catalogue.
        -- The first real completed stop is simulated by moving to its position
        -- and pressing Reached / next, exactly as the player's workflow does.
        QR_DOC.RebuildGraph()
        local trip=QR.MultiRoute
        trip:Clear()
        trip:Show()
        local stops={
            {point=service("BANK",84),name="Bank in Sturmwind"},
            {point=service("BANK",87),name="Bank in Eisenschmiede"},
            {point=service("AUCTION_HOUSE",87),name="Auktionshaus in Eisenschmiede"},
        }
        local lines={}
        for _,stop in ipairs(stops) do
            lines[#lines+1]=string.format("/way #%d %.2f %.2f %s",stop.point.mapID,stop.point.x*100,stop.point.y*100,stop.name)
        end
        trip.editBox:SetText(table.concat(lines,"\n"))
        settle(function() click(trip.frame,QR.L["MULTI_START"]) end)
        assert(not trip.busy and trip.currentIndex,"Start must produce a real active leg")
        assert(trip.total==3 and trip.planCost and trip.planCost>0,"Expected a computed three-stop tour")
        local reached=trip.stops[trip.currentIndex]
        assert(reached.mapID==84,"The nearby Stormwind stop should be visited first")
        position.mapID,position.x,position.y=reached.mapID,reached.x,reached.y
        settle(function() click(trip.frame,QR.L["MULTI_NEXT"]) end)
        assert(not trip.busy and trip.currentIndex and trip.completed==1 and #trip.stops==2,
            "Reached / next must advance to the second actual stop")
        assert(trip.stops[trip.currentIndex].mapID==87,"The active second leg should lead to Ironforge")
        assert(trip.statusLabel:GetText():find("2",1,true),"Trip progress must be visible")
        assert(trip.itinerary:GetText():find("> ",1,true),"The active stop must be marked")
        assert(QR.UI.frame.timeLabel:GetText()~="","The computed leg estimate must be visible")
        sideBySide(trip.frame)
'''


def phase_view(present):
    choice = "PHASE_PRESENT" if present else "PHASE_PAST"
    expected = "true" if present else "false"
    return HELPERS + r'''
        -- The recorded Stormwind earthshrine is the explicit scene origin.
        -- Uldum is remote: no live phase information is available, so the
        -- session assumption applies before taking its actual city portal.
        local origin=QR.TravelTransitions.nodes.EASTERN_EARTHSHRINE_SW
        position.mapID,position.x,position.y=origin.mapID,origin.x,origin.y
        local mapArt=C_Map.GetMapArtID
        C_Map.GetMapArtID=function(mapID)
            if mapID==249 then return nil end
            return mapArt and mapArt(mapID)
        end
        QR.TravelRequirements.phaseOverrides={}
        QR_DOC.RebuildGraph()
        local panel=QR.PhasePanel
        panel:Show()
        local uldumIndex
        for i,zone in ipairs(QR.TravelRequirements:GetPhaseOptions()) do
            if zone.mapID==249 then uldumIndex=i;break end
        end
        assert(uldumIndex,"Expected the actual Uldum phase control")
        local _,_,_,_,rowY=panel.rows[uldumIndex].auto:GetPoint(1)
''' + f'        click(panel.frame,QR.L["{choice}"],rowY)\n' + r'''
        local target=QR.TravelPhaseGroups[249][1]
        local result=QR.POIRouting:RouteToMapPosition(target.mapID,target.x,target.y)
        assert(result and result.steps and #result.steps>0,"Expected a computed route into classic Uldum")
        -- A descriptive destination label distinguishes the old map in the
        -- real route header; the calculated route and times remain untouched.
        local targetName="Uldum ("..QR.L["PHASE_PAST"]..")"
        result.waypoint.title=targetName
        QR.db.lastDestination.title=targetName
        QR.UI._pendingPOIRoute=result
        QR.UI:RefreshRoute()
        local changed=false
        for _,step in ipairs(result.steps) do
            if step.type=="phaseswitch" and step.phaseMapID==249 and step.phaseArtID==target.artID then changed=true end
        end
''' + f'        assert(changed=={expected},"The Zidormi step must match the selected Uldum assumption")\n' + r'''
        local zone
        for _,option in ipairs(QR.TravelRequirements:GetPhaseOptions()) do if option.mapID==249 then zone=option end end
        assert(zone and zone.source=="assumed","The panel must identify a session assumption, not claim live detection")
        assert(panel.rows[uldumIndex].label:GetText():find("Angenommen",1,true),"The assumption must be visible")
        sideBySide(panel.frame)
'''


def main():
    spec = importlib.util.spec_from_file_location(
        "render_player_review", REPO / "scripts/render_player_review.py"
    )
    renderer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(renderer)
    renderer.__doc__ = __doc__
    renderer.VIEWS = {
        "multi-active": ("", TRIP, 1600, 1000),
        "phases-present": ("", phase_view(True), 1600, 1000),
        "phases-past": ("", phase_view(False), 1600, 1000),
    }
    renderer.main()


if __name__ == "__main__":
    main()
