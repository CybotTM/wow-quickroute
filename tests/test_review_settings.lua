local T, QR = ...

T:run("Settings review: corrupt root and nonfinite options recover", function(t)
    local saved, db = QuickRouteDB, QR.db
    for _, value in ipairs({ true, "invalid", 42 }) do
        QuickRouteDB = value
        local ok = pcall(QR.Initialize, QR)
        t:assertTrue(ok, "corrupt root initializes without an exception")
        t:assertEqual("table", type(QR.db), "database recovers to a table")
    end
    QuickRouteDB = { windowScale = 0/0, loadingScreenTime = -100,
        maxCooldownHours = math.huge, activeTab = "missing", waypointPriority = "broken",
        currencyVendors = "broken", firstRunShown = true }
    QR:Initialize()
    t:assertEqual(1, QR.db.windowScale, "NaN window scale defaults to 1")
    t:assertEqual(0, QR.db.loadingScreenTime, "negative loading cost clamps to zero")
    t:assertEqual(24, QR.db.maxCooldownHours, "infinite cooldown cap defaults to 24")
    t:assertEqual("route", QR.db.activeTab, "unknown tab becomes route")
    t:assertEqual("mappin", QR.db.waypointPriority, "unknown priority becomes mappin")
    t:assertEqual("table", type(QR.db.currencyVendors), "currency store recovers to a table")
    QuickRouteDB, QR.db = saved, db
end)
