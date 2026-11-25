# XPCard — Addon Specification

> Status: v0.1.0. Sections 3.4–3.6 were added after the first in-game test.

A minimal, background-less XP tracking card for **World of Warcraft: Forever**.

> Working name: `XPCard` (rename freely — folder name, `.toc` name and SavedVariables must all match).

---

## 1. Target client

| Item | Value |
|---|---|
| Game | World of Warcraft: Forever (released 2026-11-04) |
| Patch / Interface | 1.60.1 → `## Interface: 16001` |
| Install path | `World of Warcraft\_forever_\Interface\AddOns\XPCard\` |
| TOC suffix (optional) | `XPCard_Forever.toc` (`_Camelot` is an accepted alias) |
| UI architecture | Mainline (modern) UI and API, ~12.1.5 level — **not** the Classic Era API |
| Restrictions | Midnight "addon disarmament" rules are active, including **Secret Values** |
| Level cap | 60 |

**Verify in game before release:** `/dump select(4, GetBuildInfo())` should print `16001`. If not, use the number it prints.

### 1.1 What the restrictions mean for this addon

- `COMBAT_LOG_EVENT_UNFILTERED` / `CombatLogGetCurrentEventInfo()` are **not available**. Kill counting must not depend on the combat log.
- Some event payloads and chat messages can be **secret values**, especially in instances and during combat. Tainted (addon) code gets a Lua error if it compares or does arithmetic on a secret value. **Every value read from an event payload must be checked with `issecretvalue(v)` before use.**
- `UnitXP("player")`, `UnitXPMax("player")`, `UnitLevel("player")` and `GetXPExhaustion()` are character-progress APIs, not combat data. XP math is based on them. (Verify they're not secret: `/dump issecretvalue(UnitXP("player"))` in combat.)

---

## 2. Features

### 2.1 Displayed stats (top to bottom)

| Label | Meaning | Format example |
|---|---|---|
| **Session** | Elapsed session time | `1:23:45` |
| **XP gained** | Total XP earned this session (all sources) | `48,210` |
| **XP / hour** | `sessionXP / elapsedHours` | `35,100` |
| **Kills** | Mobs killed (manually resettable) | `142` |
| **To level** | Estimated mobs left until next level | `~37 mobs` |
| **Time to level** *(secondary line)* | `remainingXP / XPperHour` | `~18m` |

- Show `—` for any value that can't be computed yet (e.g. XP/hour in the first 10 seconds, To level before the first kill).
- At level 60: replace "To level" and "Time to level" with `Max level`.

### 2.2 How "mobs to next level" is calculated

The mob estimate comes from **average XP per kill**, not XP/hour, because XP/hour also counts quest XP and time spent not fighting:

```
remainingXP  = UnitXPMax("player") - UnitXP("player")
avgKillXP    = killXP / kills            -- killXP = XP that came from kills only
mobsToLevel  = ceil(remainingXP / avgKillXP)
timeToLevel  = remainingXP / xpPerHour   -- the XP/hour-based estimate
```

Both are shown, so the user gets "how many mobs" and "how long at my current pace". Rested XP is already included in `avgKillXP` because it's measured, not predicted.

### 2.3 Kill counting (combat-log-free)

Use this order of strategies and **subscribe to only one at a time** to avoid double counting:

1. **Primary — `PARTY_KILL`** (added in Midnight; fires when the player or a party member kills a unit; payload `attackerGUID, targetGUID`).
   - If `attackerGUID` is not secret and equals `UnitGUID("player")`, count the kill immediately.
   - Otherwise (a party member's kill, or a secret attacker GUID), count it only if `PLAYER_XP_UPDATE` reports an XP increase within ~1.5 s. That credits group kills that gave you XP and ignores the rest.
   - Kills and XP gains are matched through two short queues (kills waiting for XP, XP waiting for a kill), so it works whichever event arrives first and with several kills at once (AoE).
2. **Fallback — `CHAT_MSG_COMBAT_XP_GAIN`**, used only if `PARTY_KILL` doesn't exist on the client (`C_EventUtils.IsEventValid("PARTY_KILL")` is false).
   - Payload text looks like "*Mob dies, you gain N experience.*" Skip it entirely if `issecretvalue(text)`.
   - Ignore messages without "dies" (localized: build the pattern from the `COMBATLOG_XPGAIN_FIRSTPERSON` global string, not a hard-coded English string).

**Kill XP attribution:** a positive XP delta from `PLAYER_XP_UPDATE` within 1.5 s of a kill (before or after) goes into `killXP`. Every other XP delta (quests, exploration, turn-ins) goes only into `sessionXP`.

### 2.4 XP tracking

- On `PLAYER_XP_UPDATE`: `delta = UnitXP - lastXP`.
- On level-up (`PLAYER_LEVEL_UP`), the bar wraps: `delta = (lastMax - lastXP) + newXP`. Store `lastMax` before the level changes.
- Ignore negative deltas that aren't caused by a level-up (just resync `lastXP`).

### 2.5 Session lifecycle

| Event | Behavior |
|---|---|
| Fresh login (`PLAYER_ENTERING_WORLD`, `isInitialLogin == true`) | New session: timer, XP and kills reset |
| `/reload` (`isReloadingUi == true`) | **Keep** the session (restore from SavedVariablesPerCharacter) |
| Zoning / loading screens | No effect |
| Reset button | Resets **kills and killXP** (so the kill average stays consistent). Timer and XP gained keep running |
| `/xpc reset all` | Resets the entire session |

The timer uses `time()` (epoch seconds) for the start timestamp so it survives `/reload`. Display updates through a 1-second `C_Timer.NewTicker`, not `OnUpdate`.

---

## 3. Visual design

### 3.1 The card

- **No background, no border.** Text only, so it floats over the world.
- Font: `GameFontHighlightSmall` (or `NumberFontNormal` for values), with `OUTLINE` or shadow for readability over any terrain.
- Layout: two columns, labels left-aligned (muted grey `#B0B0B0`) and values right-aligned (white). XP/hour value accented in light purple `#C9A2FF` (the XP-bar color).
- Approximate size: 170 × 110 px. Width fits the content.
- Reset button: a small text-only `reset` button on the right side of the Kills row (plain text, because the game font may not include a ↺ glyph). Text highlights on hover, with a tooltip: "Reset kill count".

