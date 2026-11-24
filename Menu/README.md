# Mad City Menu

A modular Mad City menu built on [Tokyo UI](https://github.com/dohmai/Tokyo).
The entry point loads every tab and feature from GitHub, so the whole `src/`
folder can be edited independently.

## Layout

```
Main.lua                  entry point (the executor only loads this)
src/
  Shared.lua              services, window settings, feature order
  Theme.lua               Tokyo UI "Mad City" palette
  Library.lua             Tokyo UI loader + source patches
  Menu.lua                Tokyo adapter (tabs, sections, controls, cleanup)
  Signal.lua              standalone GoodSignal used by Tokyo UI
  Unload.lua              removes a previous menu instance and its GUIs
  features/
    Movement/
      Init.lua            tab definition + feature list
      Flight.lua          fly toggle, keybind, speed slider
    Player/
      Init.lua
    Combat/
      Init.lua            tab definition + shared module list
      Common.lua          targeting, team checks, wall checks, FOV circle
      Aimbot.lua          smooth camera aimbot
      SilentAim.lua       WeaponCore shot hooks
    Teleport/
      Init.lua
    Visuals/
      Init.lua
    Misc/
      Init.lua
Decompiled/
  WeaponCore.lua          local reference decompilation (not required at runtime)
```

The menu opens Movement, Player, Combat, Teleport, Visuals, and Misc tabs.
Each feature file adds its own controls to its tab. Tokyo UI lays tabs out as a
flat row and splits every tab into two columns; the adapter alternates sections
across those columns and appends paragraphs to the section that created them.

## Interface

- Dark navy surfaces with the Mad City green/cyan accent palette.
- Two-column Tokyo sections with toggles, sliders, dropdowns, keybinds, and buttons.
- Press `RightShift` to show or hide the menu.
- A short notification confirms the version when the menu loads.

## Flight

The Movement tab includes Flight:

- Toggle **Fly**, or press the configured keybind (default `F`).
- `WASD` moves relative to the camera.
- `Space` moves up, `LeftControl` moves down.
- **Fly Speed** slider adjusts movement speed.
- When a nearby vehicle seat is free, flight uses the seat-persist bypass;
  otherwise it falls back to normal flight.

## Combat

The Combat tab has two features.

### Aimbot

Moves the camera onto the nearest target inside the FOV circle.

- **Enabled** toggle, **Activation** (`Hold`, `Toggle`, `Always`), and **Aim Key**.
- **Smoothness**, **FOV**, and **Max Distance** sliders.
- **Target Part** (`Head`, `UpperTorso`, `HumanoidRootPart`).
- **Team Check**, **Wall Check**, **Prediction**, and **Show FOV** toggles.
- The prediction slider stays locked until **Prediction** is enabled.
- The FOV circle is centered on the game crosshair, which sits 58 pixels above
  the camera projection center.

### Silent Aim

Re-aims shots without moving the camera or your input.

- **Enabled** toggle, **FOV** and **Max Distance** sliders.
- **Target Part**, **Team Check**, **Wall Check**, **Max Damage**, **Show FOV**.
- **Reinstall Hooks** re-hooks WeaponCore after a respawn or script reset.
- **Hook Status** shows how many of the four shot functions are hooked.
- Hooks `WeaponCore.ShootGun`, `ShootShotgun`, `ShootTazer`, and `ShootRayGun`,
  replacing the aim point and spread, and setting damage to `1e9` when
  **Max Damage** is on. If WeaponCore hooks cannot be installed, the remote
  `ReplicatedStorage.Event` namecall path is used as a fallback.

## Unload

Loading the menu again automatically unloads the previous instance. You can
also unload it manually:

```lua
getgenv().MadCityMenu.Unload()
```

Unloading runs feature cleanups, disconnects input connections, removes FOV
circles, restores WeaponCore hooks, and calls Tokyo UI's `Unload()`, which
removes every Drawing object and destroys the `MadCityTokyo` ScreenGui.

## Hosting

Upload `Main.lua` and the whole `src/` folder to the same directory on GitHub.
Point the executor at `Main.lua`:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/LuaSecurity/Perfect/refs/heads/main/Menu/Main.lua"))()
```

If the repo or folder moves, update `baseUrl` at the top of `Main.lua`.
`Main.lua` also accepts a local test root through
`getgenv().MadCityBaseUrl`.

## Editing

- `src/Shared.lua` — service references, window options, feature order
- `src/Theme.lua` — Tokyo color keys used by every window element
- `src/Library.lua` — Tokyo UI download, dependency patches, initialization
- `src/Menu.lua` — Tokyo adapter and cleanup registry
- `src/Unload.lua` — previous-instance detection and GUI cleanup
- `src/features/<Tab>/Init.lua` — tab definition, shared modules, and feature list
- `src/features/<Tab>/<Feature>.lua` — one feature per file

### Adding a feature

Create `src/features/Movement/<Feature>.lua`:

```lua
local Example = {}

function Example.build(tab, menu, modules)
    tab:Button({
        Title = "Example button",
        Callback = function()
            print("clicked")
        end,
    })
end

return Example
```

Then add `"Example"` to the `features` list in `src/features/Movement/Init.lua`.

If a feature needs a shared helper, add the helper name to the tab's `modules`
list. The loader downloads it once and passes a keyed table to every feature:

```lua
modules = { "Common" },

features = { "Aimbot", "SilentAim" },
```

### Adding a tab

Create `src/features/<Tab>/Init.lua` with a tab config and feature list:

```lua
local Example = {
    tab = {
        Title = "Example",
        Desc = "What this tab does",
        Icon = "lucide:wrench",
        CustomEmptyPage = {
            Title = "Example",
            Desc = "Coming soon.",
        },
    },

    features = {},
}

function Example.build(menu)
    return menu:addTab(Example.tab)
end

return Example
```

Then add `"Example"` to `Shared.settings.featureOrder`. `featureOrder` lists
tab folders in display order. The `Icon` and `section` fields are kept as
metadata for future UIs; Tokyo UI renders text-only tabs.

### Changing the look

Edit the Tokyo palette in `src/Theme.lua`. Every key Tokyo UI reads is listed
there: `Accent`, `Background`, `Primary Text`, `Option Background`,
`Section Background`, and the rest of the palette. Window size, title, and the
toggle key live in `src/Shared.lua`.

## Tokyo UI loading

`Library.load` downloads
`https://raw.githubusercontent.com/dohmai/Tokyo/main/Libraries/UI`, then
patches three things before running it:

1. The broken Quenty Signal URL is replaced with this repo's `src/Signal.lua`.
2. The ScreenGui is named `MadCityTokyo` so `src/Unload.lua` can remove it.
3. Synapse's embedded base64 color-picker images are converted to data URIs.

After `library:init()`, the theme is applied with `library:SetTheme(...)`, the
toggle key is set to `RightShift`, and the empty Tokyo keybind indicator is
hidden. Tokyo UI requires an executor with `Drawing`, `makefolder`, `isfile`,
`readfile`, and `writefile`.
