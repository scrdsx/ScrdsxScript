local UIS = game:GetService("UserInputService")
local UI = __import("ui")
local Loading = __import("loading")
local Vehicle = __import("vehicle")
local Fly = __import("fly")
local Player = __import("player")
local Anti = __import("anticrash")
local AntiFlat = __import("antiflat")
local Speed = __import("speed")
local Config = __import("config")
local Drive = __import("autodrive")
local ESP = __import("esp")
local Aim = __import("aim")
local Extras = __import("extras")
local Loot = __import("loot")
local FPS = __import("fps")
local Crosshair = __import("crosshair")
local Visuals = __import("visuals")
local Skins = __import("skins")

local TITLE = "Scrdsx"
local SUBTITLE = "Solutions  v" .. tostring((getgenv and getgenv() or _G).ScrdsxVersion or "?") -- TODO: set the script name
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

-- helper: a button that cycles through a list (the UI has no dropdown)
local function cycle(parent, title, list, get, set)
	local idx = 1
	for i, v in ipairs(list) do if v == get() then idx = i end end
	local b
	b = parent:Button({ Name = title .. ": " .. tostring(list[idx]), NoSave = true, Callback = function()
		idx = idx % #list + 1
		set(list[idx])
		b:SetText(title .. ": " .. tostring(list[idx]))
	end })
	return b
end

-- COMBAT ---------------------------------------------------------------------------------------------------------------
local tAim = win:Tab("Aim", { Section = "Combat", Icon = 4 })
local mAim = tAim:Module({ Name = "Camlock", Default = false, Callback = function(on) Aim.SetEnabled(on) end })
local lAim = mAim:Label({ Name = "Status", Value = Aim.Info })
Aim.Changed = function() lAim:Set(Aim.Info) end
mAim:Section("Activation")
local aimKey = mAim:Keybind({ Name = "Aim key", Default = Enum.KeyCode.Z })
mAim:Toggle({ Name = "Hold the key (off = press to toggle)", Default = Aim.Hold, Callback = function(v) Aim.Hold = v; Aim.Active = false end })
mAim:Toggle({ Name = "Mouse lock (cursor stays in the centre while aiming)", Default = Aim.MouseLock, Callback = function(v) Aim.MouseLock = v end })
mAim:Section("Targeting")
mAim:Toggle({ Name = "Aim at the head (off = body)", Default = true, Callback = function(v) Aim.Part = v and "Head" or "Torso" end })
cycle(mAim, "Target priority", Aim.Priorities, function() return Aim.Priority end, function(v) Aim.Priority = v end)
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
mAim:Toggle({ Name = "Filled circle", Default = Aim.FovFilled, Callback = function(v) Aim.FovFilled = v end })
mAim:Slider({ Name = "Circle thickness", Min = 0.5, Max = 4, Step = 0.1, Default = Aim.FovThick, Callback = function(v) Aim.FovThick = v end })
mAim:ColorPicker({ Name = "Circle colour", Default = Aim.FovColor, Callback = function(c) Aim.FovColor = c end })
mAim:Toggle({ Name = "Line to the target", Default = Aim.ShowLine, Callback = function(v) Aim.ShowLine = v end })
mAim:ColorPicker({ Name = "Line colour", Default = Aim.LineColor, Callback = function(c) Aim.LineColor = c end })
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

local mAssist = tAim:Module({ Name = "Aim Assist (soft pull)", Default = false, Callback = function(on) Aim.AssistEnabled = on end })
mAssist:Label({ Name = "What it does", Value = "gentle pull while you aim" })
cycle(mAssist, "Active while", Aim.AssistButtons, function() return Aim.AssistButton end, function(v) Aim.AssistButton = v end)
mAssist:Slider({ Name = "Pull strength", Min = 0.02, Max = 0.6, Step = 0.02, Default = Aim.AssistStrength, Callback = function(v) Aim.AssistStrength = v end })
mAssist:Slider({ Name = "Assist field of view", Min = 40, Max = 400, Step = 10, Default = Aim.AssistFOV, Suffix = " px", Callback = function(v) Aim.AssistFOV = v end })

