-- XPCard: UI
-- A text card with an optional background, row toggles, a thin XP bar and
-- a one-line compact mode. Shift + drag to move.

local _, ns = ...

local WIDTH      = 140
local ROW_HEIGHT = 15
local PAD        = 6
local FOOTER_H   = 12
local FOOTER_GAP = 3
local BAR_H      = 2
local BAR_GAP    = 4

local LABEL_COLOR = { 0.69, 0.69, 0.69 }   -- #B0B0B0
local VALUE_COLOR = { 1, 1, 1 }
local ACCENT      = { 0.79, 0.64, 1.00 }   -- #C9A2FF (XP bar purple)
local MUTED       = { 0.55, 0.55, 0.55 }
local RESTED      = { 0.35, 0.55, 1.00 }   -- rested XP blue
local GOLD        = { 1.00, 0.82, 0.00 }

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Row order, top to bottom.
local ROW_ORDER = { "session", "xp", "rate", "kills", "level", "time", "gold", "goldRate" }
local ROW_LABELS = {
    session = "Session",
    xp      = "XP gained",
    rate    = "XP / hour",
    kills   = "Kills",
    level   = "To level",
    time    = "",          -- sub-line under "To level"
    gold    = "Gold looted",
    goldRate = "Gold / hour",
}

local card, content, rows, compactText, resetBtn
local xpBar, restedBar

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------

local function Num(n)
    n = math.floor((n or 0) + 0.5)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

local function Short(n)
    n = n or 0
    if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
    if n >= 1e3 then return string.format("%.1fk", n / 1e3) end
    return tostring(math.floor(n + 0.5))
end

local function Clock(sec)
    sec = math.floor(sec or 0)
    return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor((sec % 3600) / 60), sec % 60)
end

local function Duration(sec)
    if sec < 60 then return "<1m" end
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    if h > 0 then return string.format("%dh %02dm", h, m) end
    return string.format("%dm", m)
end

-- Full coin string with the game's coin icons, e.g. "12[g] 34[s] 5[c]".
local function Money(copper)
    copper = math.floor(copper or 0)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local g, sv, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    if g > 0 then return string.format("%dg %ds %dc", g, sv, c) end
    if sv > 0 then return string.format("%ds %dc", sv, c) end
    return string.format("%dc", c)
end

-- Rates drop the copper so the line stays short.
local function MoneyRate(copper)
    copper = copper or 0
    if copper >= 100 then copper = math.floor(copper / 100) * 100 end
    return Money(copper)
end

-- Compact: "12.3g", "45s", "7c".
local function ShortMoney(copper)
    copper = copper or 0
    if copper >= 10000 then return string.format("%.1fg", copper / 10000) end
    if copper >= 100 then return string.format("%ds", math.floor(copper / 100)) end
    return string.format("%dc", math.floor(copper))
end

local function Colorize(text, c)
    return string.format("|cff%02x%02x%02x%s|r", c[1] * 255, c[2] * 255, c[3] * 255, text)
end

---------------------------------------------------------------------------
-- Fonts (outlined so text reads over any terrain)
---------------------------------------------------------------------------

local function MakeFont(name, base, sizeDelta)
    local f = CreateFont(name)
    f:CopyFontObject(base)
    local path, size = f:GetFont()
    f:SetFont(path, (size or 12) + (sizeDelta or 0), "OUTLINE")
    f:SetShadowOffset(1, -1)
    f:SetShadowColor(0, 0, 0, 0.6)
    return f
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function CreateRow(key)
    local label = content:CreateFontString(nil, "OVERLAY", "XPCardLabelFont")
    label:SetJustifyH("LEFT")
    label:SetTextColor(unpack(LABEL_COLOR))
    label:SetText(ROW_LABELS[key])

    local value = content:CreateFontString(nil, "OVERLAY", "XPCardValueFont")
    value:SetJustifyH("RIGHT")
    value:SetTextColor(unpack(VALUE_COLOR))
    value:SetText("—")

    return { label = label, value = value }
end

local function SavePosition()
    local point, _, relPoint, x, y = card:GetPoint(1)
    XPCardCharDB.point = { point, relPoint, x, y }
end

local function RestorePosition()
    local p = XPCardCharDB.point
    card:ClearAllPoints()
    card:SetPoint(p[1] or "CENTER", UIParent, p[2] or "CENTER", p[3] or 0, p[4] or 200)
end

-- The card ignores the mouse (so clicks reach the world) unless Shift is
-- held and the card is unlocked. No visual change; the reset button always
-- takes clicks.
local function UpdateMouse()
    if card.isMoving then return end
    card:EnableMouse(IsShiftKeyDown() and not XPCardDB.locked)
end

