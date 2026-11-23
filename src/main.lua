-- Scrdsx Solutions (Emergency Hamburg). Entry point: loading screen, the window, one file per tab (src/tabs/), configs, unload.
-- Folders:  core/ (config, sounds, logo, icons, loading)   ui/ (the UI library)   tabs/ (what each tab shows)
--           combat/  visuals/  vehicle/  drive/  player/  client/   (the features themselves)
local UIS = game:GetService("UserInputService")
local UI = __import("ui/init")
local Sfx = __import("core/sfx")
local Loading = __import("core/loading")
local FPS = __import("client/fps")
local Prank = __import("client/prank")

local env = getgenv and getgenv() or _G
local TITLE = "Scrdsx"
local SUBTITLE = "Solutions  v" .. tostring(env.ScrdsxVersion or "?")
print("[Scrdsx] running " .. SUBTITLE)

-- a second run replaces the first
if env.__ScrdsxScript then pcall(env.__ScrdsxScript) end

-- a module that fails to start must not take the whole script down: every Start() goes through safe()
local startErrors = {}
local function safe(name, f)
	local ok, err = pcall(f)
	if not ok then
		startErrors[#startErrors + 1] = name .. ": " .. tostring(err)
		warn("[Scrdsx] " .. name .. " failed to start: " .. tostring(err))
	end
end

Loading.run(TITLE, SUBTITLE)
local win = UI.new({ Title = TITLE, Subtitle = SUBTITLE })

local alive = true
local ctx = {
	win = win, UI = UI, safe = safe, startErrors = startErrors,
	alive = function() return alive end,
	-- a dropdown from a list (kept as a helper: many tabs build their choices this way)
	cycle = function(parent, title, list, get, set) return parent:Choice({ Name = title, Options = list, Default = get(), Callback = set }) end,
}

-- TABS (order = order in the sidebar) -------------------------------------------------------------------------------------------
for _, name in ipairs({ "aim", "visuals", "chams", "crosshair", "skins", "vehicle", "player", "shaders", "utility" }) do
	safe("tab " .. name, function() __import("tabs/" .. name)(ctx) end)
end
safe("fps", FPS.Start)
local configs = __import("tabs/configs")(ctx)

-- every feature module, for unload (each one puts back what it changed)
local FEATURES = {
	"vehicle/vehicle", "vehicle/fly", "vehicle/anticrash", "vehicle/antiflat", "vehicle/speed", "vehicle/repair",
	"drive/autonpc", "player/player", "player/world", "player/loot", "player/hop",
	"visuals/esp", "visuals/shops", "visuals/lootesp", "visuals/chams", "visuals/skins", "visuals/shaders",
	"combat/aim", "combat/crosshair", "client/utility", "client/fps",
}
local function unload()
	pcall(configs.save, true)
	alive = false
	pcall(function() __import("drive/autodrive").Stop() end)
	for _, path in ipairs(FEATURES) do
		local m = __import(path)
		m.Changed, m.OnPolice = nil, nil
		if m.Destroy then pcall(m.Destroy) end
	end
	win:Destroy()
	env.__ScrdsxScript = nil
end
ctx.unload = unload
env.__ScrdsxScript = unload

local settings = __import("tabs/settings")(ctx)

configs.loadStart()
settings.afterLoad()

-- KEYS --------------------------------------------------------------------------------------------------------------------------
table.insert(win.conns, UIS.InputBegan:Connect(function(i, gp)
	if i.KeyCode == Enum.KeyCode.RightShift then
		win:Toggle()
	elseif i.KeyCode == Enum.KeyCode.Slash and win.visible and not gp then -- menu open: search (chat uses / too, so not while typing)
		win.searchBox:CaptureFocus()
		task.defer(function() win.searchBox.Text = "" end)
	end
	if Sfx.Keys and i.UserInputType == Enum.UserInputType.Keyboard then Sfx.Key(i.KeyCode == Enum.KeyCode.Space) end
end))

win:Notify(TITLE .. " loaded  v" .. tostring(env.ScrdsxVersion or "?"))
if #startErrors > 0 then win:Notify(#startErrors .. " part(s) failed to start (Settings > Copy diagnostics)", 6, "warn") end
Prank.Run(win, UI, function() settings.applyTheme(false) end) -- one-time joke for two friends, nothing for anybody else

-- update watcher: tells you when a newer version is published
task.spawn(function()
	local told = env.ScrdsxVersion
	task.wait(10)
	while alive and env.ScrdsxFetchVersion do
		local ok, latest = pcall(env.ScrdsxFetchVersion)
		if ok and latest ~= "" and latest ~= env.ScrdsxVersion and latest ~= told then
			told = latest
			win:Notify("Update available: v" .. latest .. "  (Settings > Update now)", 12)
		end
		task.wait(60)
	end
end)
