local T, QR = ...

T:run("Windows: corrupted saved anchors and nonfinite positions are rejected", function(t)
    t:assertTrue(QR.IsValidWindowPosition("CENTER", "TOPLEFT", -200, 350), "valid saved anchor accepted")
    t:assertFalse(QR.IsValidWindowPosition("INVALID", "CENTER", 0, 0), "unknown point never reaches SetPoint")
    t:assertFalse(QR.IsValidWindowPosition("CENTER", {}, 0, 0), "table anchor rejected")
    t:assertFalse(QR.IsValidWindowPosition("CENTER", "CENTER", math.huge, 0), "infinite coordinate rejected")
    t:assertFalse(QR.IsValidWindowPosition("CENTER", "CENTER", 0/0, 0), "NaN coordinate rejected")
end)
