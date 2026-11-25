# XPCard

A minimal, background-less XP tracker for **World of Warcraft: Forever**.

```
Session        1:23:45
XP gained       48,210
XP / hour       35,100
Kills              142
To level       37 mobs
           18m left
━━━━━━━━━━━━━━━━━━━━━━
           reset kills
```

- **Session timer.** Survives `/reload`, resets on a fresh login, and pauses while you're AFK.
- **XP gained** this session, from all sources.
- **XP per hour**, based on your session so far.
- **Kill counter** with a reset button.
- **Mobs to level**, estimated from your average XP per kill.
- **Time to level**, estimated from your XP per hour.
- **Thin XP bar** along the bottom, with rested XP shaded blue.

### Customization

Everything is under **Options → AddOns → XPCard** (or `/xpc options`):

- **Card:** text opacity, scale, compact one-line mode, XP bar on/off, lock position.
- **Background:** off by default. Turn it on and choose its color, opacity, and an optional thin border.
- **Rows:** show or hide each line (session, XP gained, XP/hour, kills, mobs to level, time to level).
- **Session:** pause the timer while AFK (on by default).

Compact mode looks like this:

```
1:23:45  ·  48.2k xp  ·  35.1k/h  ·  142 kills  ·  37 to lvl  ·  18m left   reset
```

## Install

1. Download the latest `XPCard-x.y.z.zip` from [Releases](https://github.com/Kimichin98/xpcard/releases).
2. Extract it into:
   `World of Warcraft\_forever_\Interface\AddOns\`
   You should end up with `...\AddOns\XPCard\XPCard.toc`.
3. Restart the game, or `/reload` if it's already running.

## Usage

| Command | Action |
|---|---|
| `/xpc` | Show / hide the card |
| `/xpc reset` | Reset kill count (same as the button) |
| `/xpc reset all` | Reset the whole session |
| `/xpc lock` / `/xpc unlock` | Toggle Shift-dragging |
| `/xpc opacity 0.6` | Text opacity, 0.2–1 |
| `/xpc scale 1.2` | Scale, 0.7–1.5 |
| `/xpc bg` | Toggle background |
| `/xpc bgopacity 0.5` | Background opacity, 0.05–1 |
| `/xpc bgcolor 1a1a24` | Background color as hex (no value opens the color picker) |
| `/xpc compact` | Toggle compact mode |
| `/xpc bar` | Toggle XP bar |
| `/xpc center` | Move the card back to the middle |
| `/xpc options` | Open Options → AddOns → XPCard |

**Move the card:** hold **Shift** and drag it. The rest of the time it ignores the mouse, so clicks go through to the world.

**AFK pause:** the timer stops when the game flags you AFK, either with `/afk` or automatically after about 5 minutes idle. Those first idle minutes before the flag still count.

## How kills are counted

WoW: Forever applies Midnight's addon restrictions, so addons can't read the combat log. XPCard counts kills with the `PARTY_KILL` event and matches each one to the XP gain that follows it:

- Your own killing blows always count. Grey mobs count too, with 0 XP.
- A party member's kill counts only if it gave you XP.
- Quest and exploration XP is added to *XP gained* but not to the per-kill average.

If `PARTY_KILL` doesn't exist on the client, XPCard falls back to the "*X dies, you gain N experience*" chat message.

## Development

The full design spec is in [`docs/XPCard_Spec.md`](docs/XPCard_Spec.md).


## License

[MIT](LICENSE)