### 3.2 Mockup

```
Session        1:23:45
XP gained       48,210
XP / hour       35,100
Kills              142   reset
To level      ~37 mobs
              ~18m left
```

### 3.3 Interaction

- **Move:** Shift + left-drag. The card only takes the mouse while Shift is held (no visual change), so normal clicks pass through to the world. Position saved per character.
- **Lock:** `/xpc lock` disables dragging.
- **Opacity:** a slider from 0.2 to 1.0 (step 0.05, default 1.0) that sets `frame:SetAlpha()`.
  - It lives in the addon's page under Options → AddOns, registered with the modern `Settings` API (`Settings.RegisterVerticalLayoutCategory` + `Settings.CreateSlider`).
  - Also: `/xpc opacity 0.6`. (Superseded by 3.4: this is now *text* opacity.)
- **Scale (nice-to-have):** a second slider, 0.7–1.5.


### 3.4 Background (optional, off by default)

- Toggle, color (color picker or `/xpc bgcolor RRGGBB`), opacity 0.05–1 (default 0.4), optional 1px dark border.
- Built with `BackdropTemplate` on the card frame. All text, the reset button and the XP bar live in a child `content` frame, so **text opacity** (`content:SetAlpha`) and **background opacity** (backdrop color alpha) are independent.
- The old single "opacity" setting is migrated to `textOpacity`.

### 3.5 Rows, XP bar, compact mode

- Each row can be hidden; the card height reflows. Hiding *Kills* also hides the reset button. If *To level* is hidden, the *Time to level* row gets its own label.
- XP bar: 2px bar along the bottom, current XP in the accent color with rested XP (`GetXPExhaustion()`) shaded blue behind it. Hidden at max level.
- Compact mode: one line, `1:23:45 · 48.2k xp · 35.1k/h · 142 kills · ~37 to lvl · ~18m`, honoring the row toggles. Width follows the text, rounded up to 10px to avoid jitter.

### 3.6 AFK pause (on by default)

