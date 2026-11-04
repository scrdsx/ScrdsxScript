local UIS = game:GetService("UserInputService")
local UI = __import("ui")
local Loading = __import("loading")
local Vehicle = __import("vehicle")
local Fly = __import("fly")
local Player = __import("player")
local Anti = __import("anticrash")
local AntiFlat = __import("antiflat")
local Speed = __import("speed")
local Tele = __import("teleport")
local Hud = __import("hud")
local Config = __import("config")

local TITLE = "Scrdsx Solutions"
local SUBTITLE = "Script  v" .. tostring((getgenv and getgenv() or _G).ScrdsxVersion or "?") -- TODO: set the script name
print("[Scrdsx] running " .. SUBTITLE)

-- re-run safe: tear down a previous instance
if getgenv then
	local g = getgenv()
	if g.__ScrdsxScript then pcall(g.__ScrdsxScript) end
end

Loading.run(TITLE, SUBTITLE)

local win = UI.new({ Title = TITLE, Subtitle = SUBTITLE })

-- Vehicle Mods tab
local tVeh = win:Tab("Vehicle Mods")
local lCar = tVeh:Label({ Name = "Car", Value = Vehicle.Info })
local mSusp = tVeh:Module({ Name = "Suspension", Default = false, Callback = function(on) Vehicle.SetEnabled(on) end })
mSusp:Slider({ Name = "Height", Min = 0, Max = Vehicle.MaxHeight, Step = 0.5, Default = 0, Suffix = " st", Callback = function(v) Vehicle.SetHeight(v) end })
mSusp:Toggle({ Name = "Set game's suspensionHeight", Default = true, Callback = function(v) Vehicle.UseAttribute = v end })
mSusp:Toggle({ Name = "Also raise springs", Default = false, Callback = function(v) Vehicle.UseSprings = v end })
Vehicle.Changed = function() lCar:Set(Vehicle.Info) end
Vehicle.Start()

local mAnti = tVeh:Module({ Name = "Anti Crash Damage", Default = false, Callback = function(on)
	if not Anti.SetEnabled(on) then
		mAnti:Set(false, true)
		win:Notify("Anti Crash: " .. Anti.Info)
	end
end })
local lAntiState = mAnti:Label({ Name = "Status", Value = Anti.Info })
local lAntiBlocked = mAnti:Label({ Name = "Crash reports blocked", Value = 0 })
local lAntiLast = mAnti:Label({ Name = "Last impact value", Value = "-" })
mAnti:Slider({ Name = "Block impacts above", Min = 1, Max = 2000, Step = 1, Default = Anti.MinImpact, Callback = function(v) Anti.MinImpact = v end })
Anti.Changed = function()
	lAntiState:Set(Anti.Info); lAntiBlocked:Set(Anti.Blocked); lAntiLast:Set(Anti.Last)
end

local mSpeed = tVeh:Module({ Name = "Speed", Default = false, Callback = function(on) Speed.SetEnabled(on) end })
local lSpeed = mSpeed:Label({ Name = "Status", Value = Speed.Info })
mSpeed:Slider({ Name = "Engine level", Min = 0, Max = 6, Step = 1, Default = 0, Callback = function(v) Speed.Engine = v end })
mSpeed:Slider({ Name = "Brakes level", Min = 0, Max = 6, Step = 1, Default = 0, Callback = function(v) Speed.Brakes = v end })
mSpeed:Slider({ Name = "Armor level", Min = 0, Max = 6, Step = 1, Default = 0, Callback = function(v) Speed.Armor = v end })
mSpeed:Slider({ Name = "Acceleration multiplier", Min = 1, Max = 10, Step = 0.5, Default = 1, Suffix = "x", Callback = function(v) Speed.AccelMult = v end })
mSpeed:Slider({ Name = "Top speed multiplier", Min = 1, Max = 5, Step = 0.25, Default = 1, Suffix = "x", Callback = function(v) Speed.TopMult = v end })
Speed.Changed = function() lSpeed:Set(Speed.Info) end
Speed.Start()

