# Mad City Auto Robber

## Layout

```
Main.lua                  entry point (the executor only loads this)
src/
  Shared.lua              services, settings, game primitives, cash formatting
  Core.lua                flow engine (travel, guards, idling, HUD, rejoin, disconnect recovery)
  Stats.lua               runtime stats and local persistence
  Performance.lua         automatic performance boost (3D rendering stays on)
  MiniHeists.lua          fast sweep of the $500 map cash pickups
  robberies/
    Jewelry.lua
    Club.lua
    Casino.lua
    Bank.lua
```

## HUD

The overlay shows the live cash, level, XP, and current step. Cash is expanded
and comma-formatted, so both `$10342575` and `$10M` display as an exact amount
such as `$10,342,575`. The overlay uses the total balance
(`CashHUD.Cash.Amount`); robbery completion watches the cash bag
(`CashBagHUD.Cash.Amount`) while it is visible.

Below the stats panel, a player list shows every player in the server. Each
name is colored with that player's team color; players without a team appear
gray. The list updates automatically as players join, leave, or change teams.

## Camera and team switching

The camera is locked to your character's humanoid every frame, so the game's
loading and team-selection screens cannot pull it away. Criminals can no longer
be selected directly, so the script switches to `Prisoners` when it needs a
fresh respawn. It then teleports straight to the heist; committing the robbery
promotes the character back to Criminals. A living character is sent to the
heist without any extra respawn.

All robbery cash targets are doubled for the global VIP 2x cash bonus:

| Robbery | Target |
| --- | --- |
| Bank | `$6000` |
| Casino | `$8000` |
| Club | `$12000` |
| Jewelry | `$10000` |

A robbery only counts loot that belongs to its own round. After arriving, the
script waits `bagSettleTime` (1.5s) for the bag HUD to stop showing the
previous heist's amount, then treats whatever it shows as the stale baseline.
A round only completes when the actual bag value reaches the heist's known
maximum (the game can never pay more than the doubled target) and the bag has
grown since that baseline. If the HUD drops to near zero, a fresh round
started and its value is this round's loot; a drop to another large amount is
just a different heist's stale bag, so the baseline moves instead. This is
what stops a leftover `$12,000` Club bag from instantly completing Casino or
Bank as `+$8,000 (0s)`.
Jewelry keeps farming through empty periods: when every box is broken, the
script waits at the farm height and rescans until the store restocks, then
continues firing. It only collects once the bag reaches the full target (or
the Jewelry farm cap is hit), so the `Robbery Success!` label no longer ends a
round early. The event log reports `Jewelry: boxes empty, waiting for restock`
and `Jewelry: boxes restocked, resuming` when that happens.

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
it after `baseCapTimeout` (2s). If 2x is active, the bag keeps filling past
the base cap toward the full doubled target, so nothing is collected early.
At the doubled target the round is complete after `maxConfirmTime` (0.3s).
Jewelry skips the base-cap shortcut and always waits for the full target,
because its boxes restock.

Two timers keep depleted servers from wasting a full farm cycle:

- `bagAppearTimeout` (20s): if the bag has not grown at all, the robbery is
  still on the server's loot cooldown, so it is skipped and the next robbery
  starts.
- `maxFarmSeconds` (120s, Jewelry 180s): the hard cap on any single farm.

Skips are recorded in the event log, for example
`No loot at Club (cooldown, skipped)`.

## Bank, Casino, and Club farm spots

These three heists fill the bag automatically while the character stands on
the marked payout spot. After the teleport, `core:waitForCash` calls
`core:holdPosition(root.CFrame)`, which re-applies the position on every
`RunService.Stepped` frame for the whole farm, so gravity, physics, or server
position correction cannot drag the character off the spot.

Casino is the only one that needs an action: the four levers must be pushed to
open the vault. The script fires them every `timing.leverRefire` (0.5s) until
the bag starts growing, then stops and lets the game fill the bag. Bank and
Club do no actions at all: the character stays put until the bag reaches its
determined amount, then the script teleports to the collect point.

## Mini heists

