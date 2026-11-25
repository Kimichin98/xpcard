-- XPCard: Options panel and slash commands

local ADDON_NAME, ns = ...

local category, opacitySetting, scaleSetting, lockSetting

local function Clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

---------------------------------------------------------------------------
-- Settings panel (Options > AddOns > XPCard)
---------------------------------------------------------------------------

local function BuildSettings()
    category = Settings.RegisterVerticalLayoutCategory("XPCard")

    local function OnChanged() ns.ApplyAppearance() end
    local function Percent(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end

    -- Opacity
    opacitySetting = Settings.RegisterAddOnSetting(category, "XPCard_Opacity", "opacity",
        XPCardDB, Settings.VarType.Number, "Opacity", 1.0)
    opacitySetting:SetValueChangedCallback(OnChanged)
    local opacityOpts = Settings.CreateSliderOptions(0.2, 1.0, 0.05)
    opacityOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, Percent)
    Settings.CreateSlider(category, opacitySetting, opacityOpts, "How see-through the card is.")

    -- Scale
    scaleSetting = Settings.RegisterAddOnSetting(category, "XPCard_Scale", "scale",
        XPCardDB, Settings.VarType.Number, "Scale", 1.0)
    scaleSetting:SetValueChangedCallback(OnChanged)
    local scaleOpts = Settings.CreateSliderOptions(0.7, 1.5, 0.05)
    scaleOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, Percent)
    Settings.CreateSlider(category, scaleSetting, scaleOpts, "Size of the card.")

    -- Lock
    lockSetting = Settings.RegisterAddOnSetting(category, "XPCard_Locked", "locked",
        XPCardDB, Settings.VarType.Boolean, "Lock position", false)
    local CreateCheckbox = Settings.CreateCheckbox or Settings.CreateCheckBox
    CreateCheckbox(category, lockSetting, "Prevent Shift-dragging the card.")

    Settings.RegisterAddOnCategory(category)
end

function ns.InitOptions()
    local ok, err = pcall(BuildSettings)
    if not ok then
        -- Slash commands still work if the Settings API differs on this client.
        category = nil
        ns.Print("Options panel unavailable (" .. tostring(err) .. "). Use /xpc instead.")
    end
end

local function SetValue(setting, key, value)
    if setting then
        setting:SetValue(value)   -- also updates the panel and fires OnChanged
    else
        XPCardDB[key] = value
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
    "/xpc opacity <0.2-1> - set opacity",
    "/xpc scale <0.7-1.5> - set scale",
    "/xpc center - move the card back to the middle",
    "/xpc options - open the settings page",
}

SLASH_XPCARD1 = "/xpc"
SLASH_XPCARD2 = "/xpcard"
SlashCmdList.XPCARD = function(input)
    local cmd, arg = strtrim(input or ""):lower():match("^(%S*)%s*(.-)$")

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
        SetValue(lockSetting, "locked", cmd == "lock")
        ns.Print(cmd == "lock" and "Card locked." or "Card unlocked. Shift-drag to move.")
    elseif cmd == "opacity" or cmd == "scale" then
        local v = tonumber(arg)
        if not v then
            ns.Print("Usage: /xpc " .. cmd .. (cmd == "opacity" and " 0.2-1" or " 0.7-1.5"))
            return
        end
        if cmd == "opacity" then
            SetValue(opacitySetting, "opacity", Clamp(v, 0.2, 1.0))
        else
            SetValue(scaleSetting, "scale", Clamp(v, 0.7, 1.5))
        end
    elseif cmd == "center" then
        ns.ResetPosition()
    elseif cmd == "options" or cmd == "config" then
        if category then
            Settings.OpenToCategory(category:GetID())
        else
            ns.Print("Options panel unavailable on this client.")
        end
    elseif cmd == "debug" then
        ns.Print("v" .. ns.version .. ", kill source: " .. tostring(ns.killSource))
    else
        ns.Print("Commands:")
        for _, line in ipairs(HELP) do print("  " .. line) end
    end
end