local function BuildResetButton()
    local b = CreateFrame("Button", nil, content)
    b:SetSize(60, FOOTER_H)

    local text = b:CreateFontString(nil, "OVERLAY", "XPCardLabelFont")
    text:SetPoint("RIGHT")
    text:SetText("reset")
    text:SetTextColor(unpack(MUTED))
    b.text = text

    b:SetScript("OnEnter", function(self)
        self.text:SetTextColor(unpack(ACCENT))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Reset session")
        GameTooltip:AddLine("Clears the timer, XP, kills and gold.", 1, 1, 1)
        GameTooltip:AddLine("Shift-drag the card to move it.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("/xpc options for settings.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self.text:SetTextColor(unpack(MUTED))
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function() ns.ResetAll() end)
    return b
end

local function BuildBar(level)
    local bar = CreateFrame("StatusBar", nil, content)
    bar:SetStatusBarTexture(WHITE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetFrameLevel(content:GetFrameLevel() + level)
    return bar
end

function ns.InitUI()
    MakeFont("XPCardLabelFont", GameFontHighlightSmall, 0)
    MakeFont("XPCardValueFont", GameFontHighlightSmall, 1)

    card = CreateFrame("Frame", "XPCardFrame", UIParent, "BackdropTemplate")
    card:SetSize(WIDTH, 100)
    card:SetFrameStrata("MEDIUM")
    card:SetClampedToScreen(true)
    card:SetMovable(true)
    card:EnableMouse(false)
    card:RegisterForDrag("LeftButton")
    card:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })

    card:SetScript("OnDragStart", function(self)
        if XPCardDB.locked then return end
        self.isMoving = true
        self:StartMoving()
    end)
    card:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.isMoving = false
        SavePosition()
        UpdateMouse()
    end)
    card:RegisterEvent("MODIFIER_STATE_CHANGED")
    card:SetScript("OnEvent", UpdateMouse)

    -- Everything except the background lives here, so text opacity and
    -- background opacity are independent.
    content = CreateFrame("Frame", nil, card)
    content:SetAllPoints()

    rows = {}
    for _, key in ipairs(ROW_ORDER) do
        rows[key] = CreateRow(key)
    end
    rows.rate.value:SetTextColor(unpack(ACCENT))
    rows.time.value:SetTextColor(unpack(MUTED))

    compactText = content:CreateFontString(nil, "OVERLAY", "XPCardValueFont")
    compactText:SetJustifyH("LEFT")

    resetBtn = BuildResetButton()

    -- Thin XP bar: dark track, rested overlay, then current XP on top.
    restedBar = BuildBar(1)
    restedBar:SetStatusBarColor(RESTED[1], RESTED[2], RESTED[3], 0.45)
    local track = restedBar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0, 0, 0, 0.45)
    xpBar = BuildBar(2)
    xpBar:SetAllPoints(restedBar)
    xpBar:SetStatusBarColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)

    RestorePosition()
    ns.ApplyAppearance()

    C_Timer.NewTicker(1, function() ns.Refresh() end)
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

local function ShowBar()
    return XPCardDB.progressBar and not ns.AtMaxLevel()
end

-- Places the XP bar just below `y` and returns the new y.
local function LayoutBar(y)
    local show = ShowBar()
    restedBar:SetShown(show)
    xpBar:SetShown(show)
    if not show then return y end
    y = y - BAR_GAP
    restedBar:ClearAllPoints()
    restedBar:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
    restedBar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
    restedBar:SetHeight(BAR_H)
    return y - BAR_H
end

local function SizeResetButton()
    resetBtn:SetSize(math.ceil(resetBtn.text:GetStringWidth() or 40) + 2, FOOTER_H)
end

-- Compact width follows the text; rounded up so it doesn't jitter every tick.
local function SizeCompact()
    local w = compactText:GetStringWidth() or 0
    w = w + 10 + resetBtn:GetWidth()
    w = math.ceil((w + PAD * 2) / 10) * 10
    card:SetWidth(math.max(80, w))
end

local function Layout()
    local db = XPCardDB
    local y = -PAD

    if db.compact then
        -- One line; "reset" sits at the end of the line.
        for _, key in ipairs(ROW_ORDER) do
            rows[key].label:Hide()
            rows[key].value:Hide()
        end
        compactText:ClearAllPoints()
        compactText:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
        compactText:Show()

        SizeResetButton()
        resetBtn:ClearAllPoints()
        resetBtn:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)

        y = LayoutBar(y - ROW_HEIGHT)
        card:SetHeight(-y + PAD)
        SizeCompact()
    else
        compactText:Hide()
        local count = 0

        for _, key in ipairs(ROW_ORDER) do
            local row = rows[key]
            local shown = db.rows[key]
            row.label:SetShown(shown)
            row.value:SetShown(shown)
            if shown then
                row.label:ClearAllPoints()
                row.label:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
                row.value:ClearAllPoints()
                row.value:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
                y = y - ROW_HEIGHT
                count = count + 1
            end
        end
        if count == 0 then y = y - ROW_HEIGHT end

        -- "Time to level" has no label of its own unless "To level" is hidden.
        rows.time.label:SetText(db.rows.level and "" or "Time to level")

        y = LayoutBar(y)

        -- Footer: small "reset" link, bottom-right.
        SizeResetButton()
        y = y - FOOTER_GAP
        resetBtn:ClearAllPoints()
        resetBtn:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
        y = y - FOOTER_H

        card:SetWidth(WIDTH)
        card:SetHeight(-y + PAD)
    end

    resetBtn:Show()
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

