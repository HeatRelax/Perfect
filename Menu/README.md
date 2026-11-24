# Mad City Menu

A modular Mad City menu built on [Tokyo UI](https://github.com/dohmai/Tokyo).
The entry point loads every tab and feature from GitHub, so the whole `src/`
folder can be edited independently.

## Layout

```
Main.lua                  entry point (the executor only loads this)
src/
  Shared.lua              services, window settings, feature order
  Theme.lua               Tokyo UI Midnight palette
  Library.lua             Tokyo UI loader + source patches
  Menu.lua                Tokyo adapter (tabs, sections, controls, cleanup)
  Signal.lua              standalone GoodSignal used by Tokyo UI
  Unload.lua              removes a previous menu instance and its GUIs
  features/
    Movement/
      Init.lua            tab definition + feature list
      Flight.lua          fly toggle, keybind, speed slider
    Combat/
      Init.lua            tab definition + shared module list
      Common.lua          targeting, team checks, wall checks, FOV circle
      Aimbot.lua          smooth camera aimbot
      SilentAim.lua       WeaponCore shot hooks
    Player/
      Init.lua            scaffold, not loaded yet
    Teleport/
      Init.lua            scaffold, not loaded yet
    Visuals/
      Init.lua            tab definition + feature list
      ESP.lua             player boxes, names, health, tracers, info flags
    Misc/
      Init.lua            tab definition + feature list
      Team.lua            Others section with team dropdown and Set Team button
Decompiled/
  WeaponCore.lua          local reference decompilation (not required at runtime)
```

The menu opens Combat, Visuals, Movement, and Misc, plus Tokyo's Settings tab.
Each feature file adds its own controls to its tab. Tokyo UI lays tabs out as a
flat row and splits every tab into two columns; the adapter alternates sections
across those columns. Controls are grouped with divider lines instead of
paragraph text. The empty Player and Teleport scaffolds stay out of
`featureOrder` until they have real controls.

## Interface

- Midnight surfaces with the purple accent palette, selected by default.
- Two-column Tokyo sections with toggles, sliders, dropdowns, keybinds, and buttons.
- Press `RightShift` to show or hide the menu.
- A short notification confirms the version when the menu loads.
- The Settings tab holds config load/save, the theme preset list, watermark and
  indicator controls, rejoin buttons, and Unload. Watermark and keybind
  indicators start hidden.

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
- **Smoothness**, **FOV** (10–2000 px, 1 px steps), and **Max Distance** sliders.
- **Circle Color** picks the FOV outline color and transparency, with
  **Circle Thickness**, **Circle Sides**, **Circle Fill**, and **Fill Opacity**
  (5–100%) controls for the ring.
- **Target Part** (`Head`, `UpperTorso`, `HumanoidRootPart`).
- **Team Check**, **Wall Check**, **Prediction**, and **Show FOV** toggles.
- The **Prediction Time** slider stays locked until **Prediction** is enabled.
- The FOV circle is dead-center in the viewport, with no crosshair or GUI inset
  offset.

### Silent Aim

Re-aims shots without moving the camera or your input.

- **Enabled** toggle, **Toggle Key** (default `T`), **FOV** (10–2000 px,
  1 px steps), and **Max Distance** sliders.
- **Circle Color**, **Circle Thickness**, **Circle Sides**, **Circle Fill**, and
  **Fill Opacity** (5–100%) customize the FOV ring.
- **Target Part**, **Team Check**, **Wall Check**, **Max Damage**, **Show FOV**.
- Hooks `WeaponCore.ShootGun`, `ShootShotgun`, `ShootTazer`, and `ShootRayGun`,
  replacing the aim point and spread, and setting damage to `1e9` when
  **Max Damage** is on. If WeaponCore hooks cannot be installed, the remote
  `ReplicatedStorage.Event` namecall path is used as a fallback.

## Visuals

The Visuals tab includes Player ESP, drawn with the executor's `Drawing` API.

- **Enabled** toggle.
- **Box**, **Name**, **Health**, **Distance**, and **Tracer** toggles.
- **Appearance**: **Box Style** (Full, Corners, 3D), **Box Fill** and
  **Fill Opacity**, **Text Outline** and **Outline Color**, **Team Colors**,
  **ESP Color**, **Name Mode** (username, display name, or both),
  **Health Side**, and **Tracer Origin** (bottom, center, or mouse).
- **Info Flags** sit beside the box: **Cash**, **Rank**, **Bounty**, and
  **Weapon** (the held tool name, shown without a label). Flags can show
  labels, move to the left side, and use their own text size.
- **Scaling** controls how the details resize: **Scale With Distance** scales
  text, flags, and gaps with the box, while **Min Detail Height** and
  **Max Detail Height** clamp that scale in pixels.
- **Filters**: **Team Check** hides players in the same Mad City category as
  you (law, criminal, or wanted); **Visible Only** raycasts to the player and
  skips anyone behind a wall; **Max Distance** caps the draw distance.
- Box and tracer colors follow the player's team category, and the health bar
  fades from red to green as health fills. Turn **Team Colors** off to use a
  custom **ESP Color** instead.
- The box projects every body part to the screen and hugs the visible
  silhouette, including the arms, legs, head, hands, and feet, so it wraps the
  character at any angle and range. Accessories and held tools are excluded
  so hats, pets, and weapons do not stretch the box. Every position and size
  is rounded to whole pixels for crisp rendering.

Drawings are pooled per player and removed on unload or when a player leaves.

## Misc

The Misc tab includes an **Others** section for team selection.

- **Team** dropdown: `Prisoners`, `Police`, `Heroes`, `Criminals`, `Wanted`,
  and `Battle Royale`.
- **Set Team** invokes `ReplicatedStorage.RemoteFunction` with
  `InvokeServer("SetTeam", team)` and reports the result.

## Unload

Loading the menu again automatically unloads the previous instance. You can
also unload it manually:

```lua
getgenv().MadCityMenu.Unload()
```

Unloading runs feature cleanups, disconnects input connections, removes FOV
circles and ESP drawings, restores WeaponCore hooks, and calls Tokyo UI's
`Unload()`, which
removes every Drawing object and destroys the `MadCityTokyo` ScreenGui. The
Settings tab's **Unload** button uses this same path.

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
`Section Background`, and the rest of the palette. The palette is registered as
the **Midnight** preset in the Settings tab and selected by default, so users
can switch to another preset and back. Window size, title, and the toggle key
live in `src/Shared.lua`.

## Tokyo UI loading

`Library.load` downloads
`https://raw.githubusercontent.com/dohmai/Tokyo/main/Libraries/UI`, then
patches three things before running it:

1. The broken Quenty Signal URL is replaced with this repo's `src/Signal.lua`.
2. The ScreenGui is named `MadCityTokyo` so `src/Unload.lua` can remove it.
3. Synapse's embedded base64 color-picker images are converted to data URIs.

After `library:init()`, the theme is applied with `library:SetTheme(...)`, the
toggle key is set to `RightShift`, and the empty Tokyo keybind indicator is
hidden. `Menu:createSettingsTab()` then calls Tokyo's
`library:CreateSettingsTab(window)`, restores the Midnight palette (Tokyo
selects its Default preset while building), and routes the settings Unload
button through the menu cleanup. Tokyo UI requires an executor with `Drawing`,
`makefolder`, `listfiles`, `isfile`, `readfile`, and `writefile`.
