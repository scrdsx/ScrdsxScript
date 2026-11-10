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
local Farm = __import("farm")
local Drive = __import("autodrive")
local ESP = __import("esp")
local Aim = __import("aim")
local Extras = __import("extras")

local TITLE = "Scrdsx Solutions"
local SUBTITLE = "Script  v" .. tostring((getgenv and getgenv() or _G).ScrdsxVersion or "?") -- TODO: set the script name
print("[Scrdsx] running " .. SUBTITLE)

-- a module that fails to start must not take the whole script down: every Start() goes through safe()
local startErrors = {}
local function safe(name, f)
	local ok, err = pcall(f)
	if not ok then
		startErrors[#startErrors + 1] = name .. ": " .. tostring(err)
		warn("[Scrdsx] " .. name .. " failed to start: " .. tostring(err))
	end
end

-- re-run safe: tear down a previous instance
if getgenv then
	local g = getgenv()
	if g.__ScrdsxScript then pcall(g.__ScrdsxScript) end
end

Loading.run(TITLE, SUBTITLE)

local win = UI.new({ Title = TITLE, Subtitle = SUBTITLE })

-- Vehicle Mods tab
local tVeh = win:Tab("Vehicle Mods", { Section = "Game", Icon = 1 })
local lCar = tVeh:Label({ Name = "Car", Value = Vehicle.Info })
local mSusp = tVeh:Module({ Name = "Suspension", Default = false, Callback = function(on) Vehicle.SetEnabled(on) end })
mSusp:Slider({ Name = "Height", Min = 0, Max = Vehicle.MaxHeight, Step = 0.5, Default = 0, Suffix = " st", Callback = function(v) Vehicle.SetHeight(v) end })
mSusp:Toggle({ Name = "Set game's suspensionHeight", Default = true, Callback = function(v) Vehicle.UseAttribute = v end })
mSusp:Toggle({ Name = "Also raise springs", Default = false, Callback = function(v) Vehicle.UseSprings = v end })
Vehicle.Changed = function() lCar:Set(Vehicle.Info) end
safe("vehicle", Vehicle.Start)

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
safe("speed", Speed.Start)

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
mFly:Section("Controls")
local flyKey = mFly:Keybind({ Name = "Toggle key", Default = Enum.KeyCode.F })
mFly:Section("Speed")
mFly:Slider({ Name = "Speed", Min = 10, Max = 400, Step = 5, Default = Fly.Speed, Suffix = " st/s", Callback = function(v) Fly.Speed = v end })
mFly:Slider({ Name = "Vertical speed", Min = 10, Max = 300, Step = 5, Default = Fly.VSpeed, Suffix = " st/s", Callback = function(v) Fly.VSpeed = v end })
mFly:Slider({ Name = "Boost multiplier (Shift)", Min = 1, Max = 5, Step = 0.25, Default = Fly.Boost, Suffix = "x", Callback = function(v) Fly.Boost = v end })
mFly:Slider({ Name = "Acceleration", Min = 0.05, Max = 1, Step = 0.05, Default = Fly.Accel, Callback = function(v) Fly.Accel = v end })
mFly:Section("Steering")
mFly:Toggle({ Name = "Face the camera (aircraft style)", Default = Fly.FaceCamera, Callback = function(v) Fly.FaceCamera = v end })
mFly:Toggle({ Name = "Pitch nose with camera", Default = Fly.Tilt, Callback = function(v) Fly.Tilt = v end })
mFly:Slider({ Name = "Turn smoothing", Min = 0.05, Max = 1, Step = 0.05, Default = Fly.TurnSmooth, Callback = function(v) Fly.TurnSmooth = v end })
mFly:Toggle({ Name = "Car-style steering (A/D turn)", Default = Fly.SteerMode, Callback = function(v) Fly.SteerMode = v end })
mFly:Slider({ Name = "Turn speed", Min = 0.5, Max = 6, Step = 0.25, Default = Fly.TurnSpeed, Suffix = " rad/s", Callback = function(v) Fly.TurnSpeed = v end })
mFly:Toggle({ Name = "Reverse heading (if W goes backwards)", Default = Fly.ReverseHeading, Callback = function(v) Fly.ReverseHeading = v end })
mFly:Toggle({ Name = "Stabilize (no spin)", Default = Fly.Stabilize, Callback = function(v) Fly.Stabilize = v end })
safe("fly", Fly.Start)

-- Player tab
local tPlayer = win:Tab("Player", { Icon = 2 })
local mStam = tPlayer:Module({ Name = "Inf Stamina", Default = false, Callback = function(on) Player.SetInfStamina(on) end })
local lStam = mStam:Label({ Name = "Status", Value = Player.Info })
Player.Changed = function() lStam:Set(Player.Info) end
safe("player", Player.Start)

-- ESP tab
local tEsp = win:Tab("ESP", { Section = "Game", Icon = 3 })
local mEsp = tEsp:Module({ Name = "Player ESP", Default = false, Callback = function(on) ESP.SetEnabled(on) end })
mEsp:Section("Shapes")
mEsp:Toggle({ Name = "Box", Default = ESP.Boxes, Callback = function(v) ESP.Boxes = v end })
mEsp:Toggle({ Name = "Corner box style (off = full outline)", Default = ESP.CornerBox, Callback = function(v) ESP.CornerBox = v end })
mEsp:Toggle({ Name = "Skeleton", Default = ESP.Skeleton, Callback = function(v) ESP.Skeleton = v end })
mEsp:Toggle({ Name = "Tracers", Default = ESP.Tracers, Callback = function(v) ESP.Tracers = v end })
mEsp:Section("Info")
mEsp:Toggle({ Name = "Name + role (police blue, fire red)", Default = ESP.Names, Callback = function(v) ESP.Names = v end })
mEsp:Toggle({ Name = "Health bar", Default = ESP.Health, Callback = function(v) ESP.Health = v end })
mEsp:Toggle({ Name = "Distance", Default = ESP.Distance, Callback = function(v) ESP.Distance = v end })
mEsp:Toggle({ Name = "Wanted tag (red)", Default = ESP.Wanted, Callback = function(v) ESP.Wanted = v end })
mEsp:Toggle({ Name = "Hover card (point at a player)", Default = ESP.Hover, Callback = function(v) ESP.Hover = v end })
mEsp:Section("Range")
mEsp:Slider({ Name = "Max distance", Min = 100, Max = 3000, Step = 50, Default = ESP.MaxDist, Suffix = " st", Callback = function(v) ESP.MaxDist = v end })
mEsp:Toggle({ Name = "Fade with distance", Default = ESP.Fade, Callback = function(v) ESP.Fade = v end })
mEsp:Section("Who to show")
mEsp:Toggle({ Name = "Show police", Default = true, Callback = function(v) ESP.Teams.Police = v end })
mEsp:Toggle({ Name = "Show fire department", Default = true, Callback = function(v) ESP.Teams.FireDepartment = v end })
mEsp:Toggle({ Name = "Show citizens", Default = true, Callback = function(v) ESP.Teams.Citizen = v end })
mEsp:Toggle({ Name = "Show other jobs / prisoners", Default = true, Callback = function(v) ESP.Teams.Other = v end })
local mRadar = tEsp:Module({ Name = "Police radar (escape helper)", Default = true, Callback = function(on) ESP.Radar = on end })
mRadar:Slider({ Name = "Warn within", Min = 100, Max = 800, Step = 25, Default = ESP.RadarDist, Suffix = " st", Callback = function(v) ESP.RadarDist = v end })
ESP.OnPolice = function(d) win:Notify(("Police nearby: %d studs"):format(d), 4) end
safe("esp", ESP.Start)

-- Aim tab
local tAim = win:Tab("Aim", { Section = "Game", Icon = 4 })
local mAim = tAim:Module({ Name = "Camlock", Default = false, Callback = function(on) Aim.SetEnabled(on) end })
local lAim = mAim:Label({ Name = "Status", Value = Aim.Info })
Aim.Changed = function() lAim:Set(Aim.Info) end
mAim:Section("Activation")
local aimKey = mAim:Keybind({ Name = "Aim key", Default = Enum.KeyCode.Z })
mAim:Toggle({ Name = "Hold the key (off = press to toggle)", Default = Aim.Hold, Callback = function(v) Aim.Hold = v; Aim.Active = false end })
mAim:Toggle({ Name = "Mouse lock (cursor stays in the centre while aiming)", Default = Aim.MouseLock, Callback = function(v) Aim.MouseLock = v end })
mAim:Section("Targeting")
mAim:Toggle({ Name = "Aim at the head (off = body)", Default = true, Callback = function(v) Aim.Part = v and "Head" or "Torso" end })
mAim:Slider({ Name = "Field of view", Min = 40, Max = 600, Step = 10, Default = Aim.FOV, Suffix = " px", Callback = function(v) Aim.FOV = v end })
mAim:Slider({ Name = "Smoothness (low = slow glide, 1 = snap)", Min = 0.05, Max = 1, Step = 0.05, Default = Aim.Smooth, Callback = function(v) Aim.Smooth = v end })
mAim:Slider({ Name = "Range", Min = 50, Max = 1500, Step = 25, Default = Aim.MaxDist, Suffix = " st", Callback = function(v) Aim.MaxDist = v end })
mAim:Slider({ Name = "Predict movement", Min = 0, Max = 0.4, Step = 0.01, Default = Aim.Prediction, Suffix = " s", Callback = function(v) Aim.Prediction = v end })
mAim:Section("Rules")
mAim:Toggle({ Name = "Only players I can see (wall check)", Default = Aim.WallCheck, Callback = function(v) Aim.WallCheck = v end })
mAim:Toggle({ Name = "Stay on the first target while held", Default = Aim.Sticky, Callback = function(v) Aim.Sticky = v end })
mAim:Toggle({ Name = "Wanted players only", Default = Aim.WantedOnly, Callback = function(v) Aim.WantedOnly = v end })
mAim:Section("Teams")
mAim:Toggle({ Name = "Target police", Default = true, Callback = function(v) Aim.Teams.Police = v end })
mAim:Toggle({ Name = "Target fire department", Default = true, Callback = function(v) Aim.Teams.FireDepartment = v end })
mAim:Toggle({ Name = "Target citizens", Default = true, Callback = function(v) Aim.Teams.Citizen = v end })
mAim:Toggle({ Name = "Target other jobs / prisoners", Default = true, Callback = function(v) Aim.Teams.Other = v end })
mAim:Section("Display")
mAim:Toggle({ Name = "Show field of view circle", Default = Aim.ShowFOV, Callback = function(v) Aim.ShowFOV = v end })
local lastLockMsg = 0
Aim.OnTarget = function(plr)
	if os.clock() - lastLockMsg < 0.8 then return end
	lastLockMsg = os.clock()
	if plr then
		local ch = plr.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		local myChar = game:GetService("Players").LocalPlayer.Character
		local me = myChar and myChar:FindFirstChild("HumanoidRootPart")
		local role = ESP.RoleOf(plr)
		local d = (hrp and me) and (" - %d st"):format((hrp.Position - me.Position).Magnitude) or ""
		win:Notify(("Locked on: %s (@%s, %s)%s"):format(plr.DisplayName, plr.Name, role, d), 2.5)
	else
		win:Notify("Camlock: no target", 1.5)
	end
end
safe("aim", Aim.Start)

-- World tab: client-side helpers (lighting, camera, movement)
local tWorld = win:Tab("World", { Section = "Game", Icon = 3 })
tWorld:Section("Lighting")
tWorld:Toggle({ Name = "Fullbright (no darkness)", Default = false, Callback = function(v) Extras.Fullbright = v; Extras.Refresh() end })
tWorld:Toggle({ Name = "No fog", Default = false, Callback = function(v) Extras.NoFog = v; Extras.Refresh() end })
tWorld:Toggle({ Name = "Lock the time of day", Default = false, Callback = function(v) Extras.LockTime = v; Extras.Refresh() end })
tWorld:Slider({ Name = "Time of day", Min = 0, Max = 24, Step = 0.5, Default = Extras.Time, Suffix = " h", Callback = function(v) Extras.Time = v end })
tWorld:Section("Camera")
tWorld:Toggle({ Name = "Custom field of view", Default = false, Callback = function(v) Extras.FovOn = v end })
tWorld:Slider({ Name = "Field of view", Min = 40, Max = 120, Step = 1, Default = Extras.Fov, Callback = function(v) Extras.Fov = v end })
tWorld:Toggle({ Name = "Unlimited camera zoom", Default = false, Callback = function(v) Extras.Zoom = v end })
tWorld:Section("Movement (risky: the server may notice)")
tWorld:Toggle({ Name = "Infinite jump", Default = false, Callback = function(v) Extras.InfJump = v end })
tWorld:Toggle({ Name = "Noclip (walk through walls)", Default = false, Callback = function(v) Extras.Noclip = v end })
tWorld:Toggle({ Name = "Custom walk speed", Default = false, Callback = function(v) Extras.SpeedOn = v end })
tWorld:Slider({ Name = "Walk speed", Min = 16, Max = 80, Step = 1, Default = Extras.Speed, Callback = function(v) Extras.Speed = v end })
tWorld:Section("Utility")
tWorld:Toggle({ Name = "Anti AFK (never kicked for idling)", Default = Extras.AntiAfk, Callback = function(v) Extras.AntiAfk = v end })
safe("extras", Extras.Start)

-- Travel tab: the new teleport system (instant jump first, every move checked, falls back to hops -> walking -> car)
local Travel = __import("travel")
local Escape = __import("escape")
local tTele = win:Tab("Travel", { Icon = 5 })
local lTele = tTele:Label({ Name = "Status", Value = Travel.Info })
Travel.Notify = function(m) win:Notify(m, 3) end
Travel.Changed = function() lTele:Set(Travel.Info) end
Travel.Log = function(m) Farm.Trace("travel: " .. m) end
Tele.Notify = function(m) win:Notify(m) end -- messages from the car fallback
Tele.Changed = function() end
Farm.TravelTo = function(pos, opts) return Travel.ToSync(pos, opts) end
local backKey
tTele:Section("Quick")
tTele:Button({ Name = "Hospital bed (lie down and heal)", Callback = function()
	local ok, why = Farm.GoHospital(true)
	if not ok then win:Notify("Hospital: " .. tostring(why)) end
end })
tTele:Button({ Name = "Back to where I was", Callback = function()
	local ok, why = Travel.Back()
	if not ok then win:Notify("Travel: " .. tostring(why)) end
end })
tTele:Button({ Name = "Get into my car", Callback = function() Tele.GoToCar() end })
tTele:Button({ Name = "Cancel", Callback = function() Travel.Stop(); Tele.Stop() end })
backKey = tTele:Keybind({ Name = "Back key", Default = Enum.KeyCode.B })
tTele:Section("How it travels")
tTele:Toggle({ Name = "Allow my car as the last fallback", Default = Travel.AllowCar, Callback = function(v) Travel.AllowCar = v end })
tTele:Toggle({ Name = "Phase through objects while hopping", Default = Travel.Ghost, Callback = function(v) Travel.Ghost = v end })
tTele:Slider({ Name = "Hop length (shrinks by itself when refused)", Min = 20, Max = 400, Step = 10, Default = Travel.HopLen, Suffix = " st", Callback = function(v) Travel.HopLen = v end })
tTele:Slider({ Name = "Hop delay", Min = 0.05, Max = 0.4, Step = 0.01, Default = Travel.HopDelay, Suffix = " s", Callback = function(v) Travel.HopDelay = v end })
tTele:Section("Places")
local shownLoc = {}
local function goTo(loc) Travel.To(loc.pos, { name = loc.name, face = loc.pos }) end
local function addLocations(list)
	for _, loc in ipairs(list) do
		if not shownLoc[loc.name] then
			shownLoc[loc.name] = true
			tTele:Button({ Name = loc.name, Callback = function() goTo(loc) end })
		end
	end
	lTele:Set(#list .. " places" .. (#(Tele.Missing or {}) > 0 and (" | not loaded yet: " .. table.concat(Tele.Missing, ", ")) or ""))
end
tTele:Button({ Name = "Rescan places", Callback = function() Tele.Scan(addLocations) end })
tTele:Button({ Name = "Save my position as a spot", Callback = function()
	local loc = Tele.SaveHere()
	if loc then addLocations({ loc }) end
end })
tTele:Section("Players")
local playerBtns = {}
local function refreshPlayers()
	for _, b in ipairs(playerBtns) do pcall(function() b.Destroy() end) end
	playerBtns = {}
	for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
		if p ~= game:GetService("Players").LocalPlayer then
			playerBtns[#playerBtns + 1] = tTele:Button({ Name = "To " .. p.DisplayName .. " (@" .. p.Name .. ")", Callback = function()
				local ok, why = Travel.ToPlayer(p)
				if not ok then win:Notify("Travel: " .. tostring(why)) end
			end })
		end
	end
end
tTele:Button({ Name = "Refresh the player list", Callback = refreshPlayers })
refreshPlayers()
Tele.Scan(addLocations)

-- Hospital: after every death, lie down in a bed (waits for the respawn)
local mHosp
mHosp = tTele:Module({ Name = "Auto revive at the hospital", Default = false, NoSave = true, Callback = function(on)
	Farm.AutoRevive = on
	win:Notify(on and "Auto revive on: after you die it goes to a hospital bed" or "Auto revive off", 3)
end })
mHosp:Label({ Name = "What it does", Value = "after a death: respawn, travel, lie down" })
local hospKey = mHosp:Keybind({ Name = "Go to a hospital bed now", Default = Enum.KeyCode.J })

-- Escape tab: get away from the police (uses the Travel system)
local tEsc = win:Tab("Escape", { Icon = 2 })
local mEsc
mEsc = tEsc:Module({ Name = "Auto escape", Default = false, NoSave = true, Callback = function(on)
	Escape.Auto = on
	win:Notify(on and "Auto escape on: it jumps away when you are wanted and police get close" or "Auto escape off", 3)
end })
local lEsc = mEsc:Label({ Name = "Status", Value = Escape.Info })
Escape.Changed = function() lEsc:Set(Escape.Info) end
Escape.Notify = function(m, sec) win:Notify(m, sec or 3) end
Escape.Log = function(m) Farm.Trace(m) end
mEsc:Section("When it starts")
mEsc:Slider({ Name = "Police distance", Min = 60, Max = 500, Step = 10, Default = Escape.Dist, Suffix = " st", Callback = function(v) Escape.Dist = v end })
mEsc:Toggle({ Name = "Try to break away when I am cuffed (experimental)", Default = false, Callback = function(v) Escape.OnCuff = v end })
mEsc:Section("After the jump")
mEsc:Slider({ Name = "Lay low for", Min = 20, Max = 300, Step = 10, Default = Escape.LayLow, Suffix = " s", Callback = function(v) Escape.LayLow = v end })
mEsc:Toggle({ Name = "Use my saved hideouts first", Default = Escape.SavedFirst, Callback = function(v) Escape.SavedFirst = v end })
tEsc:Section("Now")
local panicKey = tEsc:Keybind({ Name = "Panic key (escape right now)", Default = Enum.KeyCode.X })
tEsc:Button({ Name = "Escape now", Callback = function()
	local ok, why = Escape.Run("button")
	if not ok then win:Notify("Escape: " .. tostring(why)) end
end })
tEsc:Button({ Name = "Save this spot as a hideout", Callback = function()
	local loc = Tele.SaveHere("Hideout")
	if loc then addLocations({ loc }); win:Notify("Saved " .. loc.name) end
end })
tEsc:Button({ Name = "Stop", Callback = function() Escape.Stop() end })
tEsc:Label({ Name = "Police radar", Value = "ESP tab" })
safe("escape", Escape.Start)

-- AutoFarm tab (modules get added here)
local tFarm = win:Tab("AutoFarm", { Section = "Farming", Icon = 6 })
Farm.Tele = Tele
Farm.Notify = function(m) win:Notify(m, 4) end
Farm.Drive = Drive
Drive.Log = function(m) Farm.Trace("drive: " .. m) end
Tele.OnTrace = Farm.Trace
local lFarm = tFarm:Label({ Name = "Status", Value = Farm.Info })
local lFarmStats = tFarm:Label({ Name = "Done", Value = Farm.Stats })
Farm.Changed = function() lFarm:Set(Farm.Info); lFarmStats:Set(Farm.Stats) end
local mFarm
Farm.Stopped = function() if mFarm then mFarm:Set(false, true) end end
mFarm = tFarm:Module({ Name = "Auto Rob", Default = false, NoSave = true, Callback = function(on)
	Farm.SetEnabled(on)
	win:Notify(on and "AutoFarm on" or "AutoFarm stopping...")
end })
local mLoot = tFarm:Module({ Name = "Quick loot (keybind)", Default = true, Callback = function() end })
local lootKey = mLoot:Keybind({ Name = "Loot key (money, gold, items nearby)", Default = Enum.KeyCode.Y })
mLoot:Section("How it collects")
mLoot:Label({ Name = "Default", Value = "all piles in reach, at once" })
mLoot:Toggle({ Name = "Also walk to piles out of reach", Default = false, Callback = function(v) Farm.LootWalk = v end })
mLoot:Slider({ Name = "Walking range", Min = 20, Max = 250, Step = 5, Default = 90, Suffix = " st", Callback = function(v) Farm.LootRange = v end })
Farm.LootRange = Farm.LootRange or 90
mFarm:Section("What to rob")
mFarm:Toggle({ Name = "Cash registers (gas stations, shops)", Default = Farm.Registers, Callback = function(v) Farm.Registers = v end })
mFarm:Toggle({ Name = "Bank (buys a bomb, takes money + gold)", Default = Farm.Bank, Callback = function(v) Farm.Bank = v end })
mFarm:Toggle({ Name = "Jeweler safes (experimental)", Default = Farm.Jeweler, Callback = function(v) Farm.Jeweler = v end })
mFarm:Toggle({ Name = "Club safe (experimental)", Default = Farm.Club, Callback = function(v) Farm.Club = v end })
mFarm:Toggle({ Name = "Sell gold at the dealer after the bank", Default = Farm.SellGold, Callback = function(v) Farm.SellGold = v end })
mFarm:Section("Movement")
mFarm:Toggle({ Name = "Get into the car with the seat interaction (off = direct)", Default = Farm.SitInteract, NoSave = true, Callback = function(v) Farm.SitInteract = v end })
mFarm:Toggle({ Name = "Instant teleport on foot (off = walk)", Default = Farm.InstantMove, NoSave = true, Callback = function(v) Farm.InstantMove = v end })
mFarm:Slider({ Name = "Sell calls", Min = 1, Max = 6, Step = 1, Default = Farm.SellCalls, Callback = function(v) Farm.SellCalls = v end })
mFarm:Slider({ Name = "Travel speed", Min = 80, Max = 600, Step = 20, Default = Farm.TravelSpeed, NoSave = true, Suffix = " st/s", Callback = function(v) Farm.TravelSpeed = v end })
mFarm:Section("Autopilot")
mFarm:Toggle({ Name = "Autopilot: drive the car for real along the roads", Default = Farm.AutoDrive, NoSave = true, Callback = function(v) Farm.AutoDrive = v end })
mFarm:Toggle({ Name = "Honk at cars in front (H)", Default = true, NoSave = true, Callback = function(v) Drive.Honk = v end })
mFarm:Toggle({ Name = "Stop at red lights (slower)", Default = false, NoSave = true, Callback = function(v) Drive.FarmLights = v end })
mFarm:Slider({ Name = "Autopilot speed", Min = 30, Max = 140, Step = 5, Default = Farm.DriveSpeed, Suffix = " st/s", NoSave = true, Callback = function(v) Farm.DriveSpeed = v end })
mFarm:Toggle({ Name = "I drive myself (no automatic trips)", Default = Farm.Manual, NoSave = true, Callback = function(v) Farm.Manual = v end })
tFarm:Button({ Name = "Buy a bomb at the nearest dealer", Callback = function() Farm.Once("buybomb") end })
tFarm:Button({ Name = "Rob nearest cash register now", Callback = function() Farm.Once("registers") end })
tFarm:Button({ Name = "Rob the bank now", Callback = function() Farm.Once("bank") end })
tFarm:Button({ Name = "Rob the jeweler now (experimental)", Callback = function() Farm.Once("jeweler") end })
tFarm:Button({ Name = "Export road map (for training the driving offline)", Callback = function()
	local ok, info = Drive.ExportMap()
	win:Notify(ok and ("Road map saved: " .. tostring(info)) or ("Could not export: " .. tostring(info)))
end })
tFarm:Button({ Name = "Copy farm log (send me this if it fails)", Callback = function() win:Notify(Farm.CopyLog() and "Farm log copied" or "Could not copy; see workspace/farm_log.txt") end })
tFarm:Button({ Name = "Stop AutoFarm", Callback = function() mFarm:Set(false, true); Farm.Stop() end })

-- Auto Drive tab: the car drives itself like an NPC (roam the map, follow a player, park straight)
local NPC = __import("autonpc")
local tNpc = win:Tab("Auto Drive", { Icon = 1 })
local mNpc
mNpc = tNpc:Module({ Name = "Auto Drive", Default = false, NoSave = true, Callback = function(on)
	if on and Farm.Enabled then
		win:Notify("Turn Auto Rob off first")
		mNpc:Set(false, true)
		return
	end
	NPC.SetEnabled(on)
	win:Notify(on and "Auto Drive on: sit in your car" or "Auto Drive off", 2.5)
end })
local lNpc = mNpc:Label({ Name = "Status", Value = NPC.Info })
NPC.Changed = function() lNpc:Set(NPC.Info) end
NPC.Stopped = function() mNpc:Set(false, true) end
mNpc:Section("Mode")
mNpc:Toggle({ Name = "Follow a player (off = roam the map)", Default = false, NoSave = true, Callback = function(v) NPC.Follow = v end })
mNpc:TextBox({ Name = "Player to follow (blank = nearest)", Placeholder = "name", Callback = function(t) NPC.FollowName = t or "" end })
mNpc:Section("Driving")
mNpc:Slider({ Name = "Cruise speed", Min = 25, Max = 70, Step = 5, Default = NPC.Cruise, Suffix = " st/s", Callback = function(v) NPC.Cruise = v end })
mNpc:Toggle({ Name = "Turn signals (Q left, E right)", Default = Drive.Signals ~= false, Callback = function(v) Drive.Signals = v end })
mNpc:Toggle({ Name = "Honk at cars in front (H)", Default = true, Callback = function(v) Drive.Honk = v end })
mNpc:Section("Traffic rules")
mNpc:Toggle({ Name = "Stop at red lights", Default = Drive.RedLights ~= false, Callback = function(v) Drive.RedLights = v end })
mNpc:Toggle({ Name = "Slow down for speed cameras (to the limit)", Default = Drive.CameraSlow ~= false, Callback = function(v) Drive.CameraSlow = v end })
mNpc:Button({ Name = "Copy log (send me this if it drives badly)", Callback = function() win:Notify(Farm.CopyLog() and "Log copied" or "Could not copy; see workspace/farm_log.txt") end })
mNpc:Section("Parking")
local parkKey = mNpc:Keybind({ Name = "Park key (look at the space, press)", Default = Enum.KeyCode.K })
mNpc:Button({ Name = "Park straight at the crosshair now", Callback = function()
	local ok, why = NPC.ParkAtCrosshair()
	if not ok then win:Notify("Parking: " .. tostring(why)) end
end })

-- HUD tab: widgets that stay on screen; press / (window closed) to move them
local hud = Hud.new({
	Title = TITLE,
	Version = (getgenv and getgenv() or _G).ScrdsxVersion,
	GetLocations = function() return Tele.Locations end,
	GetStatus = function()
		local good, warnC, bad, sub = Color3.fromRGB(120, 220, 140), Color3.fromRGB(240, 190, 90), Color3.fromRGB(240, 100, 100), Color3.fromRGB(138, 138, 152)
		local rows = {}
		local me = game:GetService("Players").LocalPlayer
		local c = me.Character
		local hrp = c and c:FindFirstChild("HumanoidRootPart")
		if hrp then
			local w = hrp:GetAttribute("IsWanted") == true
			rows[#rows + 1] = { "Wanted", w and "YES" or "no", w and bad or good }
			local best
			for _, p in ipairs(ESP.PolicePositions(false)) do
				local d = (p - hrp.Position).Magnitude
				if not best or d < best then best = d end
			end
			rows[#rows + 1] = { "Police", best and ("%d st"):format(best) or "none near", best and (best < 150 and bad or (best < 350 and warnC or sub)) or sub }
		end
		if NPC.Enabled then rows[#rows + 1] = { "Auto Drive", NPC.Info, good } end
		if Travel.Busy then rows[#rows + 1] = { "Travel", Travel.Info, warnC } end
		if Escape.Busy then rows[#rows + 1] = { "Escape", Escape.Info, bad } end
		if Farm.Busy then rows[#rows + 1] = { "Farm", Farm.Info, warnC } end
		local car = workspace:FindFirstChild("Vehicles") and workspace.Vehicles:FindFirstChild(me.Name)
		local seat = car and car:FindFirstChild("DriveSeat")
		if seat and hrp then
			local lim = Drive.SpeedLimitAt and Drive.SpeedLimitAt(seat.Position)
			if lim then rows[#rows + 1] = { "Limit", lim >= 500 and "none" or (lim .. " km/h"), sub } end
		end
		return rows
	end,
	GetFarm = function() return { info = Farm.Info, stats = Farm.Stats, drive = Drive.State, pois = Farm.POIs(), earned = Farm.Earned(), busy = Farm.Busy } end,
	GetModules = function()
		local list = {}
		for name, m in pairs({ ["Suspension"] = mSusp, ["Anti Crash Damage"] = mAnti, ["Speed"] = mSpeed, ["Anti Flat Tires"] = mFlat,
			["Vehicle Fly"] = mFly, ["Inf Stamina"] = mStam, ["Auto Rob"] = mFarm, ["Player ESP"] = mEsp, ["Camlock"] = mAim, ["Auto Drive"] = mNpc }) do
			if m:Get() then list[#list + 1] = name end
		end
		return list
	end,
})
local tHud = win:Tab("HUD", { Section = "Client", Icon = 7 })
tHud:Toggle({ Name = "Watermark", Default = hud:IsOn("watermark"), Callback = function(v) hud:SetWidget("watermark", v) end })
tHud:Toggle({ Name = "Player info (health, position, nearest spot)", Default = hud:IsOn("info"), Callback = function(v) hud:SetWidget("info", v) end })
tHud:Toggle({ Name = "Vehicle (speed, fuel, health, tires)", Default = hud:IsOn("vehicle"), Callback = function(v) hud:SetWidget("vehicle", v) end })
tHud:Toggle({ Name = "AutoFarm navigation (status + route map)", Default = hud:IsOn("farm"), Callback = function(v) hud:SetWidget("farm", v) end })
tHud:Toggle({ Name = "Status (wanted, police, travel, auto drive)", Default = hud:IsOn("status"), Callback = function(v) hud:SetWidget("status", v) end })
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
local tCfg = win:Tab("Configs", { Icon = 8 })
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
local tSet = win:Tab("Settings", { Icon = 9 })
tSet:Slider({ Name = "UI scale", Min = 0.7, Max = 1.4, Step = 0.05, Default = 1, Callback = function(v) win:SetScale(v) end })
-- theme: accent + background as hex, applied to the window and the HUD, remembered between sessions
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
	pcall(function() hud:ApplyTheme(map, P) end)
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
tSet:Section("Theme")
local function toHex(c) return string.format("#%02X%02X%02X", math.floor(c.R * 255 + .5), math.floor(c.G * 255 + .5), math.floor(c.B * 255 + .5)) end
local accentPick = tSet:ColorPicker({ Name = "Accent colour", Default = UI.Palette().accent, Callback = function(col, final)
	theme.accent = toHex(col); applyTheme(final)
end })
local bgPick = tSet:ColorPicker({ Name = "Background colour", Default = UI.Palette().bg, Callback = function(col, final)
	theme.bg = toHex(col); applyTheme(final)
end })
if parseHex(theme.accent) then accentPick:Set(parseHex(theme.accent), true) end
if parseHex(theme.bg) then bgPick:Set(parseHex(theme.bg), true) end
if theme.accent ~= "" or theme.bg ~= "" then task.defer(applyTheme, false) end
tSet:Section("Theme presets")
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
tSet:Section("Help")
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
	local env = getgenv and getgenv() or _G
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
	add("status: farm=" .. tostring(Farm.Info) .. " | drive=" .. tostring(NPC.Info) .. " | travel=" .. tostring(Travel.Info) .. " (last method " .. tostring(Travel.LastMethod) .. ", instant refused " .. tostring(Travel.instantFails) .. "x) | escape=" .. tostring(Escape.Info) .. " | aim=" .. tostring(Aim.Info) .. " | esp=" .. tostring(ESP.Info) .. " | stamina=" .. tostring(Player.Info))
	add("start errors: " .. (#startErrors == 0 and "none" or table.concat(startErrors, " ; ")))
	local txt = table.concat(L, "\n")
	pcall(function() setclipboard(txt) end)
	pcall(function() writefile("scrdsx_diagnostics.txt", txt) end)
	win:Notify("Diagnostics copied (and saved to scrdsx_diagnostics.txt)", 4)
end })
tSet:Section("Keys")
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
	Drive.Stop()
	Farm.Destroy()
	ESP.OnPolice = nil
	ESP.Destroy()
	NPC.Destroy()
	Travel.Stop()
	Travel.Notify, Travel.Changed, Travel.Log = nil, nil, nil
	Farm.TravelTo = nil
	Escape.Destroy()
	Extras.Destroy()
	Aim.Changed = nil
	Aim.Destroy()
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

-- camlock key (hold or toggle, see the Aim tab)
table.insert(win.conns, UIS.InputBegan:Connect(function(i, gp)
	-- (gameProcessed is ignored on purpose: the game binds many keys itself and would swallow ours; only typing in a text box blocks it)
	if i.UserInputType ~= Enum.UserInputType.Keyboard or UIS:GetFocusedTextBox() or aimKey:IsListening() then return end
	if aimKey:Get() == i.KeyCode then Aim.KeyEvent(true) end
end))
table.insert(win.conns, UIS.InputEnded:Connect(function(i)
	if i.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if Aim.Hold and aimKey:Get() == i.KeyCode then Aim.KeyEvent(false) end
end))

-- travel keys: back to the last place, panic = escape now
table.insert(win.conns, UIS.InputBegan:Connect(function(i)
	if i.UserInputType ~= Enum.UserInputType.Keyboard or UIS:GetFocusedTextBox() then return end
	if not backKey:IsListening() and backKey:Get() == i.KeyCode then
		local ok, why = Travel.Back()
		if not ok then win:Notify("Travel: " .. tostring(why)) end
	elseif not panicKey:IsListening() and panicKey:Get() == i.KeyCode then
		local ok, why = Escape.Run("panic key")
		if not ok then win:Notify("Escape: " .. tostring(why)) end
	end
end))

-- hospital key
table.insert(win.conns, UIS.InputBegan:Connect(function(i)
	if i.UserInputType ~= Enum.UserInputType.Keyboard or UIS:GetFocusedTextBox() or hospKey:IsListening() then return end
	if hospKey:Get() ~= i.KeyCode then return end
	local ok, why = Farm.GoHospital(true)
	if not ok then win:Notify("Hospital: " .. tostring(why)) end
end))

-- park key: the car lines up with the space under the crosshair and rolls in straight
table.insert(win.conns, UIS.InputBegan:Connect(function(i)
	if i.UserInputType ~= Enum.UserInputType.Keyboard or UIS:GetFocusedTextBox() or parkKey:IsListening() then return end
	if parkKey:Get() ~= i.KeyCode then return end
	local ok, why = NPC.ParkAtCrosshair()
	if not ok then win:Notify("Parking: " .. tostring(why), 3) end
end))

-- quick loot key: first press collects everything in range, pressing it again while collecting stops it
table.insert(win.conns, UIS.InputBegan:Connect(function(i, gp)
	if i.UserInputType ~= Enum.UserInputType.Keyboard or UIS:GetFocusedTextBox() or lootKey:IsListening() or not mLoot:Get() then return end
	if lootKey:Get() ~= i.KeyCode then return end
	if Farm.Busy then
		if not Farm.Enabled then Farm.StopLoot(); win:Notify("Quick loot stopped") end
		return
	end
	win:Notify(Farm.LootWalk and ("Quick loot: walking to piles within " .. tostring(Farm.LootRange) .. " st (press again to stop)") or "Quick loot: picking up everything in reach", 2.5)
	Farm.LootNearby(Farm.LootRange)
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
