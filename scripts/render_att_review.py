#!/usr/bin/env python3
"""Render ATT acquisition and search flows using small, explicit ATT fixtures.

Uses render_player_review's --sim-root, --wow-install, --output and --view
arguments unchanged. Actual addon controls, source validation and search run;
ATT indexes and the cached German item name are the only additional fixtures.
"""
import importlib.util
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]

UNOBTAINABLE = """
        AllTheThings = {
            PhaseConstants = { NEVER_IMPLEMENTED=1, REMOVED_FROM_GAME=2 },
            SearchForField = function(field, id)
                if field == "spellID" and id == 393222 then
                    return {{spellID=393222,u=2},{spellID=393222,u=2}}
                end
                return {}
            end,
            CurrentCharacterFilters = function() return false end,
            CreatePopoutForSearch = function() return true end,
        }
        local removed, ordinary, owned
        for _, entry in ipairs(QR.TeleportPanel:CollectAllTeleports()) do
            if entry.id == 393222 then removed=entry
            elseif entry.status.key == "STATUS_MISSING" and not ordinary then ordinary=entry
            elseif entry.id == 6948 then owned=entry end
        end
        assert(removed and removed.status.key == "STATUS_MISSING", "Expected missing Watcher's Legacy")
        assert(ordinary and owned, "Expected comparison entries")
        assert(QR.TeleportPanel:IsAcquisitionUnavailable(removed), "Removed-source fixture was not classified")
        QR.TeleportPanel.CollectAllTeleports = function() return {removed,ordinary,owned} end
        QR.db.windowScale = 1.5
        QR.db.availabilityFilter = "all"
        QR.TeleportPanel.availabilityFilter = "all"
"""

FLAT = UNOBTAINABLE + """
        QR.db.groupByDestination = false
        QR.TeleportPanel.groupByDestination = false
        QR.MainFrame:Show("teleports")
        QR_DOC.Reposition()
        for _, row in ipairs(QR.TeleportPanel.teleportRows) do
            if row.entry.id == 393222 then
                assert(row.helpButton:GetText() == "Nicht erhältlich", "Unavailable short label missing")
                local text = row.helpButton.text or row.helpButton:GetFontString()
                if text then
                    assert(text:GetStringWidth() <= row.helpButton:GetWidth() - 6,
                        "Unavailable label exceeds its button")
                end
            end
        end
"""

GRID = UNOBTAINABLE + """
        QR.db.groupByDestination = true
        QR.TeleportPanel.groupByDestination = true
        QR.MainFrame:Show("teleports")
        QR_DOC.Reposition()
"""

UNOBTAINABLE_HELP = FLAT + """
        QR.TeleportPanel:ShowAcquisitionHelp(removed)
"""

# ATT's actual item/vendor relationship and percentage coordinates. Purchase
# reputation belongs to the leaf item; vendor ancestry retains its access gates.
VILO_SOURCE = """
        local vendor = {npcID=182257, name="Vilo", coords={ [1970]={{34.8,64.1}} },
            parent={headerID=-58,parent={lvl=60,awp=90200,parent={lvl=50,awp=90002}}}}
        local item = {itemID=190237,b=1,minReputation={2478,42000},parent=vendor}
        local items, npcs = {[190237]={item}}, {[182257]={vendor}}
        AllTheThings = {
            PhaseConstants = {NEVER_IMPLEMENTED=1,REMOVED_FROM_GAME=2},
            HeaderConstants = {VENDORS=-58},
            NPCNameFromID = {[182257]="Vilo"},
            SearchForField=function(field,id)
                return ((field == "itemID" and items) or (field == "npcID" and npcs) or {})[id] or {}
            end,
            GetRawFieldContainer=function(field)
                if field == "itemID" then return items end
                if field == "npcID" then return npcs end
            end,
            CurrentCharacterFilters=function()return true end,
            CreatePopoutForSearch=function()return true end,
        }
"""

VILO_HELP = VILO_SOURCE + """
        local entry
        for _, value in ipairs(QR.TeleportPanel:CollectAllTeleports()) do
            if value.id==190237 then entry=value;break end
        end
        assert(entry,"Expected actual Broker Translocation Matrix")
        local location = QR.TeleportPanel:GetAcquisitionLocation(entry)
        assert(location and location.npcID==182257,"Expected validated Vilo source")
        assert(math.abs(location.x-0.348)<0.000001 and math.abs(location.y-0.641)<0.000001,
            "Expected ATT Vilo coordinates")
        QR.db.windowScale=1.5
        QR.TeleportPanel:ShowAcquisitionHelp(entry)
        assert(QR.TeleportPanel.acquisitionFrame.routeButton:IsShown(),
            "Vilo source route button must be visible")
"""

SEARCH = VILO_SOURCE + """
        local cachedName = "Translokationsmatrix der Mittler"
        local cached, itemName, itemInfo = C_Item.IsItemDataCachedByID, C_Item.GetItemNameByID, C_Item.GetItemInfo
        C_Item.IsItemDataCachedByID = function(id)
            if id==190237 then return true end
            return cached and cached(id)
        end
        C_Item.GetItemNameByID = function(id)
            if id==190237 then return cachedName end
            return itemName and itemName(id)
        end
        C_Item.GetItemInfo = function(query)
            if query==cachedName then return cachedName,"|Hitem:190237::::::::|h["..cachedName.."]|h" end
            return itemInfo and itemInfo(query)
        end
        QR.db.windowScale=1.5
        QR.MainFrame:Show("route")
        local search=QR.DestinationSearch
        search:ShowDropdown(search.searchBox)
"""


def search_view(query):
    """Settle only this tiny fixture's zero-delay callbacks, with a hard bound."""
    return SEARCH + f'\n        local query = "{query}"\n' + """
        if search.searchBox then
            search._suppressTextChanged=true
            search.searchBox:SetText(query)
            search._suppressTextChanged=false
        end
        local after, pending = C_Timer.After, {}
        C_Timer.After=function(delay,callback)
            if delay==0 then pending[#pending+1]=callback else after(delay,callback) end
        end
        local ok, err=pcall(function()
            search:RefreshDropdown(query)
            for _=1,12 do
                local callback=table.remove(pending,1)
                if not callback then break end
                callback()
            end
            local state=search._attSearch
            assert(state and not state.searching,"Tiny ATT search fixture did not settle")
            assert(#state.results>0 and state.results[1].attSourceID==182257,
                "Expected Vilo in the actual ATT search results")
        end)
        C_Timer.After=after
        if not ok then error(err) end
"""


def main():
    spec = importlib.util.spec_from_file_location(
        "render_player_review", REPO / "scripts/render_player_review.py"
    )
    renderer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(renderer)
    renderer.__doc__ = __doc__
    renderer.VIEWS = {
        "unobtainable-list": ("", FLAT, 1366, 768),
        "unobtainable-grid": ("", GRID, 1366, 768),
        "unobtainable-help": ("", UNOBTAINABLE_HELP, 1366, 768),
        "vilo-purchase-help": ("", VILO_HELP, 1366, 768),
        "att-search-vilo": ("", search_view("Vilo"), 1366, 768),
        "att-search-item": ("", search_view("Translokationsmatrix der Mittler"), 1366, 768),
    }
    renderer.main()


if __name__ == "__main__":
    main()
