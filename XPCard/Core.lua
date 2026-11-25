-- XPCard: Core
-- Session state, XP tracking, combat-log-free kill counting and gold looted.

local ADDON_NAME, ns = ...

ns.version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- WoW: Forever runs the Midnight "secret values" rules. Tainted code must
-- never compare or do arithmetic on a secret, so every value that could be
-- secret is checked first. On clients without the API nothing is secret.
local issecret = issecretvalue or function() return false end
ns.issecret = issecret

local KILL_WINDOW  = 1.5     -- seconds to match a kill with its XP gain
local LOOT_WINDOW  = 1.5     -- seconds to match a money gain with a loot signal
local MIN_RATE_SECONDS = 10  -- don't show per-hour rates before this

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
        session  = true,
        xp       = true,
        rate     = true,
        kills    = true,
        level    = true,
        time     = true,
        gold     = true,
        goldRate = true,
    },
}

local CHAR_DEFAULTS = {
    point   = { "CENTER", "CENTER", 0, 200 },
    session = {
        startTime = 0,
        xp        = 0,
        kills     = 0,
        killXP    = 0,
        gold      = 0,     -- copper looted this session
        paused    = 0,     -- seconds spent AFK (not counted)
        -- afkSince = time() while AFK, nil otherwise
    },
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local lastXP, lastMax         -- last readable snapshot of the XP bar
local xpDeferred = false      -- XP was unreadable (secret) since the snapshot
local deferredKills = {}      -- kills seen while XP was unreadable: { counted= }
local pendingKills = {}       -- kills waiting for an XP gain: { t=, counted= }
local pendingXP = {}          -- XP gains waiting for a kill: { t=, amount= }

local lastMoney
local lootSignalUntil = 0     -- money gained before this GetTime() counts as loot
local pendingMoney            -- money gain waiting for a loot signal: { t=, amount= }
local merchantOpen = false

-- Counters for /xpc debug.
local debugStats = {
    partyKill = 0, partyKillSecret = 0, xpSecret = 0, deferredBatches = 0,
    lootSignals = 0, goldCredits = 0,
}
ns.debugStats = debugStats

local function Session()
    return XPCardCharDB.session
end

local function Refresh()
    if ns.Refresh then ns.Refresh() end
end

local function Prune(queue, now)
    while queue[1] and now - queue[1].t > KILL_WINDOW do
        table.remove(queue, 1)
    end
end

local function ReadXP()
    local cur, max = UnitXP("player"), UnitXPMax("player")
    if cur == nil or max == nil or issecret(cur) or issecret(max) then
        return nil
    end
    return cur, max
end

local function SnapshotXP()
    local cur, max = ReadXP()
    if cur then
        lastXP, lastMax = cur, max
        xpDeferred = false
        wipe(deferredKills)
    else
        xpDeferred = true
    end
end

local function SnapshotMoney()
    local m = GetMoney()
    if m ~= nil and not issecret(m) then lastMoney = m end
    pendingMoney = nil
end

-- XP bar values the UI can always use safely (last readable snapshot).
function ns.GetXPSnapshot()
    return lastXP or 0, lastMax or 0
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

-- Pause the session clock while flagged AFK, so breaks don't drag rates down.
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
    Refresh()
end

function ns.IsPaused()
    return Session().afkSince ~= nil
end

function ns.NewSession()
    local s = Session()
    s.startTime = time()
    s.xp, s.kills, s.killXP, s.gold = 0, 0, 0, 0
    s.paused, s.afkSince = 0, nil
    wipe(pendingKills)
    wipe(pendingXP)
    SnapshotXP()
    SnapshotMoney()
    ns.UpdateAFK()
end

-- The reset button: clears everything (timer, XP, kills, gold).
function ns.ResetAll()
    ns.NewSession()
    Refresh()
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
        elapsed  = elapsed,
        paused   = s.afkSince ~= nil,
        xp       = s.xp,
        kills    = s.kills,
        gold     = s.gold or 0,
        maxLevel = ns.AtMaxLevel(),
    }

    if elapsed >= MIN_RATE_SECONDS then
        local hours = elapsed / 3600
        stats.xpPerHour = s.xp / hours
        stats.goldPerHour = stats.gold / hours
    end

    if not stats.maxLevel then
        local cur, max = ns.GetXPSnapshot()
        local remaining = max - cur
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
-- party members (or by a hidden attacker in a group) only count if they gave
-- us XP. If XP itself is unreadable in combat, kills are queued until it can
-- be read again and the combined XP gain is credited to them.
---------------------------------------------------------------------------

