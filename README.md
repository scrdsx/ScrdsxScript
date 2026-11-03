# Scrdsx Solutions - Script

Black-themed UI + loading screen, same as BackflipFarm. Features go in `src/main.lua` (or new modules in `src/`).

```
version.txt       current version; bump on every release (clients notify when it changes)
loader.lua        the loadstring target; fetches every file in src/ and runs them
src/ui.lua        UI library (sidebar tabs, search, toggle/slider/button/label/keybind, toasts)
src/loading.lua   loading screen (Loading.run(title, subtitle, extraSteps))
src/main.lua      builds the window and wires keys
build.py          optional single-file bundle -> dist/
```

New module: add `src/<name>.lua`, add it to `MODULES` in `loader.lua` and `order` in `build.py`.

## Loadstring
```lua
getgenv().ScrdsxBase = "https://YOUR-HOST/path/"
loadstring(game:HttpGet(ScrdsxBase .. "loader.lua"))()
```
Local test: `python -m http.server 8000`, then `loadstring(game:HttpGet("http://localhost:8000/loader.lua"))()`.

Keys: RightShift hide/show, `/` focus search.