local mTrig = tAim:Module({ Name = "Triggerbot", Default = false, Callback = function(on) Aim.Trigger = on end })
mTrig:Label({ Name = "What it does", Value = "clicks when the crosshair is on a player" })
mTrig:Slider({ Name = "Delay between shots", Min = 0.03, Max = 0.6, Step = 0.01, Default = Aim.TriggerDelay, Suffix = " s", Callback = function(v) Aim.TriggerDelay = v end })
mTrig:Slider({ Name = "Range", Min = 20, Max = 1000, Step = 10, Default = Aim.TriggerRange, Suffix = " st", Callback = function(v) Aim.TriggerRange = v end })
mTrig:Toggle({ Name = "Only while a key is held", Default = Aim.TriggerHold, Callback = function(v) Aim.TriggerHold = v end })
mTrig:Keybind({ Name = "Trigger key", Default = Enum.KeyCode.X, Callback = function(k) Aim.TriggerKey = k end })
Aim.TriggerKey = Enum.KeyCode.X
safe("aim", Aim.Start)

-- VISUALS ---------------------------------------------------------------------------------------------------------------
local tEsp = win:Tab("Visuals", { Section = "Combat", Icon = 3 })
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
mEsp:Toggle({ Name = "Wanted stars + bounty (instead of the word WANTED)", Default = ESP.Stars, Callback = function(v) ESP.Stars = v end })
mEsp:Toggle({ Name = "Car health next to the distance", Default = ESP.CarInfo, Callback = function(v) ESP.CarInfo = v end })
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
local mSpot = tEsp:Module({ Name = "Car weak spots (where to hit)", Default = false, Callback = function(on) ESP.Spots = on end })
mSpot:Label({ Name = "Marks", Value = "tyres, engine, fuel tank" })
mSpot:Slider({ Name = "Show within", Min = 60, Max = 500, Step = 10, Default = ESP.SpotDist, Suffix = " st", Callback = function(v) ESP.SpotDist = v end })
mSpot:Toggle({ Name = "Only cars of wanted players", Default = false, Callback = function(v) ESP.SpotsWantedOnly = v end })
ESP.OnPolice = function(d) win:Notify(("Police nearby: %d studs"):format(d), 4) end
safe("esp", ESP.Start)

local mCham = tEsp:Module({ Name = "Chams (glowing outlines through walls)", Default = false, Callback = function(on) Visuals.Chams.Enabled = on end })
local lCham = mCham:Label({ Name = "Players lit", Value = 0 })
mCham:Toggle({ Name = "Team colours (police blue, fire red, wanted red)", Default = Visuals.Chams.TeamColors, Callback = function(v) Visuals.Chams.TeamColors = v end })
mCham:ColorPicker({ Name = "Fill colour (when team colours are off)", Default = Visuals.Chams.Fill, Callback = function(c) Visuals.Chams.Fill = c end })
mCham:ColorPicker({ Name = "Outline colour (when team colours are off)", Default = Visuals.Chams.Outline, Callback = function(c) Visuals.Chams.Outline = c end })
mCham:Slider({ Name = "Fill see-through", Min = 0, Max = 1, Step = 0.05, Default = Visuals.Chams.FillAlpha, Callback = function(v) Visuals.Chams.FillAlpha = v end })
mCham:Slider({ Name = "Outline see-through", Min = 0, Max = 1, Step = 0.05, Default = Visuals.Chams.OutlineAlpha, Callback = function(v) Visuals.Chams.OutlineAlpha = v end })
mCham:Toggle({ Name = "Show through walls", Default = Visuals.Chams.AlwaysOnTop, Callback = function(v) Visuals.Chams.AlwaysOnTop = v end })
mCham:Toggle({ Name = "Wanted players pulse", Default = Visuals.Chams.Pulse, Callback = function(v) Visuals.Chams.Pulse = v end })
mCham:Toggle({ Name = "Also light myself", Default = Visuals.Chams.Self, Callback = function(v) Visuals.Chams.Self = v end })
mCham:Slider({ Name = "Max distance", Min = 100, Max = 3000, Step = 50, Default = Visuals.Chams.MaxDist, Suffix = " st", Callback = function(v) Visuals.Chams.MaxDist = v end })
mCham:Toggle({ Name = "Police", Default = true, Callback = function(v) Visuals.Chams.Teams.Police = v end })
mCham:Toggle({ Name = "Fire department", Default = true, Callback = function(v) Visuals.Chams.Teams.FireDepartment = v end })
mCham:Toggle({ Name = "Citizens", Default = true, Callback = function(v) Visuals.Chams.Teams.Citizen = v end })
mCham:Toggle({ Name = "Other jobs / prisoners", Default = true, Callback = function(v) Visuals.Chams.Teams.Other = v end })

