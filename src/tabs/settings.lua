-- Settings tab: window (scale, blur, module list), performance, sound, theme, tools (key clash check, diagnostics), about / update / unload.
local UIS = game:GetService("UserInputService")
local UI = __import("ui/init")
local Sfx = __import("core/sfx")
local FPS = __import("client/fps")
local ESP = __import("visuals/esp")
local Visuals = __import("visuals/chams")
local Aim = __import("combat/aim")
local Crosshair = __import("combat/crosshair")
local Skins = __import("visuals/skins")
local Player = __import("player/player")
local NPC = __import("drive/autonpc")

return function(ctx)
	local win, safe, cycle = ctx.win, ctx.safe, ctx.cycle
	local env = getgenv and getgenv() or _G
	local tSet = win:Tab("Settings", { Section = "Client", Icon = 9 })
	tSet:Section("Window")
	tSet:Slider({ Name = "UI scale", Min = 0.7, Max = 1.4, Step = 0.05, Default = 1, Callback = function(v) win:SetScale(v) end })
	tSet:Slider({ Name = "Blur behind the window", Min = 0, Max = 30, Step = 1, Default = 0, Callback = function(v) win:SetBlur(v) end })
	tSet:Toggle({ Name = "Module list (top right of the screen)", Default = true, Callback = function(v) win:SetArrayList(v) end })
	-- PERFORMANCE: no FPS tab any more. The script itself is light (nothing per frame unless a visual is on); these are the optional extras.
	tSet:Section("Performance")
	local smartT = tSet:Toggle({ Name = "Smart boost (calm water, no grass sway, cheaper lighting)", Default = true, Callback = function(v) FPS.SetTerrain(v); FPS.SetLighting(v) end })
	tSet:Toggle({ Name = "Lower mesh detail far away", Default = false, Callback = function(v) FPS.SetMeshDetail(v) end })
	tSet:Toggle({ Name = "Max FPS (no shadows, no particles, no post effects)", Default = false, Callback = function(v) FPS.SetShadows(v); FPS.SetParticles(v); FPS.SetEffects(v) end })
	tSet:Toggle({ Name = "Unlock the FPS limit", Default = false, Callback = function(v) FPS.SetUnlock(v) end })
	tSet:Slider({ Name = "FPS limit", Min = 30, Max = 360, Step = 10, Default = FPS.CapValue, Suffix = " fps", Callback = function(v) FPS.SetCap(v) end })
	-- theme: accent + background as hex, applied to the window, remembered between sessions
	local THEME_FILE = "ScrdsxScript/theme.json"
	local theme = { accent = "", bg = "" }
	local function parseHex(t)
		t = tostring(t or ""):gsub("[#%s]", "")
		if #t == 3 then t = t:sub(1, 1):rep(2) .. t:sub(2, 2):rep(2) .. t:sub(3, 3):rep(2) end
		if #t ~= 6 or not t:match("^%x+$") then return nil end
		return Color3.fromRGB(tonumber(t:sub(1, 2), 16), tonumber(t:sub(3, 4), 16), tonumber(t:sub(5, 6), 16))
	end
	local function applyTheme(save)
		local P = UI.Palette(parseHex(theme.accent), parseHex(theme.bg))
		local map = win:ApplyPalette(P)
		if save then
			pcall(function()
				if writefile then
					pcall(function() if makefolder then makefolder("ScrdsxScript") end end)
					writefile(THEME_FILE, game:GetService("HttpService"):JSONEncode(theme))
				end
			end)
		end
	end
	pcall(function()
		if isfile and readfile and isfile(THEME_FILE) then
			local d = game:GetService("HttpService"):JSONDecode(readfile(THEME_FILE))
			if type(d) == "table" then theme.accent, theme.bg = tostring(d.accent or ""), tostring(d.bg or "") end
		end
	end)
	tSet:Section("Sound")
	tSet:Toggle({ Name = "Interface sounds", Default = true, Callback = function(v) Sfx.Enabled = v end })
	tSet:Toggle({ Name = "Creamy keyboard sounds (every key you press)", Default = false, Callback = function(v) Sfx.Keys = v; if v then Sfx.Preload() end end })
	tSet:Slider({ Name = "Keyboard sound volume", Min = 0, Max = 100, Step = 5, Default = 50, Suffix = "%", Callback = function(v) Sfx.KeyVolume = v / 100 end })
	tSet:Slider({ Name = "Sound volume", Min = 0, Max = 100, Step = 5, Default = 55, Suffix = "%", Callback = function(v) Sfx.Volume = v / 100 end })
	tSet:Section("Theme")
	local function toHex(c) return string.format("#%02X%02X%02X", math.floor(c.R * 255 + .5), math.floor(c.G * 255 + .5), math.floor(c.B * 255 + .5)) end
	local accentPick = tSet:ColorPicker({ Name = "Accent colour", NoSave = true, Default = UI.Palette().accent, Callback = function(col, final)
		theme.accent = toHex(col); applyTheme(final)
	end })
	local bgPick = tSet:ColorPicker({ Name = "Background colour", NoSave = true, Default = UI.Palette().bg, Callback = function(col, final)
		theme.bg = toHex(col); applyTheme(final)
	end })
	local THEMES = {
		{ "Default", UI.Palette().accent, UI.Palette().bg }, { "Mono", Color3.fromRGB(236, 237, 242), Color3.fromRGB(14, 14, 16) }, { "Aurora", Color3.fromRGB(139, 92, 246), Color3.fromRGB(11, 10, 22) }, { "Amber", Color3.fromRGB(243, 156, 18), Color3.fromRGB(14, 13, 12) }, { "Ocean", Color3.fromRGB(52, 152, 219), Color3.fromRGB(10, 16, 26) },
		{ "Violet", Color3.fromRGB(155, 110, 255), Color3.fromRGB(14, 12, 26) }, { "Mint", Color3.fromRGB(46, 204, 150), Color3.fromRGB(10, 20, 18) },
		{ "Rose", Color3.fromRGB(255, 105, 160), Color3.fromRGB(22, 12, 18) }, { "Crimson", Color3.fromRGB(231, 76, 60), Color3.fromRGB(20, 11, 11) },
	}
	local themeNames, themeName = {}, "Default"
	for _, t in ipairs(THEMES) do themeNames[#themeNames + 1] = t[1] end
	tSet:Choice({ Name = "Theme preset", NoSave = true, Options = themeNames, Default = themeName, Callback = function(v)
		themeName = v
		for _, t in ipairs(THEMES) do
			if t[1] == v then accentPick:Set(t[2]); bgPick:Set(t[3]) end
		end
	end })
	if parseHex(theme.accent) then accentPick:Set(parseHex(theme.accent), true) end
	if parseHex(theme.bg) then bgPick:Set(parseHex(theme.bg), true) end
	if theme.accent ~= "" or theme.bg ~= "" then task.defer(applyTheme, false) end
	tSet:Section("Quick accent colours")
	for _, pr in ipairs({
		{ "Blue", Color3.fromRGB(64, 132, 255) }, { "Violet", Color3.fromRGB(146, 104, 255) }, { "Green", Color3.fromRGB(46, 196, 120) },
		{ "Red", Color3.fromRGB(236, 82, 82) }, { "Orange", Color3.fromRGB(245, 160, 60) }, { "Silver", Color3.fromRGB(205, 205, 214) },
	}) do
		tSet:Button({ Name = "Accent: " .. pr[1], Callback = function()
			accentPick:Set(pr[2], true)
			theme.accent = toHex(pr[2])
			applyTheme(true)
		end })
	end
	tSet:Section("Tools")
	tSet:Button({ Name = "Check my keybinds for clashes", Callback = function()
		local GAME = { M = "Map", Tab = "Phone", L = "Headlights", H = "Horn", P = "Parking brake", G = "Hazard lights", Q = "Indicate left", E = "Indicate right", N = "Engine" }
		local byKey, msgs = {}, {}
		for id, f in pairs(win.flags) do
			if f.kind == "key" then
				local k = f.obj:Get()
				if k then
					byKey[k.Name] = byKey[k.Name] or {}
					table.insert(byKey[k.Name], (id:match("([^/]+)$")) or id)
				end
			end
		end
		for k, list in pairs(byKey) do
			if #list > 1 then msgs[#msgs + 1] = k .. " is used twice: " .. table.concat(list, ", ") end
			if GAME[k] then msgs[#msgs + 1] = k .. " is also the game's key for " .. GAME[k] .. " (" .. table.concat(list, ", ") .. ")" end
		end
		if #msgs == 0 then win:Notify("No key clashes found", 3) else win:Notify(table.concat(msgs, "  |  "), 8) end
	end })
	tSet:Button({ Name = "Copy diagnostics (send me this when something breaks)", Callback = function()
		-- env and getgenv() or _G
		local L = {}
		local function add(s) L[#L + 1] = s end
		add("Scrdsx " .. tostring(env.ScrdsxVersion) .. " (" .. tostring(env.ScrdsxCommit) .. ")")
		local okE, ex = pcall(function() return identifyexecutor and table.concat({ identifyexecutor() }, " ") end)
		add("executor: " .. tostring(okE and ex or "unknown"))
		local caps = {}
		for _, n in ipairs({ "getgc", "writefile", "readfile", "isfile", "getcustomasset", "gethui", "setclipboard", "getconnections", "firesignal", "hookfunction", "hookmetamethod", "request", "mousemoverel" }) do
			local ok2, v = pcall(function() return loadstring("return " .. n)() end)
			caps[#caps + 1] = n .. "=" .. tostring(ok2 and v ~= nil)
		end
		add("functions: " .. table.concat(caps, " "))
		add(("streaming=%s place=%s players=%d fps=%d"):format(tostring(workspace.StreamingEnabled), tostring(game.PlaceId), #game:GetService("Players"):GetPlayers(), math.floor(1 / math.max(game:GetService("RunService").RenderStepped:Wait(), 0.001))))
			add("status: drive=" .. tostring(NPC.Info) .. " | aim=" .. tostring(Aim.Info) .. " | esp=" .. tostring(ESP.Info) .. " | visuals=" .. tostring(Visuals.Info) .. " | crosshair=" .. tostring(Crosshair.Info) .. " | skins=" .. tostring(Skins.Info) .. " | stamina=" .. tostring(Player.Info))
		add("start errors: " .. (#ctx.startErrors == 0 and "none" or table.concat(ctx.startErrors, " ; ")))
		local txt = table.concat(L, "\n")
		pcall(function() setclipboard(txt) end)
		pcall(function() writefile("scrdsx_diagnostics.txt", txt) end)
		win:Notify("Diagnostics copied (and saved to scrdsx_diagnostics.txt)", 4)
	end })
	tSet:Section("Keys")
	tSet:Label({ Name = "Toggle UI", Value = "RightShift" })
	tSet:Label({ Name = "Search (menu open)", Value = "/" })


	tSet:Section("About")
	tSet:Label({ Name = "Version", Value = tostring(env.ScrdsxVersion or "?") .. " (" .. tostring(env.ScrdsxCommit or "?") .. ")" })
	tSet:Button({ Name = "Update now (reload latest)", Callback = function()
		if not env.ScrdsxReload then win:Notify("Reload not available"); return end
		local reload = env.ScrdsxReload
		ctx.unload()
		task.spawn(reload)
	end })
	tSet:Button({ Name = "Unload", Callback = function() ctx.unload() end })


	local function afterLoad()
		if smartT:Get() then FPS.SetTerrain(true); FPS.SetLighting(true) end

	end

	return { applyTheme = applyTheme, afterLoad = afterLoad }
end
