# Mad City Auto Robber

## Layout

```
Main.lua                  entry point (the executor only loads this)
src/
  Shared.lua              services, settings, game primitives, cash formatting
  Core.lua                flow engine (travel, guards, idling, HUD, rejoin, disconnect recovery)
  Stats.lua               runtime stats, persistence, Discord webhook reports
  Performance.lua         automatic performance boost (3D rendering stays on)
  robberies/
    Jewelry.lua
    Club.lua
    Casino.lua
    Bank.lua
```

## HUD

The overlay shows the live cash, level, XP, and current step. Cash is expanded
and comma-formatted, so both `$10342575` and `$10M` display as an exact amount
such as `$10,342,575`. The overlay and Discord reports use the total balance
(`CashHUD.Cash.Amount`); robbery completion watches the cash bag
(`CashBagHUD.Cash.Amount`) while it is visible.

Below the stats panel, a player list shows every player in the server. Each
name is colored with that player's team color; players without a team appear
gray. The list updates automatically as players join, leave, or change teams.

## Camera and team switching

The camera is locked to your character's humanoid every frame, so the game's
loading and team-selection screens cannot pull it away. Team switching is
skipped entirely when you are already on Criminals with a living character;
otherwise the script asks the game for Criminals and waits for the respawn.

All robbery cash targets are doubled for the global VIP 2x cash bonus:

| Robbery | Target |
| --- | --- |
| Bank | `$6000` |
| Casino | `$8000` |
| Club | `$12000` |
| Jewelry | `$10000` |

