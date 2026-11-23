-- Crosshair tab.
local UIS = game:GetService("UserInputService")
local Crosshair = __import("combat/crosshair")

return function(ctx)
	local win, safe, cycle = ctx.win, ctx.safe, ctx.cycle
	local tCross = win:Tab("Crosshair", { Section = "Combat", Icon = 17 })
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

end
