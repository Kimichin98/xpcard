-- XPCard: Options panel and slash commands

local ADDON_NAME, ns = ...

local category, layout
local settings = {}   -- key -> Setting object, so slash commands stay in sync

local function Clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

---------------------------------------------------------------------------
-- Settings panel (Options > AddOns > XPCard)
---------------------------------------------------------------------------

local function OnChanged() ns.ApplyAppearance() end
local function Percent(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end

local function Header(text)
    -- Cosmetic only: never let a header break the whole panel.
    if CreateSettingsListSectionHeaderInitializer and layout then
        pcall(function() layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text)) end)
    end
end

local function Slider(id, tbl, key, name, default, min, max, step, tooltip)
    local s = Settings.RegisterAddOnSetting(category, "XPCard_" .. id, key, tbl,
        Settings.VarType.Number, name, default)
    s:SetValueChangedCallback(OnChanged)
    local opts = Settings.CreateSliderOptions(min, max, step)
    opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, Percent)
    Settings.CreateSlider(category, s, opts, tooltip)
    settings[id] = s
    return s
end

local function Checkbox(id, tbl, key, name, default, tooltip, callback)
    local s = Settings.RegisterAddOnSetting(category, "XPCard_" .. id, key, tbl,
        Settings.VarType.Boolean, name, default)
    s:SetValueChangedCallback(callback or OnChanged)
    local Create = Settings.CreateCheckbox or Settings.CreateCheckBox
    Create(category, s, tooltip)
    settings[id] = s
    return s
end

local function Button(name, buttonText, onClick, tooltip)
    -- /xpc bgcolor still works if this initializer isn't available.
    if CreateSettingsButtonInitializer and layout then
        pcall(function()
            layout:AddInitializer(CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, true))
        end)
    end
end

local function BuildSettings()
    local db = XPCardDB
    category, layout = Settings.RegisterVerticalLayoutCategory("XPCard")

    Header("Card")
    Slider("TextOpacity", db, "textOpacity", "Text opacity", 1.0, 0.2, 1.0, 0.05,
        "Opacity of the text and XP bar.")
    Slider("Scale", db, "scale", "Scale", 1.0, 0.7, 1.5, 0.05, "Size of the card.")
    Checkbox("Compact", db, "compact", "Compact mode", false,
        "Show everything on a single line.")
    Checkbox("ProgressBar", db, "progressBar", "XP bar", true,
        "Thin XP bar along the bottom of the card. Rested XP is shaded blue.")
    Checkbox("Locked", db, "locked", "Lock position", false,
        "Prevent Shift-dragging the card.")

    Header("Background")
    Checkbox("BgEnabled", db, "bgEnabled", "Show background", false,
        "Draw a panel behind the text.")
    Slider("BgOpacity", db, "bgOpacity", "Background opacity", 0.4, 0.05, 1.0, 0.05,
        "Opacity of the background panel.")
    Checkbox("BgBorder", db, "bgBorder", "Border", false, "Thin dark border around the background.")
    Button("Background color", "Choose color", function() ns.PickBackgroundColor() end,
        "Pick the background color.")

    Header("Rows")
    Checkbox("RowSession", db.rows, "session", "Session time", true)
    Checkbox("RowXP", db.rows, "xp", "XP gained", true)
    Checkbox("RowRate", db.rows, "rate", "XP / hour", true)
    Checkbox("RowKills", db.rows, "kills", "Kills (and reset button)", true)
    Checkbox("RowLevel", db.rows, "level", "Mobs to level", true)
    Checkbox("RowTime", db.rows, "time", "Time to level", true)

    Header("Session")
    Checkbox("PauseAFK", db, "pauseAFK", "Pause timer while AFK", true,
        "Stop the session clock while you're flagged AFK, so breaks don't lower XP/hour.",
        function() ns.UpdateAFK() end)

    Settings.RegisterAddOnCategory(category)
end

function ns.InitOptions()
    local ok, err = pcall(BuildSettings)
    if not ok then
        -- Slash commands still work if the Settings API differs on this client.
        category = nil
        wipe(settings)
        ns.Print("Options panel unavailable (" .. tostring(err) .. "). Use /xpc instead.")
    end
