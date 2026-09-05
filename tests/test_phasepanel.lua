local T, QR = ...

T:run("PhasePanel: explicit zone assumptions are visible and panel reuses frames", function(t)
    local panel, combat = QR.PhasePanel, InCombatLockdown
    InCombatLockdown = function() return false end
    local ok, err = pcall(panel.Show, panel)
    t:assertTrue(ok, "phase selector opens: " .. tostring(err))
    t:assertEqual(7, #panel.rows, "each sourced Zidormi region has controls")
    local frame = panel.frame
    panel:Show()
    t:assertEqual(frame, panel.frame, "phase selector reuses existing frame")
    if frame then frame:Hide() end
    InCombatLockdown = combat
end)

T:run("PhasePanel: assumptions cannot mark an unperformed Zidormi conversation complete", function(t)
    local req, getMap = QR.TravelRequirements, C_Map.GetBestMapForUnit
    local live, assumed = req.GetLiveMapArtID, req.GetMapArtID
    C_Map.GetBestMapForUnit = function() return 17 end
    req.GetMapArtID = function() return 628 end
    req.GetLiveMapArtID = function() return nil end
    local steps = {
        {type="walk",fromMapID=84,destMapID=17},
        {type="phaseswitch",fromMapID=17,destMapID=17,phaseMapID=17,phaseArtID=628},
        {type="portal",fromMapID=17,destMapID=1116},
    }
    t:assertEqual(2, QR.UI:GetCurrentStepIndex(steps), "assumed target phase leaves required conversation visible")
    req.GetLiveMapArtID = function() return 628 end
    t:assertEqual(3, QR.UI:GetCurrentStepIndex(steps), "verified phase change advances to portal")
    C_Map.GetBestMapForUnit, req.GetLiveMapArtID, req.GetMapArtID = getMap, live, assumed
end)

T:run("PhasePanel: route card explains the required interaction", function(t)
    local action, detail = QR.UI:BuildStepCardTexts({type="phaseswitch",action="Speak to Zidormi: Past",navMapID=17,navX=0.48,navY=0.07,time=10})
    t:assertEqual("Speak to Zidormi: Past", action, "phase step presents conversation action")
    t:assertNotNil(detail:find("48.0, 7.0", 1, true), "phase card navigates to NPC coordinates")
end)

T:run("Route cards: multi-choice teleports identify the menu selection", function(t)
    local action = QR.UI:BuildStepCardTexts({type="teleport",to="Icecrown",choiceText="Icecrown"})
    t:assertNotNil(action:find("Choose: Icecrown", 1, true), "player knows which wormhole option to select")
end)

T:run("Route cards: floor transfers and jumps preserve actual interaction instructions", function(t)
    local action = QR.UI:BuildStepCardTexts({type="portal",instructionKey="STEP_USE_TRANSLOCATION_PAD",action="Use the translocation pad to Ring of Transference",to="Ring of Transference"})
    t:assertEqual("Use the translocation pad to Ring of Transference", action, "floor transfer is identified as a pad interaction")
    action = QR.UI:BuildStepCardTexts({type="jump",instructionKey="STEP_JUMP_TO",action="Jump into the central shaft to The Maw",to="The Maw"})
    t:assertEqual("Jump into the central shaft to The Maw", action, "Maw route cannot claim a nonexistent portal")
end)

T:run("Route cards: NPC shortcuts identify the source interaction point", function(t)
    local _, detail = QR.UI:BuildStepCardTexts({type="portal",to="Gorgrond",navMapID=554,navX=0.67,navY=0.76,navLabel="Grim Campfire"})
    t:assertNotNil(detail:find("Grim Campfire", 1, true), "player can identify the hidden shortcut at its coordinates")
end)
