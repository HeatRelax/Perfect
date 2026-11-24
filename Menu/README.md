# Mad City Menu

## Layout

```
Main.lua                  entry point (the executor only loads this)
src/
  Shared.lua              services, window settings, feature order
  Library.lua             WindUI loader (Studio: ReplicatedStorage, live: GitHub)
  Menu.lua                window shell and tab registration
  features/
    Movement/
      Init.lua            tab definition + feature list
      Flight.lua          one feature per file
```

The menu loads WindUI and opens a window with a Movement tab. Each feature file
under the tab folder adds its own controls.

## Hosting

Upload `Main.lua` and the whole `src/` folder to the same directory on GitHub.
Point the executor at `Main.lua`:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/LuaSecurity/Perfect/refs/heads/main/Menu/Main.lua"))()
```

If the repo or folder moves, update `baseUrl` at the top of `Main.lua`.

## Editing

- `src/Shared.lua` — service references, window options, feature order
- `src/Library.lua` — WindUI source resolution; normally does not need changing
- `src/Menu.lua` — creates the window and exposes `menu:addTab(...)`
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
        Icon = "bird",
    },

    features = {},
}

function Example.build(menu)
    return menu:addTab(Example.tab)
end

return Example
```

Then add `"Example"` to `Shared.settings.featureOrder`. `featureOrder` lists
tab folders in display order.

## WindUI loading

`Library.load` tries, in order:

1. `require("./src/Init")` (local WindUI checkout)
2. `ReplicatedStorage.WindUI.Init` (Studio)
3. The WindUI `dist/main.lua` from GitHub (live)
