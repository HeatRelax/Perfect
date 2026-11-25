# Mad City Auto Robber

## Layout

```
Main.lua                  entry point (the executor only loads this)
src/
  Shared.lua              services, settings, game primitives, cash formatting
  Core.lua                flow engine (travel, guards, idling, HUD, rejoin, disconnect recovery)
  Performance.lua         automatic max-FPS / black-screen boost
  robberies/
    Jewelry.lua
    Club.lua
    Casino.lua
    Bank.lua
```

## HUD

The overlay shows the live cash, level, XP, and current step. Cash is expanded
and comma-formatted, so both `$10342575` and `$10M` display as an exact amount
such as `$10,342,575`.

Below the stats panel, a player list shows every player in the server. Each
name is colored with that player's team color; players without a team appear
gray. The list updates automatically as players join, leave, or change teams.

## Disconnect recovery

The Auto Robber watches for Roblox's disconnect/kick prompt. When the client is
kicked or loses its connection, it:

- shows `Connection lost - rejoining...`, `Kicked - rejoining...`, or a similar
  message in the stats HUD;
- logs the full error code and message to the executor console;
- waits one second, then tries to teleport back to the same server;
- if that fails, teleports to a new server for the same place;
- retries up to four times with a short delay between attempts.

The watcher listens to both `GuiService.ErrorMessageChanged` and the
`RobloxPromptGui.promptOverlay` error prompt, so it still works if one signal is
missed. `GuiService:GetErrorCode()` is used to ignore errors that a rejoin cannot
fix, such as moderation, security checks, a wrong client version, or a private
server kick. It also ignores `DisconnectClientRequest`, which is what an
intentional leave looks like.

The Auto Robber's own `core:rejoin()` flow sets an internal `rejoining` /
`teleporting` guard before it kicks or teleports, so the watcher never treats
its own rejoin as an accidental disconnect.

Limitations: this runs inside the Roblox client. If the client process crashes,
hangs, or is closed, Lua stops running and nothing can rejoin. If the internet is
completely down, the teleport calls will keep failing until it returns; the
script gives up after four attempts and leaves `Reconnect failed - rejoin
manually` in the HUD. A Roblox-wide outage or a moderation ban cannot be bypassed
by rejoining.

## FPS boost

The script enables the max-FPS setup automatically at startup; there is no menu
or panel. It applies:

- **Black Screen** — disables 3D rendering and covers the game in black.
- **Low Graphics** — forces the lowest Roblox quality level.
- **No Shadows** — disables global and soft shadows.
- **No Post Effects** — removes bloom, blur, depth of field, sky, and atmosphere.
- **No Particles** — disables particle emitters, trails, beams, fire, and smoke.
- **Low Terrain** — flattens water waves and reflections.
- **Hide Roblox UI** — hides the Roblox topbar, chat, player list, and backpack; the Auto Robber overlays stay visible.
- **Unlock FPS** — raises the executor FPS cap.

The Auto Robber stats HUD stays visible above the black overlay.

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
- `src/Performance.lua` — automatic FPS boost and black screen
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
| `core:hasCash(target)` | reads the cash HUD |
| `core:lockChecker(name, lockWhenMissing)` | builds a heist lock checker |
| `core:setStep(label)` | updates the overlay status |
| `core:rejoin()` | rejoin the same server |
| `core:getInstancePosition(instance)` | part/model position helper |
| `core:findPrompt(container)` | finds a ProximityPrompt |