After every robbery, and once at the start of each cycle before Jewelry, the
script sweeps the ten `$500` cash pickups under
`workspace.ObjectSelection.Cash`. Each pickup is a `Cash` model containing a
`CashReward` IntValue and a `Cash` MeshPart whose `Cash` script exposes an
`Event` RemoteEvent.

The server only accepts a pickup when the player is close to it, so the sweep
teleports onto the nearest available pickup, waits one live round trip
(`core:getBaseWait()`) for the new position to replicate, and fires the event
with the pickup part. It then polls the model for the `Nope` child the server
adds when a pickup is claimed (`Cash.Nope.Cash.Event`). As soon as `Nope`
appears the pickup counts as collected and the sweep instantly heads for the
next closest one — there is no fixed post-fire delay. If the server does not
mark the pickup within `miniHeists.confirmTimeout` (0.35s), the sweep
re-teleports and retries up to `miniHeists.fireAttempts` (2) times before
moving on. The pickup list is re-scanned every step, so the sweep always
targets the closest pickup that is still available, including one that
respawned mid-sweep.

Pickups respawn after roughly 20-60 seconds, so each sweep takes whatever is
available at that boundary without delaying the robbery cycle. A sweep also
stops early if another player joins; the next robbery then idles until the
server is solo again. Settings live in `Shared.settings.miniHeists`.

## Teleport lock

A single `PivotTo` can be undone a frame later by server position correction or
physics, which is why teleports sometimes slid off the destination. Every
travel, pivot, collect, and mini-heist teleport now also registers its target
with `core:enforcePosition(targetCFrame)`. While the lock is active, a
`RunService.Stepped` connection re-applies that CFrame and zeroes the root's
linear and angular velocity every physics step.

The lock is timed rather than indefinite, so later movement and teleports are
never blocked:

- `movement.teleportLockTime` (0.6s) — how long the target is re-applied.
- `core:holdPosition(cframe)` extends the same lock for the whole farm
  (`maxFarmSeconds`); Bank, Casino, and Club use it so the bag keeps filling.
- A newer teleport replaces the target and restarts the timer.
- `core:releasePosition()` clears it early; the Jewelry vent calls this so the
  temporary vent-trigger CFrame is not overwritten.
- `Core:stop` releases the lock along with the noclip listeners.

## Ping-based waits

