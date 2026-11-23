-- Aim tab: camlock, aim assist and triggerbot (combat/aim.lua does the work).
local UIS = game:GetService("UserInputService")
local Aim = __import("combat/aim")
local ESP = __import("visuals/esp")

return function(ctx)
	local win, safe, cycle = ctx.win, ctx.safe, ctx.cycle
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
end
