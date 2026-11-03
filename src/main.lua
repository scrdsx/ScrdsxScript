local UIS = game:GetService("UserInputService")
local UI = __import("ui")
local Loading = __import("loading")
local Vehicle = __import("vehicle")
local Fly = __import("fly")
local Player = __import("player")
local Anti = __import("anticrash")
local AntiFlat = __import("antiflat")

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

-- Settings tab
local tSet = win:Tab("Settings")
tSet:Slider({ Name = "UI scale", Min = 0.7, Max = 1.4, Step = 0.05, Default = 1, Callback = function(v) win:SetScale(v) end })
tSet:Label({ Name = "Toggle UI", Value = "RightShift" })
tSet:Label({ Name = "Focus search", Value = "/" })

local env = getgenv and getgenv() or _G
local alive = true
local function unload()
	alive = false
	Vehicle.Changed = nil
	Vehicle.Destroy()
	Fly.Destroy()
	Player.Changed = nil
	Player.Destroy()
	Anti.Destroy()
	AntiFlat.Destroy()
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

table.insert(win.conns, UIS.InputBegan:Connect(function(i, gp)
	if i.KeyCode == Enum.KeyCode.RightShift then
		win:Toggle()
	elseif not gp and i.KeyCode == Enum.KeyCode.Slash then
		win.searchBox:CaptureFocus()
		task.defer(function() win.searchBox.Text = "" end)
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
