-- XPCard: UI
-- A background-less text card. Shift + drag to move.

local _, ns = ...

local WIDTH      = 172
local ROW_HEIGHT = 15
local PAD        = 4

local LABEL_COLOR = { 0.69, 0.69, 0.69 }   -- #B0B0B0
local VALUE_COLOR = { 1, 1, 1 }
local ACCENT      = { 0.79, 0.64, 1.00 }   -- #C9A2FF (XP bar purple)
local MUTED       = { 0.55, 0.55, 0.55 }

local card, rows, resetBtn, dragHint

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------

local function Num(n)
    n = math.floor((n or 0) + 0.5)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
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

local function AddRow(index, labelText)
    local y = -PAD - (index - 1) * ROW_HEIGHT

    local label = card:CreateFontString(nil, "OVERLAY", "XPCardLabelFont")
    label:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, y)
    label:SetJustifyH("LEFT")
    label:SetTextColor(unpack(LABEL_COLOR))
    label:SetText(labelText)

    local value = card:CreateFontString(nil, "OVERLAY", "XPCardValueFont")
    value:SetPoint("TOPRIGHT", card, "TOPRIGHT", -PAD - 34, y)
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
-- held and the card is unlocked. The reset button always takes clicks.
local function UpdateMouse()
    local canDrag = IsShiftKeyDown() and not XPCardDB.locked
    if card.isMoving then return end
    card:EnableMouse(canDrag)
    dragHint:SetShown(canDrag)
end

local function BuildResetButton(row)
    local b = CreateFrame("Button", nil, card)
    b:SetSize(32, ROW_HEIGHT)
    b:SetPoint("LEFT", row.value, "RIGHT", 4, 0)

    local text = b:CreateFontString(nil, "OVERLAY", "XPCardLabelFont")
    text:SetPoint("LEFT")
    text:SetText("reset")
    text:SetTextColor(unpack(MUTED))
    b.text = text

    b:SetScript("OnEnter", function(self)
        self.text:SetTextColor(unpack(ACCENT))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Reset kill count")
        GameTooltip:AddLine("Shift-drag the card to move it.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("/xpc for more options.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self.text:SetTextColor(unpack(MUTED))
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function()
        ns.ResetKills()
    end)
    return b
end

function ns.InitUI()
    MakeFont("XPCardLabelFont", GameFontHighlightSmall, 0)
    MakeFont("XPCardValueFont", GameFontHighlightSmall, 1)

    card = CreateFrame("Frame", "XPCardFrame", UIParent)
    card:SetSize(WIDTH, PAD * 2 + ROW_HEIGHT * 6)
    card:SetFrameStrata("MEDIUM")
    card:SetClampedToScreen(true)
    card:SetMovable(true)
    card:EnableMouse(false)
    card:RegisterForDrag("LeftButton")

    -- Faint highlight shown only while the card can be dragged.
    dragHint = card:CreateTexture(nil, "BACKGROUND")
    dragHint:SetAllPoints()
    dragHint:SetColorTexture(1, 1, 1, 0.08)
    dragHint:Hide()

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

    rows = {
        session = AddRow(1, "Session"),
        xp      = AddRow(2, "XP gained"),
        rate    = AddRow(3, "XP / hour"),
        kills   = AddRow(4, "Kills"),
        level   = AddRow(5, "To level"),
        time    = AddRow(6, ""),
    }
    rows.rate.value:SetTextColor(unpack(ACCENT))
    rows.time.value:SetTextColor(unpack(MUTED))
    resetBtn = BuildResetButton(rows.kills)

    RestorePosition()
    ns.ApplyAppearance()

    C_Timer.NewTicker(1, function() ns.Refresh() end)
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

function ns.ApplyAppearance()
    if not card then return end
    card:SetAlpha(XPCardDB.opacity or 1)
    card:SetScale(XPCardDB.scale or 1)
    card:SetShown(not XPCardDB.hidden)
end

function ns.ToggleShown()
    XPCardDB.hidden = not XPCardDB.hidden
    ns.ApplyAppearance()
end

function ns.ResetPosition()
    XPCardCharDB.point = { "CENTER", "CENTER", 0, 200 }
    if card then RestorePosition() end
end

function ns.Refresh()
    if not card or not card:IsShown() then return end
    local s = ns.GetStats()

    rows.session.value:SetText(Clock(s.elapsed))
    rows.xp.value:SetText(Num(s.xp))
    rows.rate.value:SetText(s.xpPerHour and Num(s.xpPerHour) or "—")
    rows.kills.value:SetText(Num(s.kills))

    if s.maxLevel then
        rows.level.value:SetText("Max level")
        rows.time.value:SetText("")
    else
        rows.level.value:SetText(s.mobsToLevel and ("~" .. Num(s.mobsToLevel) .. " mobs") or "—")
        rows.time.value:SetText(s.secondsToLevel and ("~" .. Duration(s.secondsToLevel) .. " left") or "")
    end
end