local mPoint = tEsp:Module({ Name = "Player pointers (arrows + avatar)", Default = false, Callback = function(on) Visuals.Pointers.Enabled = on end })
local lPoint = mPoint:Label({ Name = "Pointing at", Value = 0 })
cycle(mPoint, "Show", { "Offscreen", "Always" }, function() return Visuals.Pointers.Mode end, function(v) Visuals.Pointers.Mode = v end)
cycle(mPoint, "Picture", Visuals.Kinds, function() return Visuals.Pointers.Kind end, function(v) Visuals.Pointers.Kind = v end)
mPoint:Toggle({ Name = "Show the avatar picture", Default = Visuals.Pointers.Avatar, Callback = function(v) Visuals.Pointers.Avatar = v end })
mPoint:Toggle({ Name = "Distance", Default = Visuals.Pointers.Distance, Callback = function(v) Visuals.Pointers.Distance = v end })
mPoint:Toggle({ Name = "Name", Default = Visuals.Pointers.Name, Callback = function(v) Visuals.Pointers.Name = v end })
mPoint:Toggle({ Name = "Team colours", Default = Visuals.Pointers.TeamColors, Callback = function(v) Visuals.Pointers.TeamColors = v end })
mPoint:ColorPicker({ Name = "Colour (when team colours are off)", Default = Visuals.Pointers.Color, Callback = function(c) Visuals.Pointers.Color = c end })
mPoint:Slider({ Name = "Ring size", Min = 0.2, Max = 0.48, Step = 0.01, Default = Visuals.Pointers.Radius, Callback = function(v) Visuals.Pointers.Radius = v end })
mPoint:Slider({ Name = "Arrow / picture size", Min = 0.6, Max = 2, Step = 0.05, Default = Visuals.Pointers.Scale, Callback = function(v) Visuals.Pointers.Scale = v end })
mPoint:Slider({ Name = "Max distance", Min = 100, Max = 5000, Step = 100, Default = Visuals.Pointers.MaxDist, Suffix = " st", Callback = function(v) Visuals.Pointers.MaxDist = v end })
mPoint:Toggle({ Name = "Police", Default = true, Callback = function(v) Visuals.Pointers.Teams.Police = v end })
mPoint:Toggle({ Name = "Fire department", Default = true, Callback = function(v) Visuals.Pointers.Teams.FireDepartment = v end })
mPoint:Toggle({ Name = "Citizens", Default = true, Callback = function(v) Visuals.Pointers.Teams.Citizen = v end })
mPoint:Toggle({ Name = "Other jobs / prisoners", Default = true, Callback = function(v) Visuals.Pointers.Teams.Other = v end })

