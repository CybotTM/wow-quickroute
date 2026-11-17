-- CurrencySources.lua -- maintained by hand.
-- NPCs that hand out a currency through something other than a merchant offer,
-- so a merchant visit can never record them as its seller. QuickRoute offers
-- them as "QuickRoute to seller" where no vendor takes the currency. Each row
-- names its evidence.
local ADDON_NAME, QR = ...

QR.CurrencySources = {
    -- Nebulous Voidcore: Orin Straylight gives one a week through one of three
    -- quests (5,000 gold, 2,000 Voidlight Marl or 100 Veteran Mistcrests). The
    -- npcID and the position are from a DataCollection trace of 2026-11-14:
    -- GOSSIP_SHOW and QUEST_PROGRESS (quest 97978) at Orin, Silvermoon City.
    { currencyID = 3418, npcID = 269987, nameKey = "ORIN_STRAYLIGHT", mapID = 2393, x = 0.4006, y = 0.6471, faction = "both" },
}
