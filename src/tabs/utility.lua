-- Utility tab: field of view, hold-to-zoom, info bar, anti-AFK (client/utility.lua).
local UIS = game:GetService("UserInputService")
local Utility = __import("client/utility")

return function(ctx)
	local win, safe, cycle = ctx.win, ctx.safe, ctx.cycle
	local tUtil = win:Tab("Utility", { Section = "Game", Icon = 21 })
	local mFov = tUtil:Module({ Name = "Field of view", Default = false, Callback = function(on) Utility.Fov = on end })
	mFov:Slider({ Name = "FOV", Min = 40, Max = 120, Step = 1, Default = Utility.FovValue, Callback = function(v) Utility.FovValue = v end })
	local mZoom = tUtil:Module({ Name = "Hold to zoom", Default = true, Hidden = true, Callback = function() end })
	local zoomKey = mZoom:Keybind({ Name = "Zoom key", Default = Utility.ZoomKey, Callback = function(k) if k then Utility.ZoomKey = k end end })
	mZoom:Slider({ Name = "Zoom FOV", Min = 8, Max = 60, Step = 1, Default = Utility.ZoomFov, Callback = function(v) Utility.ZoomFov = v end })
	local mBar = tUtil:Module({ Name = "Info bar", Default = false, Callback = function(on) Utility.SetBar(on) end })
	mBar:Toggle({ Name = "FPS", Default = true, Callback = function(v) Utility.BarParts.Fps = v end })
	mBar:Toggle({ Name = "Ping", Default = true, Callback = function(v) Utility.BarParts.Ping = v end })
	mBar:Toggle({ Name = "Players", Default = true, Callback = function(v) Utility.BarParts.Players = v end })
	mBar:Toggle({ Name = "Police online", Default = true, Callback = function(v) Utility.BarParts.Police = v end })
	mBar:Toggle({ Name = "Clock", Default = true, Callback = function(v) Utility.BarParts.Clock = v end })
	local mAfk = tUtil:Module({ Name = "Anti AFK", Default = true, Hidden = true, Callback = function(on) Utility.AntiAfk = on end })
	safe("utility", Utility.Start)

end