local mMark = tEsp:Module({ Name = "Avatar markers (picture above heads)", Default = false, Callback = function(on) Visuals.Markers.Enabled = on end })
local lMark = mMark:Label({ Name = "Markers", Value = 0 })
cycle(mMark, "Picture", Visuals.Kinds, function() return Visuals.Markers.Kind end, function(v) Visuals.Markers.Kind = v end)
mMark:Slider({ Name = "Size", Min = 24, Max = 90, Step = 2, Default = Visuals.Markers.Size, Suffix = " px", Callback = function(v) Visuals.Markers.Size = v end })
mMark:Toggle({ Name = "Name", Default = Visuals.Markers.Name, Callback = function(v) Visuals.Markers.Name = v end })
mMark:Toggle({ Name = "Distance", Default = Visuals.Markers.Distance, Callback = function(v) Visuals.Markers.Distance = v end })
mMark:Toggle({ Name = "Team colours", Default = Visuals.Markers.TeamColors, Callback = function(v) Visuals.Markers.TeamColors = v end })
mMark:ColorPicker({ Name = "Colour (when team colours are off)", Default = Visuals.Markers.Color, Callback = function(c) Visuals.Markers.Color = c end })
mMark:Slider({ Name = "Max distance", Min = 50, Max = 2000, Step = 50, Default = Visuals.Markers.MaxDist, Suffix = " st", Callback = function(v) Visuals.Markers.MaxDist = v end })
mMark:Toggle({ Name = "Police", Default = true, Callback = function(v) Visuals.Markers.Teams.Police = v end })
mMark:Toggle({ Name = "Fire department", Default = true, Callback = function(v) Visuals.Markers.Teams.FireDepartment = v end })
mMark:Toggle({ Name = "Citizens", Default = true, Callback = function(v) Visuals.Markers.Teams.Citizen = v end })
mMark:Toggle({ Name = "Other jobs / prisoners", Default = true, Callback = function(v) Visuals.Markers.Teams.Other = v end })
safe("visuals", Visuals.Start)
task.spawn(function() -- the live counters in the module rows
	while true do
		task.wait(0.5)
		pcall(function()
			lCham:Set(Visuals.Chams.Count); lPoint:Set(Visuals.Pointers.Count); lMark:Set(Visuals.Markers.Count)
		end)
	end
end)

-- CROSSHAIR -------------------------------------------------------------------------------------------------------------
local tCross = win:Tab("Crosshair", { Section = "Combat", Icon = 5 })
local mCross = tCross:Module({ Name = "Custom crosshair", Default = false, Callback = function(on) Crosshair.SetEnabled(on) end })
cycle(mCross, "Style", Crosshair.Styles, function() return Crosshair.Style end, function(v) Crosshair.Style = v; Crosshair.Rebuild() end)
mCross:ColorPicker({ Name = "Colour", Default = Crosshair.Color, Callback = function(c) Crosshair.Color = c; Crosshair.Rebuild() end })
mCross:ColorPicker({ Name = "Colour over a player", Default = Crosshair.TargetColor, Callback = function(c) Crosshair.TargetColor = c end })
mCross:Slider({ Name = "Size", Min = 2, Max = 40, Step = 1, Default = Crosshair.Size, Suffix = " px", Callback = function(v) Crosshair.Size = v; Crosshair.Rebuild() end })
mCross:Slider({ Name = "Gap", Min = 0, Max = 24, Step = 1, Default = Crosshair.Gap, Suffix = " px", Callback = function(v) Crosshair.Gap = v; Crosshair.Rebuild() end })
mCross:Slider({ Name = "Thickness", Min = 1, Max = 8, Step = 1, Default = Crosshair.Thickness, Suffix = " px", Callback = function(v) Crosshair.Thickness = v; Crosshair.Rebuild() end })
mCross:Slider({ Name = "See-through", Min = 0, Max = 0.9, Step = 0.05, Default = 1 - Crosshair.Alpha, Callback = function(v) Crosshair.Alpha = 1 - v; Crosshair.Rebuild() end })
mCross:Toggle({ Name = "Dark outline", Default = Crosshair.Outline, Callback = function(v) Crosshair.Outline = v; Crosshair.Rebuild() end })
mCross:Toggle({ Name = "Centre dot", Default = Crosshair.CenterDot, Callback = function(v) Crosshair.CenterDot = v; Crosshair.Rebuild() end })
mCross:Toggle({ Name = "Turn red over a player", Default = Crosshair.ColorOnTarget, Callback = function(v) Crosshair.ColorOnTarget = v end })
mCross:Toggle({ Name = "Rainbow", Default = Crosshair.Rainbow, Callback = function(v) Crosshair.Rainbow = v end })
mCross:Toggle({ Name = "Spread while moving", Default = Crosshair.Dynamic, Callback = function(v) Crosshair.Dynamic = v end })
mCross:Toggle({ Name = "Spin", Default = Crosshair.Spin, Callback = function(v) Crosshair.Spin = v end })
mCross:Slider({ Name = "Spin speed", Min = 10, Max = 360, Step = 10, Default = Crosshair.SpinSpeed, Suffix = " deg/s", Callback = function(v) Crosshair.SpinSpeed = v end })
mCross:Toggle({ Name = "Follow the mouse cursor (off = screen centre)", Default = Crosshair.FollowMouse, Callback = function(v) Crosshair.FollowMouse = v end })
mCross:Toggle({ Name = "Hide the normal cursor", Default = Crosshair.HideCursor, Callback = function(v) Crosshair.SetHideCursor(v) end })
safe("crosshair", Crosshair.Start)

