# Mad City Menu

## Layout

```
Main.lua                  entry point (the executor only loads this)
src/
  Shared.lua              services, window settings, sidebar groups, feature order
  Theme.lua               custom WindUI "Mad City" theme
  Library.lua             WindUI loader (Studio: ReplicatedStorage, live: GitHub)
  Menu.lua                window shell, sidebar groups, and tab registration
  features/
    Movement/
      Init.lua            tab definition + feature list
      Flight.lua          fly toggle, keybind, speed slider
    Player/
      Init.lua
    Teleport/
      Init.lua
    Visuals/
      Init.lua
    Misc/
      Init.lua
```

The menu loads WindUI, applies the custom **Mad City** theme, and opens
Movement, Player, Teleport, Visuals, and Misc tabs. Tabs are grouped in the
sidebar under **Gameplay**, **World**, and **Utility**. Each feature file under
a tab folder adds its own controls.

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
- `src/Menu.lua` — creates the window, sidebar groups, and exposes `menu:addTab(...)`
- `src/features/<Tab>/Init.lua` — tab definition and its feature list
- `src/features/<Tab>/<Feature>.lua` — one feature per file

### Adding a feature

Create `src/features/Movement/<Feature>.lua`:

```lua
local Example = {}

function Example.build(tab, menu)
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
