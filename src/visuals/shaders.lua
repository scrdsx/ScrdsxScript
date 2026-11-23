-- Shaders: colour grading, bloom, sun rays, depth of field and haze presets built from Roblox's own post effects (client-side, only you see them).
-- Pick a preset, then scale it with Intensity; the time of day can be pinned too. Everything is removed again when turned off or unloaded.
local Lighting = game:GetService("Lighting")

local Shaders = { Enabled = false, Preset = "Cinematic", Intensity = 1, Bloom = true, Rays = true, DoF = false, Haze = true, PinTime = false, Time = 17, Exposure = 0 }
Shaders.Presets = { "Cinematic", "Vivid", "Golden hour", "Synthwave", "Noir", "Arctic", "Dream", "Toxic", "Sunset glow" }

local function C(r, g, b) return Color3.fromRGB(r, g, b) end
local WHITE = C(255, 255, 255)
-- cc = ColorCorrection, bl = Bloom (Intensity, Size, Threshold), sr = SunRays, dof = DepthOfField, ex = exposure, hz = Atmosphere haze (Density, Haze, Color)
local P = {
	["Cinematic"]   = { cc = { b = -0.02, c = 0.14, s = 0.06, t = C(255, 244, 232) }, bl = { 0.45, 28, 1.0 }, sr = { 0.1, 0.55 }, dof = { 0.12, 90, 60 }, ex = 0.0, hz = { 0.32, 0.9, C(190, 200, 215) } },
	["Vivid"]       = { cc = { b = 0.0, c = 0.12, s = 0.42, t = WHITE }, bl = { 0.35, 24, 1.1 }, sr = { 0.08, 0.5 }, dof = { 0.0, 90, 60 }, ex = 0.05, hz = { 0.25, 0.4, C(180, 205, 235) } },
	["Golden hour"] = { cc = { b = 0.02, c = 0.12, s = 0.22, t = C(255, 214, 168) }, bl = { 0.6, 30, 0.95 }, sr = { 0.28, 0.7 }, dof = { 0.0, 90, 60 }, ex = 0.12, hz = { 0.36, 1.4, C(255, 196, 140) } },
	["Synthwave"]   = { cc = { b = -0.03, c = 0.22, s = 0.35, t = C(255, 200, 255) }, bl = { 1.1, 40, 0.8 }, sr = { 0.0, 0.5 }, dof = { 0.0, 90, 60 }, ex = -0.05, hz = { 0.4, 1.8, C(200, 90, 255) } },
	["Noir"]        = { cc = { b = -0.04, c = 0.3, s = -1.0, t = C(235, 238, 245) }, bl = { 0.25, 24, 1.1 }, sr = { 0.05, 0.4 }, dof = { 0.0, 90, 60 }, ex = -0.05, hz = { 0.3, 0.7, C(150, 150, 160) } },
	["Arctic"]      = { cc = { b = 0.02, c = 0.1, s = -0.18, t = C(205, 228, 255) }, bl = { 0.4, 26, 1.0 }, sr = { 0.1, 0.5 }, dof = { 0.0, 90, 60 }, ex = 0.06, hz = { 0.38, 1.1, C(190, 215, 245) } },
	["Dream"]       = { cc = { b = 0.05, c = -0.04, s = 0.2, t = C(255, 232, 250) }, bl = { 1.4, 46, 0.75 }, sr = { 0.18, 0.8 }, dof = { 0.25, 70, 40 }, ex = 0.1, hz = { 0.4, 1.2, C(255, 215, 240) } },
	["Toxic"]       = { cc = { b = -0.04, c = 0.2, s = 0.3, t = C(205, 255, 205) }, bl = { 0.7, 32, 0.9 }, sr = { 0.0, 0.5 }, dof = { 0.0, 90, 60 }, ex = -0.03, hz = { 0.4, 1.6, C(120, 230, 120) } },
	["Sunset glow"] = { cc = { b = 0.0, c = 0.16, s = 0.3, t = C(255, 190, 170) }, bl = { 0.8, 34, 0.9 }, sr = { 0.3, 0.75 }, dof = { 0.0, 90, 60 }, ex = 0.04, hz = { 0.38, 1.5, C(255, 150, 120) } },
}

local inst = {}          -- our effect instances
local orig                -- original Lighting values, restored on disable
local atmOrig, atmMade
local loop

