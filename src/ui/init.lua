-- Scrdsx UI library v4 (entry point). The look: sidebar with search and grouped tabs, a header with live fps / ping, modules as cards
-- in two columns whose settings open inside the card, dropdowns, a module list HUD and toasts. Nothing runs per frame.
--   ui/theme.lua        colour tokens + palette maths
--   ui/base.lua         helpers, row shapes, settings registry
--   ui/window.lua       window, tabs, search, toasts, module list, configs, theme switching
--   ui/controls.lua     Section, Label, Button, TextBox, Choice, Toggle, Slider, Keybind
--   ui/module.lua       module cards
--   ui/colorpicker.lua  colour picker
local UI = __import("ui/window")
local M = __import("ui/controls")
__import("ui/module")(M)
__import("ui/colorpicker")(M)
UI.TabMethods = M
return UI
