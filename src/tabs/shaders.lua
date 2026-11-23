-- Shaders tab: colour grading presets, bloom, sun rays, depth of field, haze (time of day is on the Player tab).
local UIS = game:GetService("UserInputService")
local Shaders = __import("visuals/shaders")

return function(ctx)
	local win, safe, cycle = ctx.win, ctx.safe, ctx.cycle
	local tShade = win:Tab("Shaders", { Section = "Game", Icon = 20 })
	local mShade = tShade:Module({ Name = "Shader look", Default = false, Callback = function(on) Shaders.SetEnabled(on) end })
	cycle(mShade, "Preset", Shaders.Presets, function() return Shaders.Preset end, function(v) Shaders.Preset = v; Shaders.Apply() end)
	mShade:Slider({ Name = "Strength", Min = 0, Max = 1.5, Step = 0.05, Default = Shaders.Intensity, Callback = function(v) Shaders.Intensity = v; Shaders.Apply() end })
	mShade:Slider({ Name = "Exposure", Min = -1, Max = 1, Step = 0.05, Default = Shaders.Exposure, Callback = function(v) Shaders.Exposure = v; Shaders.Apply() end })
	mShade:Toggle({ Name = "Bloom glow", Default = Shaders.Bloom, Callback = function(v) Shaders.Bloom = v; Shaders.Apply() end })
	mShade:Toggle({ Name = "Sun rays", Default = Shaders.Rays, Callback = function(v) Shaders.Rays = v; Shaders.Apply() end })
	mShade:Toggle({ Name = "Depth of field (soft far blur)", Default = Shaders.DoF, Callback = function(v) Shaders.DoF = v; Shaders.Apply() end })
	mShade:Toggle({ Name = "Haze (colours the distance)", Default = Shaders.Haze, Callback = function(v) Shaders.Haze = v; Shaders.Apply() end })

end