local function lerp(a, b, t) return a + (b - a) * t end
local function lerpC(a, b, t) return a:Lerp(b, t) end

local function ensure(class, name)
	local o = inst[name]
	if o and o.Parent then return o end
	o = Instance.new(class)
	o.Name = "ScrdsxShader" .. name
	o.Parent = Lighting
	inst[name] = o
	return o
end

local function saveOrig()
	if orig then return end
	orig = { ClockTime = Lighting.ClockTime, ExposureCompensation = Lighting.ExposureCompensation }
end

local function atmosphere()
	local a = Lighting:FindFirstChildOfClass("Atmosphere")
	if a and not atmMade then
		if not atmOrig then atmOrig = { a = a, Density = a.Density, Haze = a.Haze, Color = a.Color, Decay = a.Decay, Glare = a.Glare, Offset = a.Offset } end
		return a
	end
	if not a then
		a = Instance.new("Atmosphere"); a.Name = "ScrdsxShaderAtm"; a.Parent = Lighting; atmMade = a
	end
	return a
end

function Shaders.Apply()
	if not Shaders.Enabled then return end
	local pr = P[Shaders.Preset] or P.Cinematic
	local k = math.clamp(Shaders.Intensity, 0, 1.5)
	saveOrig()
	local cc = ensure("ColorCorrectionEffect", "CC")
	cc.Enabled = true
	cc.Brightness = pr.cc.b * k
	cc.Contrast = pr.cc.c * k
	cc.Saturation = pr.cc.s * k
	cc.TintColor = lerpC(WHITE, pr.cc.t, math.clamp(k, 0, 1))

	local bl = ensure("BloomEffect", "Bloom")
	bl.Enabled = Shaders.Bloom
	bl.Intensity = pr.bl[1] * k; bl.Size = pr.bl[2]; bl.Threshold = pr.bl[3]

	local sr = ensure("SunRaysEffect", "Rays")
	sr.Enabled = Shaders.Rays and pr.sr[1] > 0
	sr.Intensity = pr.sr[1] * k; sr.Spread = pr.sr[2]

	local d = ensure("DepthOfFieldEffect", "DoF")
	d.Enabled = Shaders.DoF
	d.FarIntensity = math.max(pr.dof[1], 0.15) * k; d.NearIntensity = 0; d.FocusDistance = 90; d.InFocusRadius = 60

	pcall(function() Lighting.ExposureCompensation = (orig.ExposureCompensation or 0) + (pr.ex + Shaders.Exposure) * k end)

	if Shaders.Haze then
		local a = atmosphere()
		if a then
			pcall(function()
				a.Density = lerp(atmOrig and atmOrig.Density or 0.3, pr.hz[1], math.clamp(k, 0, 1))
				a.Haze = lerp(atmOrig and atmOrig.Haze or 0, pr.hz[2], math.clamp(k, 0, 1))
				a.Color = lerpC(atmOrig and atmOrig.Color or pr.hz[3], pr.hz[3], math.clamp(k, 0, 1))
			end)
		end
	end
	if Shaders.PinTime then pcall(function() Lighting.ClockTime = Shaders.Time end) end
end

local function restore()
	for _, o in pairs(inst) do pcall(function() o:Destroy() end) end
	inst = {}
	if atmMade then pcall(function() atmMade:Destroy() end); atmMade = nil end
	if atmOrig then
		pcall(function()
			local a = atmOrig.a
			a.Density, a.Haze, a.Color = atmOrig.Density, atmOrig.Haze, atmOrig.Color
		end)
		atmOrig = nil
	end
	if orig then pcall(function() Lighting.ExposureCompensation = orig.ExposureCompensation; if Shaders.PinTime then Lighting.ClockTime = orig.ClockTime end end); orig = nil end
end

function Shaders.SetEnabled(v)
	Shaders.Enabled = v
	if v then
		Shaders.Apply()
		if not loop then
			loop = task.spawn(function()
				while Shaders.Enabled do
					task.wait(1) -- the game can reset its own lighting; put ours back
					pcall(Shaders.Apply)
				end
				loop = nil
			end)
		end
	else
		restore()
	end
end

function Shaders.Destroy()
	Shaders.Enabled = false
	restore()
end

return Shaders
