# XPCard

A minimal, background-less XP tracker for **World of Warcraft: Forever**.

```
Session        1:23:45
XP gained       48,210
XP / hour       35,100
Kills              142   reset
To level      ~37 mobs
              ~18m left
```

- **Session timer.** Survives `/reload` and resets on a fresh login.
- **XP gained** this session, from all sources.
- **XP per hour**, based on your session so far.
- **Kill counter** with a reset button.
- **Mobs to level**, estimated from your average XP per kill.
- **Time to level**, estimated from your XP per hour.
- No background, adjustable opacity and scale, Shift-drag to move.

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
| `/xpc opacity 0.6` | Opacity, 0.2–1 |
| `/xpc scale 1.2` | Scale, 0.7–1.5 |
| `/xpc center` | Move the card back to the middle |
| `/xpc options` | Open Options → AddOns → XPCard |

**Move the card:** hold **Shift** and drag it. The rest of the time it ignores the mouse, so clicks go through to the world.

## How kills are counted

WoW: Forever applies Midnight's addon restrictions, so addons can't read the combat log. XPCard counts kills with the `PARTY_KILL` event and matches each one to the XP gain that follows it:

- Your own killing blows always count. Grey mobs count too, with 0 XP.
- A party member's kill counts only if it gave you XP.
- Quest and exploration XP is added to *XP gained* but not to the per-kill average.

If `PARTY_KILL` doesn't exist on the client, XPCard falls back to the "*X dies, you gain N experience*" chat message.

## Development

Keep the repo anywhere and link the addon folder into the game so you only edit one copy:

```bat
mklink /J "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\XPCard" "C:\path\to\xpcard\XPCard"
```

Then edit and `/reload`. Turn on Lua errors with `/console scriptErrors 1`. `/xpc debug` prints the version and which kill source is active.

The full design spec is in [`docs/XPCard_Spec.md`](docs/XPCard_Spec.md).

### Releasing

Push a tag like `v0.1.0`. GitHub Actions zips the `XPCard/` folder and attaches it to a new release.

```bash
git tag v0.1.0
git push origin v0.1.0
```

## License

[MIT](LICENSE)