function ns.ApplyAppearance()
    if not card then return end
    local db = XPCardDB
    local c = db.bgColor

    card:SetScale(db.scale or 1)
    content:SetAlpha(db.textOpacity or 1)

    if db.bgEnabled then
        card:SetBackdropColor(c.r, c.g, c.b, db.bgOpacity or 0.4)
        local edgeA = db.bgBorder and math.min(1, (db.bgOpacity or 0.4) + 0.3) or 0
        card:SetBackdropBorderColor(0, 0, 0, edgeA)
    else
        card:SetBackdropColor(0, 0, 0, 0)
        card:SetBackdropBorderColor(0, 0, 0, 0)
    end

    card:SetShown(not db.hidden)
    Layout()
    ns.Refresh()
end

function ns.ToggleShown()
    XPCardDB.hidden = not XPCardDB.hidden
    ns.ApplyAppearance()
end

function ns.ResetPosition()
    XPCardCharDB.point = { "CENTER", "CENTER", 0, 200 }
    if card then RestorePosition() end
end

function ns.PickBackgroundColor()
    local c = XPCardDB.bgColor
    local prev = { r = c.r, g = c.g, b = c.b }
    if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then
        ns.Print("Color picker unavailable. Use /xpc bgcolor RRGGBB")
        return
    end
    ColorPickerFrame:SetupColorPickerAndShow({
        r = c.r, g = c.g, b = c.b,
        hasOpacity = false,
        swatchFunc = function()
            c.r, c.g, c.b = ColorPickerFrame:GetColorRGB()
            ns.ApplyAppearance()
        end,
        cancelFunc = function()
            c.r, c.g, c.b = prev.r, prev.g, prev.b
            ns.ApplyAppearance()
        end,
    })
end

local function UpdateBar()
    if not xpBar:IsShown() then return end
    local cur, max = ns.GetXPSnapshot()   -- never secret
    local rested = GetXPExhaustion and GetXPExhaustion() or 0
    if max <= 0 then return end
    if rested == nil or ns.issecret(rested) then rested = 0 end
    xpBar:SetMinMaxValues(0, max)
    xpBar:SetValue(cur)
    restedBar:SetMinMaxValues(0, max)
    restedBar:SetValue(math.min(max, cur + (rested or 0)))
end

function ns.Refresh()
    if not card or not card:IsShown() then return end
    local s = ns.GetStats()
    local db = XPCardDB

    -- Re-layout if the bar should appear/disappear (e.g. hitting max level).
    if restedBar:IsShown() ~= (db.progressBar and not s.maxLevel) then
        Layout()
    end

    local clock = Clock(s.elapsed)
    local mobs = (not s.maxLevel and s.mobsToLevel) and (Num(s.mobsToLevel) .. " mobs") or nil
    local eta = (not s.maxLevel and s.secondsToLevel) and (Duration(s.secondsToLevel) .. " left") or nil

    if db.compact then
        local parts = {}
        local r = db.rows
        if r.session then
            parts[#parts + 1] = s.paused and Colorize(clock .. " (AFK)", MUTED) or clock
        end
        if r.xp then parts[#parts + 1] = Short(s.xp) .. " xp" end
        if r.rate then parts[#parts + 1] = Colorize((s.xpPerHour and Short(s.xpPerHour) or "—") .. "/h", ACCENT) end
        if r.kills then parts[#parts + 1] = Num(s.kills) .. " kills" end
        if s.maxLevel then
            if r.level or r.time then parts[#parts + 1] = "max level" end
        else
            if r.level then
                parts[#parts + 1] = s.mobsToLevel and (Num(s.mobsToLevel) .. " to lvl") or "— to lvl"
            end
            if r.time and s.secondsToLevel then
                parts[#parts + 1] = Colorize(Duration(s.secondsToLevel) .. " left", MUTED)
            end
        end
        if r.gold then parts[#parts + 1] = Colorize(ShortMoney(s.gold), GOLD) end
        if r.goldRate then
            parts[#parts + 1] = Colorize((s.goldPerHour and ShortMoney(s.goldPerHour) or "—") .. "/h", GOLD)
        end
        compactText:SetText(table.concat(parts, Colorize("  ·  ", MUTED)))
        SizeCompact()
    else
        rows.session.value:SetText(s.paused and (clock .. " AFK") or clock)
        rows.session.value:SetTextColor(unpack(s.paused and MUTED or VALUE_COLOR))
        rows.xp.value:SetText(Num(s.xp))
        rows.rate.value:SetText(s.xpPerHour and Num(s.xpPerHour) or "—")
        rows.kills.value:SetText(Num(s.kills))
        rows.gold.value:SetText(Money(s.gold))
        rows.goldRate.value:SetText(s.goldPerHour and MoneyRate(s.goldPerHour) or "—")

        if s.maxLevel then
            rows.level.value:SetText("Max level")
            rows.time.value:SetText(db.rows.level and "" or "Max level")
        else
            rows.level.value:SetText(mobs or "—")
            rows.time.value:SetText(eta or "")
        end
    end

    UpdateBar()
end