local function OnKill(own)
    local s = Session()
    if own then s.kills = s.kills + 1 end

    if xpDeferred then
        deferredKills[#deferredKills + 1] = { counted = own }
        Refresh()
        return
    end

    local now = GetTime()
    Prune(pendingXP, now)
    local xp = table.remove(pendingXP, 1)
    if xp then
        if not own then s.kills = s.kills + 1 end
        s.killXP = s.killXP + xp.amount
    else
        Prune(pendingKills, now)
        pendingKills[#pendingKills + 1] = { t = now, counted = own }
    end
    Refresh()
end

local function OnXPGained(amount)
    local now = GetTime()
    local s = Session()
    s.xp = s.xp + amount

    Prune(pendingKills, now)
    local kill = table.remove(pendingKills, 1)
    if kill then
        if not kill.counted then s.kills = s.kills + 1 end
        s.killXP = s.killXP + amount
    else
        Prune(pendingXP, now)
        pendingXP[#pendingXP + 1] = { t = now, amount = amount }
    end
end

-- Read the XP bar and credit any gain. Safe to call any time.
local function SyncXP()
    local cur, max = ReadXP()
    if not cur then
        if not xpDeferred then debugStats.xpSecret = debugStats.xpSecret + 1 end
        xpDeferred = true
        return
    end
    if lastXP == nil then
        lastXP, lastMax = cur, max
        return
    end

    local delta
    if cur < lastXP then
        delta = (lastMax - lastXP) + cur   -- bar wrapped: leveled up
    else
        delta = cur - lastXP
    end
    lastXP, lastMax = cur, max

    if xpDeferred then
        xpDeferred = false
        local batch = deferredKills
        deferredKills = {}
        if #batch > 0 then
            debugStats.deferredBatches = debugStats.deferredBatches + 1
            local s = Session()
            if delta > 0 then
                s.xp = s.xp + delta
                s.killXP = s.killXP + delta
                for _, k in ipairs(batch) do
                    if not k.counted then s.kills = s.kills + 1 end
                end
            end
            Refresh()
            return
        end
    end

    if delta > 0 then
        OnXPGained(delta)
        Refresh()
    end
end

---------------------------------------------------------------------------
-- Gold looted
--
-- Money only counts when it arrives close to a loot signal (loot window, or
-- the "You loot ..." / "Your share of the loot ..." chat event), and never
-- while a merchant is open. Quest rewards, mail and vendor sales are ignored.
-- The chat event is used only as a signal; its (possibly secret) text is
-- never read.
---------------------------------------------------------------------------

local function CreditGold(amount)
    local s = Session()
    s.gold = (s.gold or 0) + amount
    debugStats.goldCredits = debugStats.goldCredits + 1
    Refresh()
end

local function LootSignal()
    local now = GetTime()
    debugStats.lootSignals = debugStats.lootSignals + 1
    lootSignalUntil = now + LOOT_WINDOW
    if pendingMoney and now - pendingMoney.t <= LOOT_WINDOW then
        local amount = pendingMoney.amount
        pendingMoney = nil
        CreditGold(amount)
    end
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

    -- While XP is unreadable (e.g. secret in combat), keep polling so queued
    -- kills get their XP as soon as it can be read.
    C_Timer.NewTicker(1, function()
        if xpDeferred then SyncXP() end
    end)
end

function handlers.PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
    local s = Session()
    if isInitialLogin or not s.startTime or s.startTime == 0 then
        ns.NewSession()           -- fresh login: new session
    else
        SnapshotXP()              -- /reload or zoning: keep session
        SnapshotMoney()
        ns.UpdateAFK()
    end
    Refresh()
end

function handlers.PLAYER_FLAGS_CHANGED(unit)
    if unit == "player" then ns.UpdateAFK() end
end

function handlers.PLAYER_XP_UPDATE(unit)
    if unit and unit ~= "player" then return end
    SyncXP()
end

function handlers.PLAYER_LEVEL_UP()
    -- XP math is handled in SyncXP; just redraw once values settle.
    C_Timer.After(0.5, Refresh)
end

local function IsMe(guid)
    if guid == nil or issecret(guid) then return nil end
    local me, pet = UnitGUID("player"), UnitGUID("pet")
    if me and not issecret(me) and guid == me then return true end
    if pet and not issecret(pet) and guid == pet then return true end
    return false
end

function handlers.PARTY_KILL(attackerGUID)
    debugStats.partyKill = debugStats.partyKill + 1
    local inGroup = IsInGroup and IsInGroup() or false

    if not inGroup then
        -- Solo, PARTY_KILL only fires for you (or your pet): always count,
        -- even when the attacker is hidden during combat.
        if attackerGUID == nil or issecret(attackerGUID) then
            debugStats.partyKillSecret = debugStats.partyKillSecret + 1
        end
        OnKill(true)
        return
    end

    local mine = IsMe(attackerGUID)
    if mine == nil then
        debugStats.partyKillSecret = debugStats.partyKillSecret + 1
    end
    -- In a group: your kills count now, others only if they gave you XP.
    OnKill(mine == true)
end

function handlers.CHAT_MSG_COMBAT_XP_GAIN(text)
    if type(text) ~= "string" or issecret(text) then return end
    if text:match(XP_KILL_PATTERN) then
        OnKill(true)
    end
end

function handlers.PLAYER_MONEY()
    local m = GetMoney()
    if m == nil or issecret(m) then return end
    if lastMoney == nil then
        lastMoney = m
        return
    end
    local delta = m - lastMoney
    lastMoney = m
    if delta <= 0 or merchantOpen then return end

    local now = GetTime()
    if now <= lootSignalUntil then
        CreditGold(delta)
    else
        pendingMoney = { t = now, amount = delta }   -- loot signal may follow
    end
end

handlers.LOOT_READY      = LootSignal
handlers.LOOT_OPENED     = LootSignal
handlers.LOOT_CLOSED     = LootSignal
handlers.CHAT_MSG_MONEY  = LootSignal

function handlers.MERCHANT_SHOW()
    merchantOpen = true
    pendingMoney = nil
end

function handlers.MERCHANT_CLOSED()
    merchantOpen = false
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

local function SafeRegister(event)
    if IsEventValid(event) then frame:RegisterEvent(event) end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_XP_UPDATE")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("PLAYER_FLAGS_CHANGED")
frame:RegisterEvent("PLAYER_MONEY")
SafeRegister("LOOT_READY")
SafeRegister("LOOT_OPENED")
SafeRegister("LOOT_CLOSED")
SafeRegister("CHAT_MSG_MONEY")
SafeRegister("MERCHANT_SHOW")
SafeRegister("MERCHANT_CLOSED")

-- Only one kill source at a time, so kills are never double counted.
if IsEventValid("PARTY_KILL") then
    frame:RegisterEvent("PARTY_KILL")
    ns.killSource = "PARTY_KILL"
else
    frame:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
    ns.killSource = "CHAT_MSG_COMBAT_XP_GAIN"
end
