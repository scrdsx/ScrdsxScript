-- Configs tab: every setting (modules, sliders, keybinds, colours, choices) is saved per config and autosaved every 5 s.
local UIS = game:GetService("UserInputService")
local Config = __import("core/config")

return function(ctx)
	local win, safe, cycle = ctx.win, ctx.safe, ctx.cycle
	local tCfg = win:Tab("Configs", { Section = "Client", Icon = 8 })
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
		tCfg:TextBox({ Name = "New config name", NoSave = true, Placeholder = "e.g. cars", Callback = function(t) newName = t end })
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


	-- load the config you used last time (or start 'default'), then keep it saved. Called by main once every tab exists.
	local function loadStart()
		if Config.Available then
			if Config.Exists(current) then
				applyConfig(current)
			else
				saveCurrent(true)
				Config.SetAutoload(current)
			end
			refreshList()
			task.spawn(function()
				while ctx.alive() do
					task.wait(5)
					if autosave then pcall(saveCurrent) end
				end
			end)
		end

	end

	return { save = saveCurrent, loadStart = loadStart }
end
