# Mad City Menu

## Layout

```
Main.lua                  entry point (the executor only loads this)
src/
  Shared.lua              services, window settings, sidebar groups, feature order
  Theme.lua               custom WindUI "Mad City" theme
  Library.lua             WindUI loader (Studio: ReplicatedStorage, live: GitHub)
  Menu.lua                window shell, cleanup registry, and tab registration
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

The menu loads WindUI, applies the custom **Mad City** theme, and opens
Movement, Player, Combat, Teleport, Visuals, and Misc tabs. Tabs are grouped in
the sidebar under **Gameplay**, **Combat**, **World**, and **Utility**. Each
feature file under a tab folder adds its own controls.

## Interface

- Deep navy surfaces with green and cyan gradient accents.
- Grouped sidebar sections with colored tab badges.
- Window profile card, search bar, scrollbar, and resizable layout.
- Press `RightShift` to show or hide the menu.
- The open button can be dragged around the screen.

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

Unloading disconnects feature connections, removes FOV circles, restores
WeaponCore hooks, destroys the window, and clears leftover WindUI/MadCity
ScreenGuis.

## Hosting

Upload `Main.lua` and the whole `src/` folder to the same directory on GitHub.
Point the executor at `Main.lua`:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/LuaSecurity/Perfect/refs/heads/main/Menu/Main.lua"))()
```

If the repo or folder moves, update `baseUrl` at the top of `Main.lua`.

## Editing

- `src/Shared.lua` — service references, window options, sidebar groups, feature order
- `src/Theme.lua` — custom WindUI colors, gradients, and component styling
- `src/Library.lua` — WindUI source resolution; normally does not need changing
- `src/Menu.lua` — creates the window, sidebar groups, cleanup registry, and exposes `menu:addTab(...)`
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
        section = "Utility",
        Icon = "lucide:wrench",
        IconColor = Color3.fromHex("#94A3B8"),
        IconShape = "Square",
        ShowTabTitle = true,
        CustomEmptyPage = {
            Icon = "lucide:wrench",
            IconSize = 44,
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
tab folders in display order. `section` must match a key in
`Shared.settings.tabSections`.

### Changing the look

Edit `src/Theme.lua` to adjust colors and gradients. The theme is registered
before the window is created, then selected through
`Shared.settings.window.Theme`. Window size, sidebar width, open button, user
card, and toggle key live in `src/Shared.lua`.

## WindUI loading

`Library.load` tries, in order:

1. `require("./src/Init")` (local WindUI checkout)
2. `ReplicatedStorage.WindUI.Init` (Studio)
3. The WindUI `dist/main.lua` from GitHub (live)
