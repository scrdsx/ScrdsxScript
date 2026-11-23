# Scrdsx Solutions (Emergency Hamburg)

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/scrdsx/ScrdsxScript/main/loader.lua?t=" .. os.time()))()
```
Keys: Right Shift hides / shows the menu, `/` searches.

## Layout
```
loader.lua          the loadstring target: pins the latest commit, downloads every module in parallel, runs src/main.lua
version.txt         current version (bump on every release; clients get an "update available" toast)
build.py            writes the module list into loader.lua + bundles everything into dist/ScrdsxScript.lua

src/main.lua        entry point: loading screen, window, tabs, configs, unload, global keys
src/tabs/           one file per menu tab (what it shows + its own keybinds): aim, visuals, chams, crosshair, skins,
                    vehicle, player, shaders, utility, configs, settings
src/ui/             the UI library
  init.lua            entry (assembles the parts below)
  theme.lua           colour tokens + palette maths (two picked colours -> whole theme)
  base.lua            helpers (tween, new, bind, text, switch), row shapes, settings registry
  window.lua          window, sidebar, header, tabs, search, toasts, module list HUD, configs, theme switching
  controls.lua        Section, Label, Button, TextBox, Choice (dropdown), Toggle, Slider, Keybind
  module.lua          module cards (two-column grid, settings open inside the card)
  colorpicker.lua     colour picker popup
src/core/           config files, sounds, logo, icons, loading screen
src/combat/         aim (camlock, assist, triggerbot), crosshair
src/visuals/        esp (players, radar, weak spots), chams (outlines, pointers, markers), skins, shaders, shops (robbery tags), lootesp
src/vehicle/        vehicle (suspension), fly, speed, anticrash, antiflat, repair
src/drive/          autodrive (driving controller), autonpc (Auto Drive modes), roadplan + roaddata (road map / route planning)
src/player/         player (stamina), world (lighting, zoom, movement), loot (quick loot), hop (server hop)
src/client/         utility (fov, zoom, info bar, anti-AFK), fps (performance options), prank

tools/              generators (icons, sounds, key sounds, road data), globals_check.py, game_dump_v3.lua
tools/probes/       one-off in-game probes used while reverse engineering the game
tools/images/       previews / debug renders
```

## Adding something
- New feature: a file in the folder it belongs to (e.g. `src/visuals/radar.lua`) returning a table with `Start()` / `Destroy()`.
- Show it in the menu: build its controls in the right `src/tabs/*.lua` (`__import("visuals/radar")`).
- Add it to `FEATURES` in `src/main.lua` so unload cleans it up.
- Run `python build.py` (updates the loader list + the bundle), bump `version.txt`, commit, push.

## Checks before a push
```
python build.py
python tools/globals_check.py src/**/*.lua     # names used but never declared (typos, missing locals)
```
