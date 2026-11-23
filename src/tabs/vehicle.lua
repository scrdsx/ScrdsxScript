-- Vehicle Mods tab: quick repair, suspension, Maybach suspension, anti crash, speed, anti flat tyres, vehicle fly and Auto Drive.
local UIS = game:GetService("UserInputService")
local Vehicle = __import("vehicle/vehicle")
local Maybach = __import("vehicle/maybach")
local Repair = __import("vehicle/repair")
local Anti = __import("vehicle/anticrash")
local Speed = __import("vehicle/speed")
local AntiFlat = __import("vehicle/antiflat")
local Fly = __import("vehicle/fly")
local NPC = __import("drive/autonpc")
local Drive = __import("drive/autodrive")

return function(ctx)
	local win, safe, cycle = ctx.win, ctx.safe, ctx.cycle
	local tVeh = win:Tab("Vehicle Mods", { Section = "Game", Icon = 1 })
	local lCar = tVeh:Label({ Name = "Car", Value = Vehicle.Info })
	local mRep = tVeh:Module({ Name = "Quick repair", Default = true, Hidden = true, Callback = function() end })
	local lRep = mRep:Label({ Name = "Car health", Value = "-" })
	local repKey = mRep:Keybind({ Name = "Repair key", Default = Enum.KeyCode.J })
	mRep:Toggle({ Name = "Auto repair when damaged", Default = false, Callback = function(v) Repair.Auto = v end })
	mRep:Slider({ Name = "Auto repair below", Min = 10, Max = 90, Step = 5, Default = Repair.Threshold, Suffix = "%", Callback = function(v) Repair.Threshold = v end })
	Repair.Notify = function(msg, secs, kind) win:Notify(msg, secs or 3, kind) end
	safe("repair", Repair.Start)
	task.spawn(function()
		while ctx.alive() do
			task.wait(0.7)
			pcall(function() local p = Repair.Percent(); lRep:Set(p and (math.floor(p + .5) .. "%") or "-") end)
		end
	end)
	local mSusp = tVeh:Module({ Name = "Suspension", Default = false, Callback = function(on) Vehicle.SetEnabled(on) end })
	mSusp:Slider({ Name = "Height", Min = 0, Max = Vehicle.MaxHeight, Step = 0.5, Default = 0, Suffix = " st", Callback = function(v) Vehicle.SetHeight(v) end })
	mSusp:Toggle({ Name = "Set game's suspensionHeight", Default = true, Callback = function(v) Vehicle.UseAttribute = v end })
	mSusp:Toggle({ Name = "Also raise springs", Default = false, Callback = function(v) Vehicle.UseSprings = v end })
	Vehicle.Changed = function() lCar:Set(Vehicle.Info) end
	safe("vehicle", Vehicle.Start)

	-- Maybach suspension: the body rises and drops (instantly or smoothly), rolls, hops, leans into turns, lift on a key
	local mMay = tVeh:Module({ Name = "Maybach suspension", Default = false, Callback = function(on)
		Maybach.SetEnabled(on)
		if on then win:Notify("Maybach suspension on: " .. Maybach.Mode .. " (sit in your car)", 3, "success") end
	end })
	local lMay = mMay:Label({ Name = "Status", Value = Maybach.Info })
	mMay:Choice({ Name = "Mode", Options = Maybach.Modes, Default = Maybach.Mode, Callback = function(v) Maybach.Mode = v; Maybach.Restart() end })
	mMay:Slider({ Name = "Lift height", Min = 0.5, Max = 4, Step = 0.1, Default = Maybach.Lift, Suffix = " st", Callback = function(v) Maybach.Lift = v end })
	mMay:Choice({ Name = "Which corners move (Pulse / Float / Hop / lift key)", Options = Maybach.CornerSets, Default = Maybach.Corners, Callback = function(v) Maybach.Corners = v end })
	mMay:Choice({ Name = "Three wheel: corner up", Options = Maybach.CornerNames, Default = Maybach.Corner, Callback = function(v) Maybach.Corner = v end })
	mMay:Section("Timing")
	mMay:Slider({ Name = "Rise time", Min = 0.1, Max = 4, Step = 0.05, Default = Maybach.Rise, Suffix = " s", Callback = function(v) Maybach.Rise = v end })
	mMay:Slider({ Name = "Wait at the top", Min = 0, Max = 4, Step = 0.05, Default = Maybach.HoldTop, Suffix = " s", Callback = function(v) Maybach.HoldTop = v end })
	mMay:Slider({ Name = "Drop time (0 = instant)", Min = 0, Max = 3, Step = 0.05, Default = Maybach.Drop, Suffix = " s", Callback = function(v) Maybach.Drop = v end })
	mMay:Slider({ Name = "Wait at the bottom", Min = 0, Max = 4, Step = 0.05, Default = Maybach.HoldBottom, Suffix = " s", Callback = function(v) Maybach.HoldBottom = v end })
	mMay:Section("Ride")
	mMay:Slider({ Name = "Lowered stance", Min = 0, Max = 1.5, Step = 0.1, Default = Maybach.Stance, Suffix = " st", Callback = function(v) Maybach.Stance = v end })
	mMay:Toggle({ Name = "Only move when standing still", Default = Maybach.StillOnly, Callback = function(v) Maybach.StillOnly = v end })
	mMay:Slider({ Name = "Smoothness of lift / lean (lower = softer)", Min = 1, Max = 12, Step = 0.5, Default = Maybach.Smooth, Callback = function(v) Maybach.Smooth = v end })
	mMay:Section("Magic body")
	mMay:Toggle({ Name = "Level the body (lean into turns, no nose dive)", Default = Maybach.Level, Callback = function(v) Maybach.Level = v end })
	mMay:Slider({ Name = "Lean amount", Min = 0.1, Max = 1.5, Step = 0.1, Default = Maybach.LevelAmount, Suffix = " st", Callback = function(v) Maybach.LevelAmount = v end })
	mMay:Section("Lift")
	local mayKey = mMay:Keybind({ Name = "Lift key", Default = Enum.KeyCode.Y })
	local mayHold = mMay:Toggle({ Name = "Hold the key (off = press to toggle)", Default = false })
	safe("maybach", Maybach.Start)
	task.spawn(function()
		while ctx.alive() do
			task.wait(0.5)
			pcall(function() lMay:Set(Maybach.Info) end)
		end
	end)
	table.insert(win.conns, UIS.InputBegan:Connect(function(i)
		if i.UserInputType ~= Enum.UserInputType.Keyboard or UIS:GetFocusedTextBox() or mayKey:IsListening() or not mMay:Get() then return end
		if mayKey:Get() ~= i.KeyCode then return end
		if mayHold:Get() then Maybach.SetLifted(true) else win:Notify(Maybach.ToggleLift() and "Maybach: lifting" or "Maybach: lowering", 1.5) end
	end))
	table.insert(win.conns, UIS.InputEnded:Connect(function(i)
		if mayHold:Get() and mayKey:Get() == i.KeyCode then Maybach.SetLifted(false) end
	end))

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


	-- Auto Drive tab: the car drives itself like an NPC (roam the map, follow a player, park straight)
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


	-- fly toggle key (not while typing or while the key box is waiting for a key)
	table.insert(win.conns, UIS.InputBegan:Connect(function(i, gp)
		if gp or i.UserInputType ~= Enum.UserInputType.Keyboard or flyKey:IsListening() then return end
		if flyKey:Get() == i.KeyCode then mFly:Set(not mFly:Get()) end
	end))
	-- park key: the car lines up with the space under the crosshair and rolls in straight
	table.insert(win.conns, UIS.InputBegan:Connect(function(i)
		if i.UserInputType ~= Enum.UserInputType.Keyboard or UIS:GetFocusedTextBox() or parkKey:IsListening() then return end
		if parkKey:Get() ~= i.KeyCode then return end
		local ok, why = NPC.ParkAtCrosshair()
		if not ok then win:Notify("Parking: " .. tostring(why), 3) end
	end))
	table.insert(win.conns, UIS.InputBegan:Connect(function(i)
		if i.UserInputType ~= Enum.UserInputType.Keyboard or UIS:GetFocusedTextBox() or repKey:IsListening() or not mRep:Get() then return end
		if repKey:Get() == i.KeyCode then Repair.Run(false) end
	end))
end
