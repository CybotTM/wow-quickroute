#!/usr/bin/env python3
"""Render actual addon controls with a documented simulated character/locale.

QuickRoute uses its own German strings. Native labels retain the simulator
locale. ATT presence and an empty currency list are explicit fixtures.
"""
import argparse
import os
from pathlib import Path
import subprocess

VIEWS = {
    "sidebar": ("QRMapSidebar", """
        QR.MapSidebar:CreatePanel()
        QR.MapSidebar.frame:SetParent(UIParent)
        QR.MapSidebar.frame:ClearAllPoints()
        QR.MapSidebar.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        QR.MapSidebar.frame:SetWidth(360)
        QR.MapSidebar:UpdateForMap(999999, true)
        QR.MapSidebar.frame:Show()
    """, 1000, 700),
    "settings": ("SettingsPanel", 'SlashCmdList["QR"]("settings")', 1600, 1000),
    "teleports-small": ("", """
        QR.db.availabilityFilter = "all"
        QR.db.windowScale = 1.5
        QR.db.groupByDestination = true
        QR.TeleportPanel.groupByDestination = true
        QR.TeleportPanel.availabilityFilter = "all"
        QR.MainFrame:Show("teleports")
        QR_DOC.Reposition()
    """, 1366, 768),
    "acquisition-vendor": ("QuickRouteAcquisitionFrame", """
        AllTheThings = { CreatePopoutForSearch = function() return true end }
        QR.TeleportPanel:ShowAcquisitionHelp({
            id = 46874, isSpell = false, data = QR.TeleportItemsData[46874],
        })
    """, 1400, 900),
    "acquisition-unknown": ("QuickRouteAcquisitionFrame", """
        AllTheThings = { CreatePopoutForSearch = function() return true end }
        QR.TeleportPanel:ShowAcquisitionHelp({
            id = 140192, isSpell = false, data = QR.TeleportItemsData[140192],
        })
    """, 1400, 900),
    "currency-empty": ("QRDestSearchDropdown", """
        QR.ServiceRouter.GetKnownCurrencies = function()
            return {{currencyID = 2003, name = "Vorräte der Dracheninseln"}}
        end
        QR.ServiceRouter.GetCurrencyLocations = function() return {} end
        QR.ServiceRouter.GetCurrencyName = function() return "Vorräte der Dracheninseln" end
        QR.DestinationSearch:ShowCurrencyDropdown()
        QR.DestinationSearch:SelectResult({currencyID = 2003, selectCurrency = true})
        QR.DestinationSearch.frame:ClearAllPoints()
        QR.DestinationSearch.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    """, 1400, 900),
}

VIEWS["sidebar-collapsed"] = (
    "QRMapSidebar", VIEWS["sidebar"][1] + "QR.MapSidebar:Toggle()", 1000, 700,
)

# Exercise covering windows without filtering away UIParent-owned cast buttons.
for scene, action in {
    "overlap-help": """
        QR.TeleportPanel:ShowAcquisitionHelp({
            id = 46874, isSpell = false, data = QR.TeleportItemsData[46874],
        })
    """,
    "overlap-settings": 'SlashCmdList["QR"]("settings")',
    "overlap-menu": "QRTeleportFilterDropdown:OpenMenu()",
}.items():
    VIEWS[scene] = ("", VIEWS["teleports-small"][1] + action, 1366, 768)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sim-root", type=Path, required=True)
    parser.add_argument("--wow-install", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--view", choices=VIEWS)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    sim = args.sim_root.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)

    addon_root = output / "addons"
    addon_root.mkdir(exist_ok=True)
    addon_link = addon_root / "QuickRoute"
    if not addon_link.exists():
        addon_link.symlink_to(repo / "QuickRoute", target_is_directory=True)
    if addon_link.resolve() != (repo / "QuickRoute").resolve():
        parser.error("Output addon link belongs to a different source tree")
    env = os.environ.copy()
    env["WOW_INSTALL_PATH"] = str(args.wow_install.resolve())
    env["WOW_SIM_ADDONS_PATH"] = str(addon_root)

    seeds = repo / "screenshots/seeds"
    common = (seeds / "common.lua").read_text() + "\n" + (seeds / "graph.lua").read_text()
    locale = """
local t0 = GetTime(); while GetTime() - t0 < 2.6 do end
local QR = QR_DOC.FindQR()
local function translate(...)
    local GetLocale = function() return "deDE" end
""" + (repo / "QuickRoute/Localization.lua").read_text() + """
end
local translated = {}
translate("QuickRoute", translated)
for k, v in pairs(translated.L) do QR.L[k] = v end
"""
    for name, (frame, action, width, height) in VIEWS.items():
        if args.view and name != args.view:
            continue
        seed = output / ("qr-combined-" + name + ".lua")
        seed.write_text(common + "\n" + locale + """
QR_DOC.OpenView(function()
""" + action + "\nend)\n")
        image = output / ("qr-combined-" + name + ".webp")
        log_path = output / ("qr-combined-" + name + ".log")
        command = [
            str(sim / "target/release/wow-sim"), "--no-saved-vars",
            "--exec-lua", "@" + str(seed), "screenshot", "--output", str(image),
            "--width", str(width), "--height", str(height),
            "--dump-tree", frame or "QuickRouteMainFrame",
        ]
        if frame:
            command.extend(["--filter", frame])
        with log_path.open("w") as log:
            subprocess.run(command, cwd=sim, env=env, stdout=log,
                           stderr=subprocess.STDOUT, check=True, timeout=90)
        log_text = log_path.read_text()
        if not image.exists() or "[exec-lua] error:" in log_text or "stack traceback:" in log_text:
            raise SystemExit("Invalid render; inspect " + str(log_path))
        print(name + ": " + str(image), flush=True)


if __name__ == "__main__":
    main()
