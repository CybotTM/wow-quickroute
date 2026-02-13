-------------------------------------------------------------------------------
-- test_ui_modernization.lua
-- Regression tests to prevent reintroduction of old WoW UI templates/textures.
-- Scans QuickRoute source files for banned patterns and verifies modern helpers.
-------------------------------------------------------------------------------

local T, QR, MockWoW = ...

-------------------------------------------------------------------------------
-- Source file scanner
-------------------------------------------------------------------------------

--- Resolve project root from this test file's location.
local function getProjectRoot()
    local info = debug.getinfo(1, "S")
    local src = info.source:gsub("^@", "")
    local dir = src:match("(.-)[^/]*$") or "tests/"
    return dir .. "../"
end

local PROJECT_ROOT = getProjectRoot()
local ADDON_DIR = PROJECT_ROOT .. "QuickRoute/"

--- Read all lines from a file. Returns table of {lineNum, text} or nil.
local function readLines(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local lines = {}
    local n = 0
    for line in f:lines() do
        n = n + 1
        lines[#lines + 1] = { num = n, text = line }
    end
    f:close()
    return lines
end

--- List all .lua files under a directory (recursive).
local function listLuaFiles(dir)
    local files = {}
    local handle = io.popen("find '" .. dir .. "' -name '*.lua' -type f 2>/dev/null")
    if handle then
        for line in handle:lines() do
            files[#files + 1] = line
        end
        handle:close()
    end
    return files
end

--- No legacy allowlist needed — addon targets WoW 12.0+ (Interface: 120000).
-- All old templates are banned everywhere.

--- Check if a line is a comment (not actual code usage).
local function isComment(lineText)
    return lineText:match("^%s*%-%-") ~= nil
end

-------------------------------------------------------------------------------
-- Banned patterns: old templates that should NOT appear in 11.x codepaths
-------------------------------------------------------------------------------

local BANNED_TEMPLATES = {
    {
        pattern = "UIPanelButtonTemplate",
        description = "Old gold ornate button — use QR.CreateModernButton()",
    },
    {
        pattern = "UIPanelCloseButton",
        description = "Old red X close button — use custom close in CreateStandardWindow()",
    },
    {
        pattern = "UICheckButtonTemplate",
        description = "Old checkbox template — use QR.CreateModernCheckbox()",
    },
    {
        pattern = "UIDropDownMenuTemplate",
        description = "Old dropdown — use WowStyle1DropdownTemplate",
    },
    {
        pattern = "OptionsSliderTemplate",
        description = "Old slider — use native Settings.CreateSlider()",
    },
}

local BANNED_TEXTURES = {
    {
        pattern = "UI%-Panel%-Button%-Up",
        literal = "UI-Panel-Button-Up",
        description = "Old gold button texture — use WHITE8x8 with vertex colors",
    },
    {
        pattern = "UI%-Panel%-Button%-Down",
        literal = "UI-Panel-Button-Down",
        description = "Old gold button texture — use WHITE8x8 with vertex colors",
    },
    {
        pattern = "UI%-Panel%-Button%-Highlight",
        literal = "UI-Panel-Button-Highlight",
        description = "Old gold button highlight — use BackdropTemplate hover",
    },
    {
        pattern = "UI%-RefreshButton",
        literal = "UI-RefreshButton",
        description = "Old refresh icon — use QR.CreateModernIconButton()",
    },
}

-------------------------------------------------------------------------------
-- 1. Source file scanning: banned templates
-------------------------------------------------------------------------------

T:run("UI Lint: no banned old templates in 11.x codepaths", function(t)
    local files = listLuaFiles(ADDON_DIR)
    t:assertGreaterThan(#files, 0, "Found Lua source files to scan")

    local violations = {}
    for _, filePath in ipairs(files) do
        local lines = readLines(filePath)
        if lines then
            for _, entry in ipairs(lines) do
                if not isComment(entry.text) then
                    for _, banned in ipairs(BANNED_TEMPLATES) do
                        if entry.text:match(banned.pattern) then
                            violations[#violations + 1] = string.format(
                                "%s:%d — %s: %s",
                                filePath:match("QuickRoute/(.+)$") or filePath,
                                entry.num, banned.pattern, banned.description
                            )
                        end
                    end
                end
            end
        end
    end

    if #violations > 0 then
        for _, v in ipairs(violations) do
            t:assert(false, "BANNED TEMPLATE: " .. v)
        end
    else
        t:assert(true, "No banned old templates found in 11.x codepaths")
    end
end)

-------------------------------------------------------------------------------
-- 2. Source file scanning: banned textures
-------------------------------------------------------------------------------

T:run("UI Lint: no banned old textures in source files", function(t)
    local files = listLuaFiles(ADDON_DIR)

    local violations = {}
    for _, filePath in ipairs(files) do
        local lines = readLines(filePath)
        if lines then
            for _, entry in ipairs(lines) do
                if not isComment(entry.text) then
                    for _, banned in ipairs(BANNED_TEXTURES) do
                        if entry.text:match(banned.pattern) then
                            violations[#violations + 1] = string.format(
                                "%s:%d — %s: %s",
                                filePath:match("QuickRoute/(.+)$") or filePath,
                                entry.num, banned.literal, banned.description
                            )
                        end
                    end
                end
            end
        end
    end

    if #violations > 0 then
        for _, v in ipairs(violations) do
            t:assert(false, "BANNED TEXTURE: " .. v)
        end
    else
        t:assert(true, "No banned old textures found in source files")
    end
end)

-------------------------------------------------------------------------------
-- 3. Modern helper existence and API checks
-------------------------------------------------------------------------------

T:run("UI Helpers: QR.SkinScrollBar exists", function(t)
    t:assertNotNil(QR.SkinScrollBar, "QR.SkinScrollBar is defined")
    t:assertEqual("function", type(QR.SkinScrollBar), "SkinScrollBar is a function")
end)

T:run("UI Helpers: QR.CreateModernButton exists and returns frame", function(t)
    t:assertNotNil(QR.CreateModernButton, "QR.CreateModernButton is defined")
    t:assertEqual("function", type(QR.CreateModernButton), "CreateModernButton is a function")

    local parent = CreateFrame("Frame")
    local btn = QR.CreateModernButton(parent, 100, 24)
    t:assertNotNil(btn, "CreateModernButton returns a frame")
    t:assertNotNil(btn.SetBackdrop, "Button supports BackdropTemplate")
    t:assertNotNil(btn.SetText, "Button has SetText (via SetFontString)")
end)

T:run("UI Helpers: QR.CreateModernCheckbox exists and toggles", function(t)
    t:assertNotNil(QR.CreateModernCheckbox, "QR.CreateModernCheckbox is defined")
    t:assertEqual("function", type(QR.CreateModernCheckbox), "CreateModernCheckbox is a function")

    local parent = CreateFrame("Frame")
    local cb = QR.CreateModernCheckbox(parent, 20)
    t:assertNotNil(cb, "CreateModernCheckbox returns a frame")

    -- Test SetChecked / GetChecked API
    t:assertFalse(cb:GetChecked(), "Checkbox starts unchecked")
    cb:SetChecked(true)
    t:assertTrue(cb:GetChecked(), "Checkbox is checked after SetChecked(true)")
    cb:SetChecked(false)
    t:assertFalse(cb:GetChecked(), "Checkbox is unchecked after SetChecked(false)")
end)

T:run("UI Helpers: QR.CreateModernIconButton exists and returns frame", function(t)
    t:assertNotNil(QR.CreateModernIconButton, "QR.CreateModernIconButton is defined")
    t:assertEqual("function", type(QR.CreateModernIconButton), "CreateModernIconButton is a function")

    local parent = CreateFrame("Frame")
    local btn = QR.CreateModernIconButton(parent, 16, "\226\134\187")
    t:assertNotNil(btn, "CreateModernIconButton returns a frame")
    t:assertNotNil(btn._icon, "Icon button has _icon FontString")
end)

T:run("UI Helpers: QR.CreateStandardWindow exists", function(t)
    t:assertNotNil(QR.CreateStandardWindow, "QR.CreateStandardWindow is defined")
    t:assertEqual("function", type(QR.CreateStandardWindow), "CreateStandardWindow is a function")
end)

-------------------------------------------------------------------------------
-- 4. Verify modern patterns ARE used where expected
-------------------------------------------------------------------------------

T:run("UI Lint: scroll frames are skinned with SkinScrollBar", function(t)
    -- Check that every UIPanelScrollFrameTemplate usage is followed by SkinScrollBar
    local files = listLuaFiles(ADDON_DIR)
    local scrollFrameFiles = {}

    for _, filePath in ipairs(files) do
        local lines = readLines(filePath)
        if lines then
            local hasScrollTemplate = false
            local hasSkinCall = false
            for _, entry in ipairs(lines) do
                if entry.text:match("UIPanelScrollFrameTemplate") and not isComment(entry.text) then
                    hasScrollTemplate = true
                end
                if entry.text:match("SkinScrollBar") and not isComment(entry.text) then
                    hasSkinCall = true
                end
            end
            if hasScrollTemplate then
                local basename = filePath:match("([^/]+)$") or filePath
                scrollFrameFiles[#scrollFrameFiles + 1] = { file = basename, skinned = hasSkinCall }
            end
        end
    end

    for _, info in ipairs(scrollFrameFiles) do
        t:assertTrue(info.skinned,
            info.file .. " uses UIPanelScrollFrameTemplate but has QR.SkinScrollBar() call")
    end
end)

T:run("UI Lint: CreateStandardWindow uses modern close button (no UIPanelCloseButton)", function(t)
    local path = ADDON_DIR .. "Utils/WindowFactory.lua"
    local lines = readLines(path)
    t:assertNotNil(lines, "WindowFactory.lua readable")

    local usesOldClose = false
    for _, entry in ipairs(lines) do
        if entry.text:match("UIPanelCloseButton") and not isComment(entry.text) then
            usesOldClose = true
        end
    end
    t:assertFalse(usesOldClose, "WindowFactory does not use UIPanelCloseButton")
end)

-------------------------------------------------------------------------------
-- 5. Verify modern helpers produce correct default sizes
-------------------------------------------------------------------------------

T:run("UI Helpers: CreateModernButton default size is 80x22", function(t)
    local parent = CreateFrame("Frame")
    local btn = QR.CreateModernButton(parent)
    t:assertEqual(80, btn:GetWidth(), "Default width is 80")
    t:assertEqual(22, btn:GetHeight(), "Default height is 22")
end)

T:run("UI Helpers: CreateModernButton respects custom size", function(t)
    local parent = CreateFrame("Frame")
    local btn = QR.CreateModernButton(parent, 120, 30)
    t:assertEqual(120, btn:GetWidth(), "Custom width is 120")
    t:assertEqual(30, btn:GetHeight(), "Custom height is 30")
end)

T:run("UI Helpers: CreateModernCheckbox default size is 20x20", function(t)
    local parent = CreateFrame("Frame")
    local cb = QR.CreateModernCheckbox(parent)
    t:assertEqual(20, cb:GetWidth(), "Default width is 20")
    t:assertEqual(20, cb:GetHeight(), "Default height is 20")
end)

T:run("UI Helpers: CreateModernIconButton default size is 18x18", function(t)
    local parent = CreateFrame("Frame")
    local btn = QR.CreateModernIconButton(parent)
    t:assertEqual(18, btn:GetWidth(), "Default width is 18")
    t:assertEqual(18, btn:GetHeight(), "Default height is 18")
end)

T:run("UI Helpers: CreateModernIconButton custom glyph", function(t)
    local parent = CreateFrame("Frame")
    local btn = QR.CreateModernIconButton(parent, 24, "X")
    t:assertNotNil(btn._icon, "Has icon FontString")
    t:assertEqual("X", btn._icon:GetText(), "Custom glyph set correctly")
end)
