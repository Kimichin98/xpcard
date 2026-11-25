-- XPCard: Core
-- Session state, XP tracking and combat-log-free kill counting.

local ADDON_NAME, ns = ...

ns.version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- WoW: Forever runs the Midnight "secret values" rules. Tainted code must
-- never compare or do arithmetic on a secret, so every payload value is
-- checked first. On clients without the API nothing is secret.
local issecret = issecretvalue or function() return false end
ns.issecret = issecret

local KILL_WINDOW = 1.5      -- seconds to match a kill with its XP gain
local MIN_RATE_SECONDS = 10  -- don't show XP/hour before this

local function Print(msg)
    print("|cffc9a2ffXPCard|r: " .. tostring(msg))
end
ns.Print = Print

local function CopyDefaults(src, dst)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

local DB_DEFAULTS = {
    textOpacity = 1.0,
    scale       = 1.0,
    locked      = false,
    hidden      = false,

    bgEnabled   = false,
    bgOpacity   = 0.4,
    bgColor     = { r = 0.05, g = 0.05, b = 0.07 },
    bgBorder    = false,

    progressBar = true,
    compact     = false,
    pauseAFK    = true,

    rows = {
        session = true,
        xp      = true,
        rate    = true,
        kills   = true,
        level   = true,
        time    = true,
    },
}

