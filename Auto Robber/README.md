# Mad City Auto Robber

## Layout

```
Main.lua                  entry point (the executor only loads this)
src/
  Shared.lua              services, settings, game primitives, cash formatting
  Core.lua                flow engine (travel, guards, idling, HUD, rejoin)
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

## FPS boost

The script enables the max-FPS setup automatically at startup; there is no menu
or panel. It applies:

- **Black Screen** — disables 3D rendering and covers the game in black.
- **Low Graphics** — forces the lowest Roblox quality level.
- **No Shadows** — disables global and soft shadows.
- **No Post Effects** — removes bloom, blur, depth of field, sky, and atmosphere.
- **No Particles** — disables particle emitters, trails, beams, fire, and smoke.
- **Low Terrain** — flattens water waves and reflections.
- **Hide Roblox UI** — hides the topbar, chat, player list, and backpack.
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
