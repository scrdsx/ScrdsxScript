-- Player tab: stamina, server hop, quick loot, and the world helpers (lighting, camera zoom, movement).
local UIS = game:GetService("UserInputService")
local Player = __import("player/player")
local Hop = __import("player/hop")
local Loot = __import("player/loot")
local World = __import("player/world")

return function(ctx)
	local win, safe, cycle = ctx.win, ctx.safe, ctx.cycle
	local tPlayer = win:Tab("Player", { Section = "Game", Icon = 2 })
	local mStam = tPlayer:Module({ Name = "Inf Stamina", Default = false, Callback = function(on) Player.SetInfStamina(on) end })
	local lStam = mStam:Label({ Name = "Status", Value = Player.Info })
	Player.Changed = function() lStam:Set(Player.Info) end
	safe("player", Player.Start)

	local mHop = tPlayer:Module({ Name = "Server hop", Default = true, Hidden = true, Callback = function() end })
	mHop:Button({ Name = "Hop to a low server with police", NoSave = true, Callback = function() Hop.Go(false) end })
	local hopKey = mHop:Keybind({ Name = "Hop key", Default = Enum.KeyCode.H })
	mHop:Slider({ Name = "Minimum players", Min = 3, Max = 30, Step = 1, Default = Hop.MinPlayers, Callback = function(v) Hop.MinPlayers = v end })
	mHop:Slider({ Name = "Minimum police", Min = 1, Max = 8, Step = 1, Default = Hop.MinPolice, Callback = function(v) Hop.MinPolice = v end })
	mHop:Toggle({ Name = "Keep hopping until enough police", Default = true, Callback = function(v) Hop.Auto = v end })
	Hop.Notify = function(msg, secs, kind) win:Notify(msg, secs or 3, kind) end
	safe("hop", Hop.Start)
	local mLoot = tPlayer:Module({ Name = "Quick loot", Default = true, Hidden = true, Callback = function() end })
	local lLoot = mLoot:Label({ Name = "Status", Value = Loot.Info })
	local lootKey = mLoot:Keybind({ Name = "Loot key (money, gold, items in reach)", Default = Enum.KeyCode.Y })
	mLoot:Label({ Name = "How it works", Value = "everything in reach, all at once" })
	mLoot:Toggle({ Name = "Auto loot (pick up whatever is in reach)", Default = false, Callback = function(v) Loot.Auto = v end })
	local useName = "bomb"
	mLoot:TextBox({ Name = "Use-all item name (part of the name)", Placeholder = "bomb", Default = "bomb", NoSave = false, Callback = function(t) useName = t or "" end })
	local useKey = mLoot:Keybind({ Name = "Use-all key (every matching item at once)", Default = Enum.KeyCode.U })
	mLoot:Button({ Name = "Use all now", NoSave = true, Callback = function() Loot.UseAll(useName) end })
	Loot.Notify = function(m) win:Notify(m, 2.5) end
	Loot.Changed = function() lLoot:Set(Loot.Info) end
	safe("loot", Loot.Start)

	-- World tab: client-side helpers (lighting, camera, movement)
	local tWorld = tPlayer -- world helpers sit on the Player tab
	tWorld:Section("Lighting")
	tWorld:Toggle({ Name = "Fullbright (no darkness)", Default = false, Callback = function(v) World.Fullbright = v; World.Refresh() end })
	tWorld:Toggle({ Name = "No fog", Default = false, Callback = function(v) World.NoFog = v; World.Refresh() end })
	tWorld:Toggle({ Name = "Lock the time of day", Default = false, Callback = function(v) World.LockTime = v; World.Refresh() end })
	tWorld:Slider({ Name = "Time of day", Min = 0, Max = 24, Step = 0.5, Default = World.Time, Suffix = " h", Callback = function(v) World.Time = v end })
	tWorld:Section("Camera")
	tWorld:Toggle({ Name = "Unlimited camera zoom", Default = false, Callback = function(v) World.Zoom = v end })
	tWorld:Section("Movement (risky: the server may notice)")
	tWorld:Toggle({ Name = "Infinite jump", Default = false, Callback = function(v) World.InfJump = v end })
	tWorld:Toggle({ Name = "Noclip (walk through walls)", Default = false, Callback = function(v) World.Noclip = v end })
	tWorld:Toggle({ Name = "Custom walk speed", Default = false, Callback = function(v) World.SpeedOn = v end })
	tWorld:Slider({ Name = "Walk speed", Min = 16, Max = 80, Step = 1, Default = World.Speed, Callback = function(v) World.Speed = v end })
	safe("world", World.Start)


	table.insert(win.conns, UIS.InputBegan:Connect(function(i)
		if i.UserInputType ~= Enum.UserInputType.Keyboard or UIS:GetFocusedTextBox() or hopKey:IsListening() or not mHop:Get() then return end
		if hopKey:Get() == i.KeyCode then Hop.Go(false) end
	end))

	-- quick loot key: first press collects everything in reach, pressing it again while collecting stops it
	table.insert(win.conns, UIS.InputBegan:Connect(function(i)
		if i.UserInputType ~= Enum.UserInputType.Keyboard or UIS:GetFocusedTextBox() or lootKey:IsListening() or not mLoot:Get() then return end
		if useKey:Get() == i.KeyCode and not useKey:IsListening() then Loot.UseAll(useName); return end
		if lootKey:Get() ~= i.KeyCode then return end
		if Loot.Busy then Loot.Stop(); win:Notify("Quick loot stopped"); return end
		Loot.Run(false)
	end))
end
