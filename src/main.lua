local UIS = game:GetService("UserInputService")
local UI = __import("ui")
local Loading = __import("loading")
local Vehicle = __import("vehicle")

local TITLE, SUBTITLE = "Scrdsx Solutions", "Script" -- TODO: set the script name

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
tVeh:Slider({ Name = "Suspension height", Min = 0, Max = Vehicle.MaxHeight, Step = 0.5, Default = 0, Suffix = " st", Callback = function(v) Vehicle.SetHeight(v) end })
tVeh:Toggle({ Name = "Set game's suspensionHeight", Default = true, Callback = function(v) Vehicle.UseAttribute = v end })
tVeh:Toggle({ Name = "Also raise springs", Default = false, Callback = function(v) Vehicle.UseSprings = v end })
tVeh:Button({ Name = "Reset suspension", Callback = function() Vehicle.SetHeight(0); win:Notify("Suspension reset (move the slider to re-apply)") end })
Vehicle.Changed = function() lCar:Set(Vehicle.Info) end
Vehicle.Start()

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