The collect step no longer sleeps a fixed 1.5s at the criminal base.
`Core:getPing()` reads `Player:GetNetworkPing()` (falling back to the `Stats`
service's `Data Ping`) and `Core:getBaseWait()` waits one round trip plus a
100ms buffer, clamped to 0.1-1.0s. The server pays out when it registers the
player at the base, so the next robbery starts as soon as that round trip
finishes. Per-robbery stats use the increase of the total cash HUD across the
collect wait, capped at the heist's maximum. A fresh bag already sitting at
that maximum is recorded as the full payout even if the total HUD has not
updated yet; the bag growth measured during the heist is the fallback.

The same live wait is used before each mini-heist fire. The Jewelry vent is
fully event-driven: `workspace.JewelryStore.JewelryVent.Vent.Break` is watched
before the trigger fires, and the farm tween/volleys start on the frame that
sound plays. Character movement remains a fallback if the sound is missing,
with `timing.ventWait` (1.5s) only as a safety cap. Other checks were
tightened as well: the cash target polls every 50ms, guards every 50ms, Casino
levers refire every 0.5s, and Jewelry volleys every 0.1s.

## Jewelry box farm

Jewelry no longer tweens to one box, waits for its health to drop, and then
tweens to the next. The character follows a continuous nearest-neighbour tour
of the live boxes while every live box is fired once per volley:

- `movement.jewelryVolleyInterval` (0.1s) — time between all-box volleys.
- `movement.jewelrySpeed` (50) — normal travel speed between boxes.
- `movement.jewelryMinSpeed` (12) — minimum approach speed near a box.
- `movement.jewelrySlowRadius` (8) — distance at which movement starts slowing.

The character farms a few studs below the store floor to stay out of sight. A
transparent, anchored, client-only slab is created under the whole box area for
the duration of the farm, so gravity cannot pull the character into the void and
out of the boxes' event range. Right after the vent, the character snaps straight
to the farming height instead of falling from the travel pivot, fall velocity is
zeroed every frame, and a heartbeat clamp holds that height during the vent wait
and any pause — even while noclip has collision disabled. The slab is destroyed
when the farm ends. Settings live in `Shared.settings.movement`:

- `jewelryPlatform` (true) — enable the farm floor.
- `jewelryPlatformMargin` (30) — extra studs around the box bounds.
- `jewelryPlatformThickness` (2) — slab thickness.

When every box is broken, the farm does not stop: it keeps the character at
the farming height, waits 0.1s per scan, and resumes the volleys as soon as
the store restocks. The round is collected only at the full `$10000` target;
`jewelryMaxFarmSeconds` (180s) is the safety cap.

The server registers at most one hit per box per volley and only for boxes near
the player. Firing every box means the closest cluster breaks while the
character is already moving to the next stop; boxes outside hit range ignore
the event harmlessly. `movement.firesPerBox` is now `1` because extra calls in
the same volley do not stack.

## Stats

The Auto Robber tracks a full run in the background and shows it in the stats
overlay. It records:

- session, run, and all-time runtime;
- current cash, cash gained/lost, net change, and cash per hour;
- total cash gained, average per session, and average per robbery;
- sessions, rejoins (with reasons), disconnects, and reconnect attempts;
- robberies completed, per-hour rate, failures, breakdown, and earnings;
- mini heist sweeps, with pickups collected and cash gained;
- idle time while other players are in the server;
- unique players seen, join events, peak server size, and total player time;
- best session, best run, previous session/run, and recent events.

Stats persist across rejoins through `getgenv` and a local JSON file named
`MadCityAutoRobberStats_<PlaceId>.json` in the executor workspace. A rejoin
continues the same run; a fresh execution starts a new run. Progress is saved
every 30 seconds (`Shared.settings.stats.persistInterval`) and before
intentional rejoins, disconnect recovery, and shutdown.

Useful commands:

```lua
getgenv().MadCityAutoRobberStats:GetSnapshot()  -- raw stats table
getgenv().MadCityAutoRobberStats:Stop()         -- stop tracking and save
```

`MadCityAutoRobberStats_*.json` is in `.gitignore` and must never be committed.
A missing or unwritable state file is logged and ignored; it never stops the
Auto Robber.

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
- `src/Stats.lua` — runtime stats and local persistence
- `src/Performance.lua` — automatic performance boost (3D rendering stays on)
- `src/MiniHeists.lua` — fast sweep of the map cash pickups after each robbery
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
| `core:travel(destination, isLocked, label)` | respawn via Prisoners if needed, noclip teleport |
| `core:enforcePosition(cframe, duration)` | re-apply a teleport target on `RunService.Stepped` |
| `core:releasePosition()` | clear the active teleport lock |
| `core:collect(label)` | teleport to the criminal base, wait ping + 100ms, record the real payout |
| `core:getPing()` | live round-trip time in seconds (Player API, Stats fallback) |
| `core:getBaseWait()` | ping plus a 100ms buffer, clamped to 0.1-1.0s |
| `core:waitForCash(target, isLocked, label)` | generic wait-until-cash flow, pins the farm spot |
| `core:waitForSolo(isLocked, label)` | idle while other players are present |
| `core:guard(isLocked)` | solo, alive, and heist-open check |
| `core:guardLock(isLocked)` | heist-open check only |
| `core:tweenTo(position, speed, isLocked)` | smooth movement |
| `core:startNoclip(isLocked)` / `core:stopNoclip(conn)` | noclip pump |
| `core:hasCash(target)` | true once this heist has earned its expected payout |
| `core:getHeistEarned()` | bag growth since the heist started, capped at the heist maximum |
| `core:holdPosition(cframe)` | pin the character to the farm spot for the whole heist |
| `core:lockChecker(name, lockWhenMissing)` | builds a heist lock checker |
| `core:setStep(label)` | updates the overlay status |
| `core:rejoin()` | rejoin with the Infinite Yield method |
| `core:getInstancePosition(instance)` | part/model position helper |
| `core:findPrompt(container)` | finds a ProximityPrompt |