local CHAR_DEFAULTS = {
    point   = { "CENTER", "CENTER", 0, 200 },
    session = {
        startTime = 0,
        xp        = 0,
        kills     = 0,
        killXP    = 0,
        paused    = 0,     -- seconds spent AFK (not counted)
        -- afkSince = time() while AFK, nil otherwise
    },
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local lastXP, lastMax         -- snapshot of the XP bar
local pendingKills = {}       -- kills waiting for an XP gain: { t=, counted= }
local pendingXP = {}          -- XP gains waiting for a kill: { t=, amount= }

local function Session()
    return XPCardCharDB.session
end

local function Prune(queue, now)
    while queue[1] and now - queue[1].t > KILL_WINDOW do
        table.remove(queue, 1)
    end
end

local function SnapshotXP()
    lastXP  = UnitXP("player") or 0
    lastMax = UnitXPMax("player") or 0
end

function ns.AtMaxLevel()
    if IsPlayerAtEffectiveMaxLevel then
        return IsPlayerAtEffectiveMaxLevel()
    end
    local cap = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or 60
    return (UnitLevel("player") or 0) >= cap
end

---------------------------------------------------------------------------
-- Session control
---------------------------------------------------------------------------

-- Pause the session clock while flagged AFK, so breaks don't drag XP/hour down.
function ns.UpdateAFK()
    local s = Session()
    local afk = XPCardDB.pauseAFK and UnitIsAFK("player") or false
    if issecret(afk) then return end
    local now = time()
    if afk and not s.afkSince then
        s.afkSince = now
    elseif not afk and s.afkSince then
        s.paused = (s.paused or 0) + math.max(0, now - s.afkSince)
        s.afkSince = nil
    end
    if ns.Refresh then ns.Refresh() end
end

function ns.IsPaused()
    return Session().afkSince ~= nil
end

function ns.NewSession()
    local s = Session()
    s.startTime = time()
    s.xp, s.kills, s.killXP = 0, 0, 0
    s.paused, s.afkSince = 0, nil
    wipe(pendingKills)
    wipe(pendingXP)
    SnapshotXP()
    ns.UpdateAFK()
end

function ns.ResetKills()
    local s = Session()
    s.kills, s.killXP = 0, 0
    wipe(pendingKills)
    wipe(pendingXP)
    if ns.Refresh then ns.Refresh() end
end

function ns.ResetAll()
    ns.NewSession()
    if ns.Refresh then ns.Refresh() end
end

---------------------------------------------------------------------------
-- Stats for the UI
---------------------------------------------------------------------------

function ns.GetStats()
    local s = Session()
    local now = time()
    local afk = s.afkSince and (now - s.afkSince) or 0
    local elapsed = math.max(0, now - (s.startTime or now) - (s.paused or 0) - afk)
    local stats = {
        elapsed = elapsed,
        paused  = s.afkSince ~= nil,
        xp      = s.xp,
        kills   = s.kills,
        maxLevel = ns.AtMaxLevel(),
    }

    if elapsed >= MIN_RATE_SECONDS then
        stats.xpPerHour = s.xp / (elapsed / 3600)
    end

    if not stats.maxLevel then
        local remaining = (UnitXPMax("player") or 0) - (UnitXP("player") or 0)
        if remaining > 0 then
            if s.kills > 0 and s.killXP > 0 then
                stats.mobsToLevel = math.ceil(remaining / (s.killXP / s.kills))
            end
            if stats.xpPerHour and stats.xpPerHour > 0 then
                stats.secondsToLevel = remaining / stats.xpPerHour * 3600
            end
        end
    end

    return stats
end

---------------------------------------------------------------------------
-- Kill / XP matching
--
-- Kills and XP gains don't arrive in a guaranteed order, so each side waits
-- briefly (KILL_WINDOW) for the other. Own kills count right away; kills by
-- party members (or by a secret attacker) only count if they gave us XP.
---------------------------------------------------------------------------

local function OnKill(countedAlready)
    local now = GetTime()
    local s = Session()
    Prune(pendingXP, now)

    local xp = table.remove(pendingXP, 1)
    if xp then
        s.kills = s.kills + 1
        s.killXP = s.killXP + xp.amount
    else
        if countedAlready then
            s.kills = s.kills + 1
        end
        Prune(pendingKills, now)
        pendingKills[#pendingKills + 1] = { t = now, counted = countedAlready }
    end
    if ns.Refresh then ns.Refresh() end
end

local function OnXPGained(amount)
    local now = GetTime()
    local s = Session()
    s.xp = s.xp + amount

    Prune(pendingKills, now)
    local kill = table.remove(pendingKills, 1)
    if kill then
        if not kill.counted then
            s.kills = s.kills + 1
        end
        s.killXP = s.killXP + amount
    else
        Prune(pendingXP, now)
        pendingXP[#pendingXP + 1] = { t = now, amount = amount }
    end
    if ns.Refresh then ns.Refresh() end
end

---------------------------------------------------------------------------
-- Chat fallback pattern ("%s dies, you gain %d experience.")
---------------------------------------------------------------------------

local function FormatToPattern(fmt)
    local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    return "^" .. p
end

local XP_KILL_PATTERN = FormatToPattern(
    type(COMBATLOG_XPGAIN_FIRSTPERSON) == "string" and COMBATLOG_XPGAIN_FIRSTPERSON
    or "%s dies, you gain %d experience.")

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}

function handlers.ADDON_LOADED(name)
    if name ~= ADDON_NAME then return end
    frame:UnregisterEvent("ADDON_LOADED")

    -- Migrate pre-release "opacity" (whole card) to "textOpacity".
    if type(XPCardDB) == "table" and XPCardDB.opacity ~= nil then
        if XPCardDB.textOpacity == nil then XPCardDB.textOpacity = XPCardDB.opacity end
        XPCardDB.opacity = nil
    end

    XPCardDB = CopyDefaults(DB_DEFAULTS, XPCardDB)
    XPCardCharDB = CopyDefaults(CHAR_DEFAULTS, XPCardCharDB)

    if ns.InitUI then ns.InitUI() end
    if ns.InitOptions then ns.InitOptions() end
end

function handlers.PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
    local s = Session()
    if isInitialLogin or not s.startTime or s.startTime == 0 then
        ns.NewSession()           -- fresh login: new session
    else
        SnapshotXP()              -- /reload or zoning: keep session
        ns.UpdateAFK()
    end
    if ns.Refresh then ns.Refresh() end
end

function handlers.PLAYER_FLAGS_CHANGED(unit)
    if unit == "player" then ns.UpdateAFK() end
end

function handlers.PLAYER_XP_UPDATE(unit)
    if unit and unit ~= "player" then return end
    local cur = UnitXP("player") or 0
    local max = UnitXPMax("player") or 0
    if issecret(cur) or issecret(max) then return end

    if lastXP == nil then
        lastXP, lastMax = cur, max
        return
    end

    local delta
    if cur < lastXP then
        -- Bar wrapped: we leveled up.
        delta = (lastMax - lastXP) + cur
    else
        delta = cur - lastXP
    end
    lastXP, lastMax = cur, max

    if delta > 0 then
        OnXPGained(delta)
    end
end

function handlers.PLAYER_LEVEL_UP()
    -- XP math is handled in PLAYER_XP_UPDATE; just redraw once values settle.
    C_Timer.After(0.5, function() if ns.Refresh then ns.Refresh() end end)
end

function handlers.PARTY_KILL(attackerGUID)
    if attackerGUID == nil or issecret(attackerGUID) then
        OnKill(false)             -- unknown killer: count if XP follows
        return
    end
    local me = UnitGUID("player")
    if me and not issecret(me) and attackerGUID == me then
        OnKill(true)
    else
        OnKill(false)             -- party member's kill: count if it gave XP
    end
end

function handlers.CHAT_MSG_COMBAT_XP_GAIN(text)
    if type(text) ~= "string" or issecret(text) then return end
    if text:match(XP_KILL_PATTERN) then
        OnKill(true)
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    local fn = handlers[event]
    if fn then
        xpcall(fn, geterrorhandler(), ...)
    end
end)

local function IsEventValid(event)
    if C_EventUtils and C_EventUtils.IsEventValid then
        return C_EventUtils.IsEventValid(event)
    end
    return pcall(frame.RegisterEvent, frame, event) and (frame:UnregisterEvent(event) or true)
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_XP_UPDATE")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("PLAYER_FLAGS_CHANGED")

-- Only one kill source at a time, so kills are never double counted.
if IsEventValid("PARTY_KILL") then
    frame:RegisterEvent("PARTY_KILL")
    ns.killSource = "PARTY_KILL"
else
    frame:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
    ns.killSource = "CHAT_MSG_COMBAT_XP_GAIN"
end