A robbery only counts after its bag has been seen visible and below the new
target, so a stale bag from the previous heist cannot skip the next one. When
a bag runs out of loot before the doubled target (Jewelry caps at whatever the
round's boxes hold, often `$5,000`), the game switches the bag label from
`Cash Reward` to `Robbery Success!`; the script accepts that signal and
collects instead of waiting for the farm timeout.

The doubled targets stay in place so the script immediately takes advantage
of the 2x bonus if the game re-enables it. While 2x is off, every round caps at
half the doubled target, so each robbery also defines a `baseTarget`:

| Robbery | 2x target | Base cap |
| --- | --- | --- |
| Bank | `$6000` | `$3000` |
| Casino | `$8000` | `$4000` |
| Club | `$12000` | `$6000` |
| Jewelry | `$10000` | `$5000` |

When the bag reaches its `baseTarget` and stops growing, the script collects
it after `baseCapTimeout` (4s). If 2x is active, the bag keeps filling past
the base cap toward the full doubled target, so nothing is collected early.

Three timers keep depleted servers from wasting a full farm cycle:

- `bagAppearTimeout` (20s): if no bag appears, the robbery is still on the
  server's loot cooldown, so it is skipped and the next robbery starts.
- `bagStaleTimeout` (12s): if a visible bag stops growing below the base cap
  (another player already took part of the round), the script collects the
  capped amount instead of waiting for `maxFarmSeconds` (120s). Jewelry uses
  its own flat-bag exit inside the box farm.
- `baseCapTimeout` (4s): a bag that reached its base cap is collected quickly
  instead of waiting for the full stale timeout.

Skips and capped collections are recorded in the event log, for example
`No loot at Club (cooldown, skipped)`,
`Base cap $6,000 at Club (2x off, collected)`, and
`Bag capped at $3,000 at Bank (collected)`.

## Stats & Discord reports

The Auto Robber tracks a full run in the background and posts Discord embeds.
The report includes:

- session, run, and all-time runtime;
- current cash, cash gained/lost, net change, and cash per hour;
- total cash gained, average per session, and average per robbery;
- sessions, rejoins (with reasons), disconnects, and reconnect attempts;
- robberies completed, per-hour rate, failures, breakdown, and earnings;
- idle time while other players are in the server;
- unique players seen, join events, peak server size, total player time, and a
  top-players list with each player's time and team;
- best session, best run, previous session/run, recent events, job id, ping,
  memory use, executor name, and timestamps.

Reports are sent:

- once shortly after the script starts;
- every 5 minutes (`Shared.settings.stats.reportInterval`);
- before an intentional rejoin and before auto-reconnect attempts;
- when a permanent disconnect is detected;
- on demand with `getgenv().MadCityAutoRobberStats:SendReport()`.

Stats persist across rejoins through `getgenv` and a local JSON file named
`MadCityAutoRobberStats_<PlaceId>.json` in the executor workspace. A rejoin
continues the same run; a fresh execution starts a new run.

### Webhook setup (local-only)

The webhook is **never stored in this repository**. It is read from a file in
the executor workspace:

```lua
writefile("MadCityAutoRobberWebhook.txt", "https://discord.com/api/webhooks/...")
```

To store it encoded instead of plain text:

```lua
writefile(
    "MadCityAutoRobberWebhook.txt",
    getgenv().MadCityAutoRobberEncodeWebhook("https://discord.com/api/webhooks/...")
)
```

The encoder writes an `MAD1:<hex>` payload; the script decodes it at runtime.
If `readfile`/`writefile` are unavailable, you can set the URL for the current
session only:

```lua
getgenv().MadCityAutoRobberWebhook = "https://discord.com/api/webhooks/..."
```

Useful commands:

```lua
getgenv().MadCityAutoRobberStats:SendReport()      -- send a report now
getgenv().MadCityAutoRobberStats:ReloadWebhook()   -- re-read the local file
getgenv().MadCityAutoRobberStats:GetSnapshot()     -- raw stats table
getgenv().MadCityAutoRobberStats:Stop(true)        -- stop tracking and send final
```

`MadCityAutoRobberWebhook*.txt` and `MadCityAutoRobberStats_*.json` are in
`.gitignore` and must never be committed. Webhook failures, Discord rate
limits, or a missing file are logged and ignored; they never stop the Auto
Robber. A report cannot be sent after the Roblox process crashes or is closed.

## Disconnect recovery

The Auto Robber watches for Roblox's disconnect/kick prompt. When the client is
kicked or loses its connection, it:

- shows `Connection lost - rejoining...`, `Kicked - rejoining...`, or a similar
  message in the stats HUD;
- logs the full error code and message to the executor console;
- rejoins immediately with the same method Infinite Yield uses: `Kick` +
  `Teleport` when alone in the server, otherwise `TeleportToPlaceInstance` for
  the current job;
- retries up to four times with a short delay between attempts.

The rejoin path is intentionally fast: there is no pre-teleport delay and no
long retry sleep. If the teleport cannot start, the HUD shows `Rejoin failed -
rejoin manually`.

The watcher listens to both `GuiService.ErrorMessageChanged` and the
`RobloxPromptGui.promptOverlay` error prompt, so it still works if one signal is
missed. `GuiService:GetErrorCode()` is used to ignore errors that a rejoin cannot
fix, such as moderation, security checks, a wrong client version, or a private
server kick. It also ignores `DisconnectClientRequest`, which is what an
intentional leave looks like.

The Auto Robber's own `core:rejoin()` flow sets an internal `rejoining` /
`teleporting` guard before it teleports, so the watcher never treats its own
rejoin as an accidental disconnect.

Limitations: this runs inside the Roblox client. If the client process crashes,
hangs, or is closed, Lua stops running and nothing can rejoin. If the internet is
completely down, the teleport calls will keep failing until it returns; the
script gives up after four attempts and leaves `Reconnect failed - rejoin
manually` in the HUD. A Roblox-wide outage or a moderation ban cannot be bypassed
by rejoining.

## Performance boost

The script enables the performance setup automatically at startup; there is no
menu or panel. It applies:

- **Low Graphics** — forces the lowest Roblox quality level.
- **No Shadows** — disables global and soft shadows.
- **No Post Effects** — removes bloom, blur, depth of field, sky, and atmosphere.
- **No Particles** — disables particle emitters, trails, beams, fire, and smoke.
- **Low Terrain** — flattens water waves and reflections.
- **Hide Roblox UI** — hides the Roblox topbar, chat, player list, and backpack; the Auto Robber overlays stay visible.
- **Unlock FPS** — raises the executor FPS cap.

3D rendering stays enabled; there is no black overlay. The game remains visible
and the Auto Robber stats HUD stays on top.

To turn the boost off without stopping the script:

```lua
getgenv().MadCityAutoRobberPerformance:DisableAll()
```

To restore everything and release the handle:

```lua
getgenv().MadCityAutoRobberPerformance:Destroy()
```

## Hosting

Upload `Main.lua` and the whole `src/` folder to the same directory on GitHub.
Point the executor at `Main.lua`:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/LuaSecurity/Perfect/refs/heads/main/Auto%20Robber/Main.lua"))()
```

If the repo or folder moves, update `baseUrl` at the top of `Main.lua`.

## Editing

- `src/Shared.lua` — service references, shared settings, game helpers, cash formatting
- `src/robberies/<Name>.lua` — one robbery per file (destination, cash target, behavior)
- `src/Core.lua` — shared flow engine; normally does not need changing
- `src/Stats.lua` — runtime stats, local persistence, Discord webhook reports
- `src/Performance.lua` — automatic performance boost (3D rendering stays on)
- Robbery order lives in `Shared.settings.robberyOrder`

### Adding a robbery

Create `src/robberies/<Name>.lua`:

```lua
local Example = {
    name = "Example",
    destination = Vector3.new(0, 0, 0),
    targetCash = "$1000",
    lockName = "Example",
    lockWhenMissing = true,
}

function Example.run(core)
    local isLocked = core:lockChecker(Example.lockName, Example.lockWhenMissing)

    if not core:travel(Example.destination, isLocked, "Teleporting to Example...") then
        return false
    end

    if not core:waitForCash(Example.targetCash, isLocked, "Robbing Example...") then
        return false
    end

    return core:collect("Collecting Example cash...")
end

return Example
```

Then add `"Example"` to `Shared.settings.robberyOrder`.

## Robbery API

| Method | Purpose |
| --- | --- |
| `core:travel(destination, isLocked, label)` | switch team, respawn, noclip teleport |
| `core:collect(label)` | teleport to the cash spot and collect |
| `core:waitForCash(target, isLocked, label)` | generic wait-until-cash flow |
| `core:waitForSolo(isLocked, label)` | idle while other players are present |
| `core:guard(isLocked)` | solo, alive, and heist-open check |
| `core:guardLock(isLocked)` | heist-open check only |
| `core:tweenTo(position, speed, isLocked)` | smooth movement |
| `core:startNoclip(isLocked)` / `core:stopNoclip(conn)` | noclip pump |
| `core:hasCash(target)` | reads the cash bag HUD (`CashBagHUD.Cash.Amount`) |
| `core:lockChecker(name, lockWhenMissing)` | builds a heist lock checker |
| `core:setStep(label)` | updates the overlay status |
| `core:rejoin()` | rejoin with the Infinite Yield method |
| `core:getInstancePosition(instance)` | part/model position helper |
| `core:findPrompt(container)` | finds a ProximityPrompt |
