#!/usr/bin/env python3
"""Render actual addon controls with a documented simulated character/locale.

QuickRoute uses its own German strings. Native labels retain the simulator
locale. ATT presence and an empty currency list are explicit fixtures.
"""
import argparse
import hashlib
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


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def source_state(directory):
    commit = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=directory, text=True
    ).strip()
    patch = subprocess.check_output(["git", "diff", "HEAD", "--binary"], cwd=directory)
    return commit, hashlib.sha256(patch).hexdigest()


def content_digest(root, paths):
    """Hash named input files, including files Git does not track yet."""
    manifest = hashlib.sha256()
    for path in sorted(paths):
        manifest.update(path.relative_to(root).as_posix().encode() + b"\0")
        manifest.update(digest(path).encode() + b"\n")
    return manifest.hexdigest()


def render_inputs(repo):
    addon = content_digest(repo, (p for p in (repo / "QuickRoute").rglob("*") if p.is_file()))
    fixtures = content_digest(repo, [
        repo / "scripts" / name for name in (
            "render_player_review.py", "render_att_review.py",
            "render_feature_review.py", "render_gallery_review.py",
        )
    ] + [repo / "screenshots/seeds" / name for name in ("common.lua", "graph.lua")])
    return addon, fixtures


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
    versions = [line.split(":", 1)[1].strip()
                for line in (repo / "QuickRoute/QuickRoute.toc").read_text().splitlines()
                if line.startswith("## Version:")]
    if len(versions) != 1 or not all(part.isdigit() for part in versions[0].split(".")):
        parser.error("The addon TOC must contain one numeric version")
    initial_inputs = render_inputs(repo)
    binary = sim / "target/release/wow-sim"

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
    locale = f"""
local t0 = GetTime(); while GetTime() - t0 < 2.6 do end
local QR = QR_DOC.FindQR()
assert(QR and QR.version == "{versions[0]}", "Rendered addon version differs from the current TOC")
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
        if render_inputs(repo) != initial_inputs:
            raise SystemExit("Render inputs changed during this run; restart with a stable source tree")
        addon_commit, addon_patch = source_state(repo)
        sim_commit, sim_patch = source_state(sim)
        binary_hash = digest(binary)
        seed = output / ("qr-combined-" + name + ".lua")
        seed.write_text(common + "\n" + locale + """
QR_DOC.OpenView(function()
""" + action + f"""
    for _, button in ipairs(QR.SecureButtons.pool) do
        local target = button._qrStepFrame
        if button.inUse and target then
            assert(not button:IsUsingParentLevel(), "Secure overlay still draws at its UIParent level")
            assert(button:GetFrameStrata() == target:GetFrameStrata(), "Secure overlay strata differs from its target")
            assert(button:GetFrameLevel() > target:GetFrameLevel(), "Secure overlay is behind its target")
        end
    end
    A_Print("QR_RENDER_COMPLETE:{name}")
end)
""")
        image = output / ("qr-combined-" + name + ".webp")
        log_path = output / ("qr-combined-" + name + ".log")
        image.unlink(missing_ok=True)
        image.with_suffix(".provenance.txt").unlink(missing_ok=True)
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
        if (not image.exists() or log_text.count("QR_RENDER_COMPLETE:" + name) != 1
                or any(marker in log_text for marker in (
                "[exec-lua] error:", "stack traceback:", "Lua error:"))):
            image.unlink(missing_ok=True)
            raise SystemExit("Invalid render; inspect " + str(log_path))
        if (render_inputs(repo) != initial_inputs or digest(binary) != binary_hash
                or source_state(sim) != (sim_commit, sim_patch)):
            image.unlink(missing_ok=True)
            raise SystemExit("Render inputs changed during capture; restart with stable inputs")
        image.with_suffix(".provenance.txt").write_text(
            f"View: {name}\nAddon version: {versions[0]}\n"
            f"Addon commit: {addon_commit}\nAddon working diff SHA256: {addon_patch}\n"
            f"Addon content SHA256: {initial_inputs[0]}\nRenderer inputs SHA256: {initial_inputs[1]}\n"
            f"Simulator commit: {sim_commit}\nSimulator working diff SHA256: {sim_patch}\n"
            f"Simulator binary SHA256: {binary_hash}\n"
            f"Lua scene SHA256: {digest(seed)}\nImage SHA256: {digest(image)}\n"
        )
        print(name + ": " + str(image), flush=True)


if __name__ == "__main__":
    main()