-- SKINS -----------------------------------------------------------------------------------------------------------------
local tSkin = win:Tab("Skins", { Section = "Combat", Icon = 7 })
local lSkinNote = tSkin:Label({ Name = "Only you see these", Value = "client-side" })
local mPaint = tSkin:Module({ Name = "My skin (paint my character)", Default = false, Callback = function(on) Skins.Paint.Enabled = on; Skins.Refresh() end })
mPaint:ColorPicker({ Name = "Colour", Default = Skins.Paint.Color, Callback = function(c) Skins.Paint.Color = c end })
cycle(mPaint, "Material", Skins.Materials, function() return Skins.Paint.Material end, function(v) Skins.Paint.Material = v end)
mPaint:Slider({ Name = "See-through", Min = 0, Max = 0.95, Step = 0.05, Default = Skins.Paint.Transparency, Callback = function(v) Skins.Paint.Transparency = v end })
mPaint:Toggle({ Name = "Rainbow", Default = Skins.Paint.Rainbow, Callback = function(v) Skins.Paint.Rainbow = v end })
mPaint:Toggle({ Name = "Paint hats / accessories too", Default = Skins.Paint.Accessories, Callback = function(v) Skins.Paint.Accessories = v; Skins.Refresh() end })
mPaint:Section("Presets")
for _, pr in ipairs(Skins.Presets) do
	mPaint:Button({ Name = "Preset: " .. pr.name, NoSave = true, Callback = function()
		Skins.ApplyPreset(pr)
		mPaint:Set(true)
		win:Notify("Skin: " .. pr.name, 2)
	end })
end

local mOthers = tSkin:Module({ Name = "Paint other players", Default = false, Callback = function(on) Skins.Others.Enabled = on; Skins.Refresh() end })
mOthers:Toggle({ Name = "Team colours", Default = Skins.Others.TeamColors, Callback = function(v) Skins.Others.TeamColors = v end })
mOthers:ColorPicker({ Name = "Colour (when team colours are off)", Default = Skins.Others.Color, Callback = function(c) Skins.Others.Color = c end })
cycle(mOthers, "Material", Skins.Materials, function() return Skins.Others.Material end, function(v) Skins.Others.Material = v end)
mOthers:Slider({ Name = "See-through", Min = 0, Max = 0.95, Step = 0.05, Default = Skins.Others.Transparency, Callback = function(v) Skins.Others.Transparency = v end })
mOthers:Toggle({ Name = "Rainbow", Default = Skins.Others.Rainbow, Callback = function(v) Skins.Others.Rainbow = v end })