- On `PLAYER_FLAGS_CHANGED`, if `UnitIsAFK("player")`: store `session.afkSince = time()`. On return, add the gap to `session.paused`.
- `elapsed = now - startTime - paused - (afkSince and now - afkSince or 0)`. Persisted, so it survives `/reload`.
- The session value turns grey with an "AFK" tag while paused.
- No highlight on Shift: the card silently becomes draggable while Shift is held (removed after testing, as it was distracting).

---

## 4. Slash commands

| Command | Action |
|---|---|
| `/xpc` | Toggle card visibility |
| `/xpc reset` | Reset kills (same as the button) |
| `/xpc reset all` | Reset the whole session |
| `/xpc lock` / `/xpc unlock` | Toggle dragging |
| `/xpc opacity <0.2–1>` | Set opacity |
| `/xpc options` | Open the settings page |

---

## 5. File structure

```
XPCard/
├── XPCard.toc
├── Core.lua        -- event handling, XP/kill math, session state
├── UI.lua          -- card frame, font strings, reset button, dragging
└── Options.lua     -- Settings panel (opacity/scale sliders), slash commands
```

### 5.1 `XPCard.toc`

```
## Interface: 16001
## Title: XPCard
## Notes: Minimal XP/hour, kills and time-to-level card.
## Author: <you>
## Version: 0.1.0
## SavedVariables: XPCardDB
## SavedVariablesPerCharacter: XPCardCharDB

Core.lua
UI.lua
Options.lua
```

### 5.2 Saved data

```lua
XPCardDB = {                 -- account-wide settings
  opacity = 1.0,
  scale   = 1.0,
  locked  = false,
}

XPCardCharDB = {             -- per character
  point   = { "CENTER", nil, "CENTER", 0, 200 },
  session = {                -- restored only on /reload
    startTime = 0,           -- time()
    xp        = 0,
    kills     = 0,
    killXP    = 0,
  },
}
```

---

## 6. Events used

| Event | Purpose |
|---|---|
| `ADDON_LOADED` | Init SavedVariables with defaults |
| `PLAYER_ENTERING_WORLD` | Detect fresh login vs. reload; snapshot `lastXP` / `lastMax` |
| `PLAYER_XP_UPDATE` | XP delta calculation |
| `PLAYER_LEVEL_UP` | Wrap-around delta |
| `PARTY_KILL` | Primary kill counter |
| `CHAT_MSG_COMBAT_XP_GAIN` | Fallback kill counter only |
| `PLAYER_LOGOUT` | Final write of session state |

Not used: `COMBAT_LOG_EVENT_UNFILTERED` (unavailable on this client).

---

## 7. Edge cases

- **Group play:** party members' kills that give you no XP aren't counted (see 2.3).
- **Mobs that give no XP (grey):** counted as kills but add 0 to killXP, which lowers the average. Accepted behavior, since it reflects real pace.
- **Dungeons:** chat payloads may be secret inside instances; the `issecretvalue` guards make the addon skip them silently, never throw errors.
- **XP/hour early in a session:** hide until 10 s have passed to avoid absurd numbers.
- **Number formatting:** use `BreakUpLargeNumbers()` for thousands separators.
- **Errors:** wrap event handlers so one bad payload never breaks the card.

---

## 8. Test checklist

1. `/dump select(4, GetBuildInfo())` → confirm interface number.
2. `/etrace`, then kill a mob solo → confirm `PARTY_KILL` fires and check whether its GUIDs are secret.
3. Kill solo in the open world → Kills +1, killXP grows, To level updates.
4. Turn in a quest → XP gained grows, Kills and avg kill XP unchanged.
5. Ding a level mid-session → no negative or huge XP spike.
6. `/reload` → session continues. Log out and back in → session resets.
7. Click Reset → kills go to 0, To level shows `—` until the next kill.
8. Enter a dungeon and fight → no Lua errors (enable `/console scriptErrors 1`).
9. Opacity slider and `/xpc opacity` both work and persist.
10. Reach 60 (or test on a 60) → shows `Max level`.

---

## 9. Out of scope (v1)

- Gold per hour, reputation, honor tracking
- History graphs across sessions
- LibDataBroker / Titan Panel integration