end

local function SetValue(id, tbl, key, value)
    if settings[id] then
        settings[id]:SetValue(value)   -- also updates the panel and fires the callback
    else
        tbl[key] = value
        ns.ApplyAppearance()
    end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local HELP = {
    "/xpc - show or hide the card",
    "/xpc reset - reset kill count",
    "/xpc reset all - reset the whole session",
    "/xpc lock | unlock - toggle Shift-dragging",
    "/xpc opacity <0.2-1> - text opacity",
    "/xpc scale <0.7-1.5> - card scale",
    "/xpc bg - toggle background",
    "/xpc bgopacity <0.05-1> - background opacity",
    "/xpc bgcolor <RRGGBB> - background color (no argument opens the picker)",
    "/xpc compact - toggle compact mode",
    "/xpc bar - toggle XP bar",
    "/xpc center - move the card back to the middle",
    "/xpc options - open the settings page",
}

local function Toggle(id, key, label)
    local v = not XPCardDB[key]
    SetValue(id, XPCardDB, key, v)
    ns.Print(label .. (v and " on." or " off."))
end

SLASH_XPCARD1 = "/xpc"
SLASH_XPCARD2 = "/xpcard"
SlashCmdList.XPCARD = function(input)
    local cmd, arg = strtrim(input or ""):lower():match("^(%S*)%s*(.-)$")
    local num = tonumber(arg)

    if cmd == "" then
        ns.ToggleShown()
    elseif cmd == "reset" then
        if arg == "all" then
            ns.ResetAll()
            ns.Print("Session reset.")
        else
            ns.ResetKills()
            ns.Print("Kill count reset.")
        end
    elseif cmd == "lock" or cmd == "unlock" then
        SetValue("Locked", XPCardDB, "locked", cmd == "lock")
        ns.Print(cmd == "lock" and "Card locked." or "Card unlocked. Shift-drag to move.")
    elseif cmd == "opacity" then
        if not num then return ns.Print("Usage: /xpc opacity 0.2-1") end
        SetValue("TextOpacity", XPCardDB, "textOpacity", Clamp(num, 0.2, 1.0))
    elseif cmd == "scale" then
        if not num then return ns.Print("Usage: /xpc scale 0.7-1.5") end
        SetValue("Scale", XPCardDB, "scale", Clamp(num, 0.7, 1.5))
    elseif cmd == "bg" then
        Toggle("BgEnabled", "bgEnabled", "Background")
    elseif cmd == "bgopacity" then
        if not num then return ns.Print("Usage: /xpc bgopacity 0.05-1") end
        SetValue("BgOpacity", XPCardDB, "bgOpacity", Clamp(num, 0.05, 1.0))
    elseif cmd == "bgcolor" then
        local hex = arg:gsub("^#", "")
        if hex == "" then
            ns.PickBackgroundColor()
        elseif hex:match("^%x%x%x%x%x%x$") then
            local c = XPCardDB.bgColor
            c.r = tonumber(hex:sub(1, 2), 16) / 255
            c.g = tonumber(hex:sub(3, 4), 16) / 255
            c.b = tonumber(hex:sub(5, 6), 16) / 255
            ns.ApplyAppearance()
        else
            ns.Print("Usage: /xpc bgcolor 1a1a24")
        end
    elseif cmd == "compact" then
        Toggle("Compact", "compact", "Compact mode")
    elseif cmd == "bar" then
        Toggle("ProgressBar", "progressBar", "XP bar")
    elseif cmd == "center" then
        ns.ResetPosition()
    elseif cmd == "options" or cmd == "config" then
        if category then
            Settings.OpenToCategory(category:GetID())
        else
            ns.Print("Options panel unavailable on this client.")
        end
    elseif cmd == "debug" then
        ns.Print("v" .. ns.version .. ", kill source: " .. tostring(ns.killSource)
            .. ", AFK paused: " .. tostring(ns.IsPaused()))
    else
        ns.Print("Commands:")
        for _, line in ipairs(HELP) do print("  " .. line) end
    end
end