tSkin:Section("Copy a Roblox avatar onto me")
local skinName = ""
tSkin:TextBox({ Name = "Username or user id", Placeholder = "e.g. Roblox", NoSave = true, Callback = function(t) skinName = t or "" end })
tSkin:Button({ Name = "Apply that avatar to my character", NoSave = true, Callback = function()
	local ok, why = Skins.CopyUser(skinName)
	win:Notify(ok and "Avatar applied (only you see it)" or ("Could not apply: " .. tostring(why)), 3)
end })
tSkin:Toggle({ Name = "Keep the avatar after respawning", Default = Skins.KeepLook, Callback = function(v) Skins.KeepLook = v end })
tSkin:Button({ Name = "Back to my own avatar", NoSave = true, Callback = function() Skins.RestoreLook(); win:Notify("Original avatar restored", 2) end })
safe("skins", Skins.Start)

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

local mLoot = tPlayer:Module({ Name = "Quick loot", Default = true, Callback = function() end })
local lLoot = mLoot:Label({ Name = "Status", Value = Loot.Info })
local lootKey = mLoot:Keybind({ Name = "Loot key (money, gold, items in reach)", Default = Enum.KeyCode.Y })
mLoot:Label({ Name = "How it works", Value = "everything in reach, all at once" })
mLoot:Toggle({ Name = "Auto loot (pick up whatever is in reach)", Default = false, Callback = function(v) Loot.Auto = v end })
Loot.Notify = function(m) win:Notify(m, 2.5) end
Loot.Changed = function() lLoot:Set(Loot.Info) end
safe("loot", Loot.Start)

-- World tab: client-side helpers (lighting, camera, movement)
local tWorld = tPlayer
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

-- FPS tab: client-side optimisations (each one remembers the original value, so turning it off restores everything)
local tFps = win:Tab("FPS", { Section = "Game", Icon = 6 })
local lFps = tFps:Label({ Name = "FPS now", Value = "-" })
local lLow = tFps:Label({ Name = "Worst frame (last 2 s)", Value = "-" })
tFps:Button({ Name = "Preset: invisible tweaks (you will not notice them)", NoSave = true, Callback = function()
	FPS.Preset("invisible"); win:Notify("FPS: invisible tweaks on", 2.5)
end })
tFps:Button({ Name = "Preset: maximum FPS (no shadows, no particles)", NoSave = true, Callback = function()
	FPS.Preset("max"); win:Notify("FPS: maximum mode on", 2.5)
end })
tFps:Button({ Name = "Turn all optimisations off", NoSave = true, Callback = function()
	FPS.AllOff(); win:Notify("FPS: everything back to normal", 2.5)
end })
tFps:Section("Things you will not notice")
tFps:Toggle({ Name = "Post effects off (bloom, blur, sun rays, depth of field)", Default = false, Callback = function(v) FPS.SetEffects(v) end })
tFps:Toggle({ Name = "Cheaper environment lighting", Default = false, Callback = function(v) FPS.SetLighting(v) end })
tFps:Toggle({ Name = "Calm water + no grass sway", Default = false, Callback = function(v) FPS.SetTerrain(v) end })
tFps:Toggle({ Name = "Lower mesh detail", Default = false, Callback = function(v) FPS.SetMeshDetail(v) end })
tFps:Section("Bigger savings (the world looks a little different)")
tFps:Toggle({ Name = "No shadows", Default = false, Callback = function(v) FPS.SetShadows(v) end })
tFps:Toggle({ Name = "No particles (smoke, fire, sparks, trails)", Default = false, Callback = function(v) FPS.SetParticles(v) end })
tFps:Toggle({ Name = "Lower graphics level", Default = false, Callback = function(v) FPS.SetQuality(v) end })
tFps:Slider({ Name = "Graphics level (1 = lowest)", Min = 1, Max = 10, Step = 1, Default = FPS.QualityLevel, Callback = function(v) FPS.SetQualityLevel(v) end })
tFps:Section("Frame rate limit")
tFps:Toggle({ Name = "Unlock the FPS limit", Default = false, Callback = function(v) FPS.SetUnlock(v) end })
tFps:Slider({ Name = "Limit", Min = 30, Max = 360, Step = 10, Default = FPS.CapValue, Suffix = " fps", Callback = function(v) FPS.SetCap(v) end })
safe("fps", FPS.Start)
task.spawn(function()
	while true do
		task.wait(0.5)
		pcall(function() lFps:Set(FPS.Fps); lLow:Set(FPS.Low > 0 and (FPS.Low .. " fps") or "-") end)
	end
end)