local mFlat = tVeh:Module({ Name = "Anti Flat Tires", Default = false, Callback = function(on) AntiFlat.SetEnabled(on) end })
local lFlatState = mFlat:Label({ Name = "Status", Value = AntiFlat.Info })
local lFlatBlocked = mFlat:Label({ Name = "Hit reports blocked", Value = 0 })
mFlat:Toggle({ Name = "Block blockade hit reports", Default = AntiFlat.BlockReports, Callback = function(v) AntiFlat.BlockReports = v; AntiFlat.Refresh() end })
mFlat:Toggle({ Name = "No touch on blockade parts", Default = AntiFlat.NoTouch, Callback = function(v) AntiFlat.NoTouch = v; AntiFlat.Refresh() end })
mFlat:Toggle({ Name = "Ghost spike strips (no collision)", Default = AntiFlat.GhostSpikes, Callback = function(v) AntiFlat.GhostSpikes = v; AntiFlat.Refresh() end })
AntiFlat.Changed = function() lFlatState:Set(AntiFlat.Info); lFlatBlocked:Set(AntiFlat.Blocked) end

local mFly = tVeh:Module({ Name = "Vehicle Fly", Default = false, Callback = function(on)
	Fly.SetEnabled(on)
	win:Notify(on and "Vehicle fly on (W/S/A/D, Space up, Ctrl down, Shift boost)" or "Vehicle fly off")
end })
local flyKey = mFly:Keybind({ Name = "Toggle key", Default = Enum.KeyCode.F })
mFly:Slider({ Name = "Speed", Min = 10, Max = 400, Step = 5, Default = Fly.Speed, Suffix = " st/s", Callback = function(v) Fly.Speed = v end })
mFly:Slider({ Name = "Vertical speed", Min = 10, Max = 300, Step = 5, Default = Fly.VSpeed, Suffix = " st/s", Callback = function(v) Fly.VSpeed = v end })
mFly:Slider({ Name = "Boost multiplier (Shift)", Min = 1, Max = 5, Step = 0.25, Default = Fly.Boost, Suffix = "x", Callback = function(v) Fly.Boost = v end })
mFly:Slider({ Name = "Acceleration", Min = 0.05, Max = 1, Step = 0.05, Default = Fly.Accel, Callback = function(v) Fly.Accel = v end })
mFly:Toggle({ Name = "Face the camera (aircraft style)", Default = Fly.FaceCamera, Callback = function(v) Fly.FaceCamera = v end })
mFly:Toggle({ Name = "Pitch nose with camera", Default = Fly.Tilt, Callback = function(v) Fly.Tilt = v end })
mFly:Slider({ Name = "Turn smoothing", Min = 0.05, Max = 1, Step = 0.05, Default = Fly.TurnSmooth, Callback = function(v) Fly.TurnSmooth = v end })
mFly:Toggle({ Name = "Car-style steering (A/D turn)", Default = Fly.SteerMode, Callback = function(v) Fly.SteerMode = v end })
mFly:Slider({ Name = "Turn speed", Min = 0.5, Max = 6, Step = 0.25, Default = Fly.TurnSpeed, Suffix = " rad/s", Callback = function(v) Fly.TurnSpeed = v end })
mFly:Toggle({ Name = "Reverse heading (if W goes backwards)", Default = Fly.ReverseHeading, Callback = function(v) Fly.ReverseHeading = v end })
mFly:Toggle({ Name = "Stabilize (no spin)", Default = Fly.Stabilize, Callback = function(v) Fly.Stabilize = v end })
Fly.Start()

-- Player tab
local tPlayer = win:Tab("Player")
local mStam = tPlayer:Module({ Name = "Inf Stamina", Default = false, Callback = function(on) Player.SetInfStamina(on) end })
local lStam = mStam:Label({ Name = "Status", Value = Player.Info })
Player.Changed = function() lStam:Set(Player.Info) end
Player.Start()

-- Teleports tab
local tTele = win:Tab("Teleports")
local lTele = tTele:Label({ Name = "Status", Value = Tele.Info })
Tele.Notify = function(m) win:Notify(m) end
Tele.Changed = function() lTele:Set(Tele.Info) end
tTele:Button({ Name = "Go to my vehicle (get in)", Callback = function() Tele.GoToCar() end })
tTele:Toggle({ Name = "Get in my car first", Default = Tele.GetIn, Callback = function(v) Tele.GetIn = v end })
tTele:Toggle({ Name = "Face the location when I arrive", Default = Tele.Face, Callback = function(v) Tele.Face = v end })
tTele:Toggle({ Name = "Hide the trip from other players (risky)", Default = Tele.Stealth, Callback = function(v) Tele.Stealth = v end })
tTele:Toggle({ Name = "Phase through objects while travelling", Default = Tele.Ghost, Callback = function(v) Tele.Ghost = v end })
tTele:Slider({ Name = "Travel speed", Min = 100, Max = 3000, Step = 50, Default = Tele.Speed, Suffix = " st/s", Callback = function(v) Tele.Speed = v end })
tTele:Slider({ Name = "Cruise height", Min = 10, Max = 200, Step = 5, Default = Tele.Height, Suffix = " st", Callback = function(v) Tele.Height = v end })
tTele:Button({ Name = "Cancel teleport", Callback = function() Tele.Stop() end })
local shownLoc = {}
local function addLocations(list)
	for _, loc in ipairs(list) do
		if not shownLoc[loc.name] then
			shownLoc[loc.name] = true
			tTele:Button({ Name = loc.name, Callback = function() Tele.GoTo(loc) end })
		end
	end
	Tele.Info = #list .. " locations" .. (#(Tele.Missing or {}) > 0 and (" | not loaded yet: " .. table.concat(Tele.Missing, ", ")) or "")
	lTele:Set(Tele.Info)