-- Auto Drive tab: the car drives itself like an NPC (roam the map, follow a player, park straight)
local NPC = __import("autonpc")
local tNpc = tVeh
local mNpc
mNpc = tNpc:Module({ Name = "Auto Drive", Default = false, NoSave = true, Callback = function(on)
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
mNpc:Section("Parking")
local parkKey = mNpc:Keybind({ Name = "Park key (look at the space, press)", Default = Enum.KeyCode.K })
mNpc:Button({ Name = "Park straight at the crosshair now", Callback = function()
	local ok, why = NPC.ParkAtCrosshair()
	if not ok then win:Notify("Parking: " .. tostring(why)) end
end })

-- Configs tab: everything you change (modules on/off, sliders, keybinds) is saved and loaded again next time
local tCfg = win:Tab("Configs", { Icon = 8 })
local current = Config.GetAutoload() or "default"
local lCurrent = tCfg:Label({ Name = "Current config", Value = current })
local autosave, newName, lastSnap = true, "", nil
local cfgButtons = {}

local function snapshot() return { v = 1, flags = win:GetConfig() } end
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
		add("status: drive=" .. tostring(NPC.Info) .. " | aim=" .. tostring(Aim.Info) .. " | esp=" .. tostring(ESP.Info) .. " | visuals=" .. tostring(Visuals.Info) .. " | crosshair=" .. tostring(Crosshair.Info) .. " | skins=" .. tostring(Skins.Info) .. " | stamina=" .. tostring(Player.Info))
	add("start errors: " .. (#startErrors == 0 and "none" or table.concat(startErrors, " ; ")))
	local txt = table.concat(L, "\n")
	pcall(function() setclipboard(txt) end)
	pcall(function() writefile("scrdsx_diagnostics.txt", txt) end)
	win:Notify("Diagnostics copied (and saved to scrdsx_diagnostics.txt)", 4)
end })
tSet:Section("Keys")
tSet:Label({ Name = "Toggle UI", Value = "RightShift" })
tSet:Label({ Name = "Search (menu open)", Value = "/" })

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
	Drive.Stop()
	ESP.OnPolice = nil
	ESP.Destroy()
	NPC.Destroy()
	Extras.Destroy()
	Loot.Destroy()
	FPS.Destroy()
	Crosshair.Destroy()
	Visuals.Destroy()
	Skins.Destroy()
	Aim.Changed = nil
	Aim.Destroy()
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
		win:Toggle()
	elseif i.KeyCode == Enum.KeyCode.Slash and win.visible and not gp then -- menu open: search (chat uses / too, so not while typing)
		win.searchBox:CaptureFocus()
		task.defer(function() win.searchBox.Text = "" end)
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

-- park key: the car lines up with the space under the crosshair and rolls in straight
table.insert(win.conns, UIS.InputBegan:Connect(function(i)
	if i.UserInputType ~= Enum.UserInputType.Keyboard or UIS:GetFocusedTextBox() or parkKey:IsListening() then return end
	if parkKey:Get() ~= i.KeyCode then return end
	local ok, why = NPC.ParkAtCrosshair()
	if not ok then win:Notify("Parking: " .. tostring(why), 3) end
end))

-- quick loot key: first press collects everything in reach, pressing it again while collecting stops it
table.insert(win.conns, UIS.InputBegan:Connect(function(i)
	if i.UserInputType ~= Enum.UserInputType.Keyboard or UIS:GetFocusedTextBox() or lootKey:IsListening() or not mLoot:Get() then return end
	if lootKey:Get() ~= i.KeyCode then return end
	if Loot.Busy then Loot.Stop(); win:Notify("Quick loot stopped"); return end
	Loot.Run(false)
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