end
tTele:Button({ Name = "Rescan locations", Callback = function() Tele.Scan(addLocations) end })
tTele:Button({ Name = "Save my position as a spot", Callback = function()
	local loc = Tele.SaveHere()
	if loc then addLocations({ loc }) end
end })
Tele.Scan(addLocations)

-- HUD tab: widgets that stay on screen; press / (window closed) to move them
local hud = Hud.new({
	Title = TITLE,
	Version = (getgenv and getgenv() or _G).ScrdsxVersion,
	GetLocations = function() return Tele.Locations end,
	GetModules = function()
		local list = {}
		for name, m in pairs({ ["Suspension"] = mSusp, ["Anti Crash Damage"] = mAnti, ["Speed"] = mSpeed, ["Anti Flat Tires"] = mFlat,
			["Vehicle Fly"] = mFly, ["Inf Stamina"] = mStam }) do
			if m:Get() then list[#list + 1] = name end
		end
		return list
	end,
})
local tHud = win:Tab("HUD")
tHud:Toggle({ Name = "Watermark", Default = hud:IsOn("watermark"), Callback = function(v) hud:SetWidget("watermark", v) end })
tHud:Toggle({ Name = "Player info (health, position, nearest spot)", Default = hud:IsOn("info"), Callback = function(v) hud:SetWidget("info", v) end })
tHud:Toggle({ Name = "Vehicle (speed, fuel, health, tires)", Default = hud:IsOn("vehicle"), Callback = function(v) hud:SetWidget("vehicle", v) end })
tHud:Toggle({ Name = "Active modules list", Default = hud:IsOn("modules"), Callback = function(v) hud:SetWidget("modules", v) end })
tHud:Slider({ Name = "HUD size", Min = 0.6, Max = 1.6, Step = 0.05, Default = hud.scale, Callback = function(v) hud:SetScale(v) end })
tHud:Button({ Name = "Move HUD (closes this window; press / when done)", Callback = function()
	win:SetVisible(false)
	hud:SetEdit(true)
end })
tHud:Button({ Name = "Reset HUD positions", Callback = function() hud:ResetPositions() end })
hud.EditChanged = function(on)
	if not on and not win.visible then win:Notify("HUD saved. RightShift opens the menu") end
end

-- Configs tab: everything you change (modules on/off, sliders, keybinds, HUD layout) is saved and loaded again next time
local tCfg = win:Tab("Configs")
local current = Config.GetAutoload() or "default"
local lCurrent = tCfg:Label({ Name = "Current config", Value = current })
local autosave, newName, lastSnap = true, "", nil
local cfgButtons = {}

local function snapshot() return { v = 1, flags = win:GetConfig(), hud = hud:GetLayout() } end
local function deepEq(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, v in pairs(a) do if not deepEq(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end
local function saveCurrent(force)
	if not Config.Available then return end
	local s = snapshot()
	if force or not lastSnap or not deepEq(s, lastSnap) then
		if Config.Write(current, s) then lastSnap = s end
	end
end
local function applyConfig(name)
	local data = Config.Read(name)
	if not data then win:Notify("Could not read config: " .. name); return false end
	win:ApplyConfig(data.flags or {})
	if data.hud then hud:SetLayout(data.hud) end
	current = name
	lCurrent:Set(name)
	Config.SetAutoload(name)
	lastSnap = snapshot()
	return true
end
local refreshList
function refreshList()
	for _, b in ipairs(cfgButtons) do b:Destroy() end
	cfgButtons = {}
	for i, n in ipairs(Config.List()) do
		cfgButtons[#cfgButtons + 1] = tCfg:Button({ Name = (n == current and "●  " or "") .. "Load: " .. n, Order = 100 + i, Callback = function()
			saveCurrent(true) -- keep the one you are leaving up to date
			if applyConfig(n) then win:Notify("Loaded config: " .. n); refreshList() end
		end })
	end
end

if Config.Available then
	tCfg:TextBox({ Name = "New config name", Placeholder = "e.g. cars", Callback = function(t) newName = t end })
	tCfg:Button({ Name = "Create config from current settings", Callback = function()
		local name = Config.Clean(newName)
		if name == "" then win:Notify("Type a config name first"); return end
		saveCurrent(true)
		current = name
		lCurrent:Set(name)
		Config.SetAutoload(name)
		saveCurrent(true)
		refreshList()
		win:Notify("Created config: " .. name)
	end })
	tCfg:Button({ Name = "Save current config now", Callback = function() saveCurrent(true); win:Notify("Saved: " .. current) end })
	tCfg:Button({ Name = "Delete current config", Callback = function()
		local gone = current
		Config.Delete(gone)
		current = "default"
		lCurrent:Set(current)
		Config.SetAutoload(current)
		lastSnap = nil
		saveCurrent(true)
		refreshList()
		win:Notify("Deleted: " .. gone .. "  (now on 'default')")
	end })
	tCfg:Toggle({ Name = "Autosave every 5 seconds", Default = true, NoSave = true, Callback = function(v) autosave = v end })
else
	tCfg:Label({ Name = "Configs", Value = "executor has no file functions" })
end

-- Settings tab
local tSet = win:Tab("Settings")
tSet:Slider({ Name = "UI scale", Min = 0.7, Max = 1.4, Step = 0.05, Default = 1, Callback = function(v) win:SetScale(v) end })
tSet:Label({ Name = "Toggle UI", Value = "RightShift" })
tSet:Label({ Name = "Search (menu open)", Value = "/" })
tSet:Label({ Name = "Move HUD (menu closed)", Value = "/" })

local env = getgenv and getgenv() or _G
local alive = true
local function unload()
	pcall(saveCurrent, true)
	alive = false
	Vehicle.Changed = nil
	Vehicle.Destroy()
	Fly.Destroy()
	Player.Changed = nil
	Player.Destroy()
	Anti.Destroy()
	AntiFlat.Destroy()
	Speed.Destroy()
	Tele.Notify, Tele.Changed = nil, nil
	hud.EditChanged = nil
	hud:Destroy()
	win:Destroy()
	if getgenv then getgenv().__ScrdsxScript = nil end
end
tSet:Label({ Name = "Version", Value = tostring(env.ScrdsxVersion or "?") .. " (" .. tostring(env.ScrdsxCommit or "?") .. ")" })
tSet:Button({ Name = "Update now (reload latest)", Callback = function()
	if not env.ScrdsxReload then win:Notify("Reload not available"); return end
	local reload = env.ScrdsxReload
	unload()
	task.spawn(reload)
end })
tSet:Button({ Name = "Unload", Callback = unload })
if getgenv then getgenv().__ScrdsxScript = unload end

-- load the config you used last time (or start 'default'), then keep it saved
if Config.Available then
	if Config.Exists(current) then
		applyConfig(current)
	else
		saveCurrent(true)
		Config.SetAutoload(current)
	end
	refreshList()
	task.spawn(function()
		while alive do
			task.wait(5)
			if autosave then pcall(saveCurrent) end
		end
	end)
end

table.insert(win.conns, UIS.InputBegan:Connect(function(i, gp)
	if i.KeyCode == Enum.KeyCode.RightShift then
		if hud.editing then hud:SetEdit(false) end
		win:Toggle()
	elseif i.KeyCode == Enum.KeyCode.Slash then
		if win.visible then
			if not gp then -- menu open: search (chat uses / too, so not while typing)
				win.searchBox:CaptureFocus()
				task.defer(function() win.searchBox.Text = "" end)
			end
		elseif hud.editing or not gp then -- menu closed: start / stop moving the HUD
			hud:ToggleEdit()
		end
	end
end))

-- fly toggle key (not while typing or while the key box is waiting for a key)
table.insert(win.conns, UIS.InputBegan:Connect(function(i, gp)
	if gp or i.UserInputType ~= Enum.UserInputType.Keyboard or flyKey:IsListening() then return end
	if flyKey:Get() == i.KeyCode then mFly:Set(not mFly:Get()) end
end))

win:Notify(TITLE .. " loaded  v" .. tostring(env.ScrdsxVersion or "?"))

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
