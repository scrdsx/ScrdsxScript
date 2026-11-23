-- FPS: client-side optimisations. Each option changes only what YOUR game draws and remembers the original value, so turning it off puts everything back.
-- Most of them are things you will not notice while playing (post effects, water waves, mesh detail, light settings); the strong ones (shadows,
-- particles, graphics level) are separate switches.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local lp = Players.LocalPlayer

local FPS = {
	Effects = false, Lighting = false, Terrain = false, MeshDetail = false, Shadows = false, Particles = false, Quality = false, QualityLevel = 4,
	Unlock = false, CapValue = 240, Fps = 0, Low = 0, Info = "ready",
}

local orig = setmetatable({}, { __mode = "k" }) -- instance -> { property = original value }
local saved = {}                                 -- singletons (Lighting, Terrain, settings)
local conns = {}

local EFFECTS = { BloomEffect = true, BlurEffect = true, SunRaysEffect = true, DepthOfFieldEffect = true }
local EMITTERS = { ParticleEmitter = true, Trail = true, Beam = true, Smoke = true, Fire = true, Sparkles = true }
local LIGHTS = { PointLight = true, SpotLight = true, SurfaceLight = true }

local function remember(inst, prop)
	local t = orig[inst]
	if not t then t = {}; orig[inst] = t end
	if t[prop] == nil then t[prop] = inst[prop] end
end

local function setProp(inst, prop, value)
	pcall(function()
		remember(inst, prop)
		inst[prop] = value
	end)
end

local function restoreInst(inst, props)
	local t = orig[inst]
	if not t then return end
	for _, prop in ipairs(props) do
		if t[prop] ~= nil then pcall(function() inst[prop] = t[prop] end); t[prop] = nil end
	end
end

-- walk a big tree without freezing the game: a slice per frame
local function sliced(root, fn)
	local list
	local ok = pcall(function() list = root:GetDescendants() end)
	if not ok then return end
	local n = 0
	for _, d in ipairs(list) do
		pcall(fn, d)
		n = n + 1
		if n % 2500 == 0 then task.wait() end
	end
end

local function eachWorld(fn)
	task.spawn(function()
		sliced(workspace, fn)
		sliced(Lighting, fn)
		local cam = workspace.CurrentCamera
		if cam then sliced(cam, fn) end
	end)
end

-- EFFECTS: bloom, blur, sun rays, depth of field ------------------------------------------------------------------------
local function effectOff(d) if EFFECTS[d.ClassName] and d.Name ~= "ScrdsxGlass" and not d.Name:find("^ScrdsxShader") then setProp(d, "Enabled", false) end end
local function effectOn(d) if EFFECTS[d.ClassName] then restoreInst(d, { "Enabled" }) end end
function FPS.SetEffects(v)
	FPS.Effects = v
	if FPS._watch then FPS._watch() end
	eachWorld(v and effectOff or effectOn)
end

-- LIGHTING: cheaper environment lighting (barely visible) ---------------------------------------------------------------
function FPS.SetLighting(v)
	FPS.Lighting = v
	pcall(function()
		if v then
			saved.light = saved.light or { spec = Lighting.EnvironmentSpecularScale, diff = Lighting.EnvironmentDiffuseScale, soft = Lighting.ShadowSoftness }
			Lighting.EnvironmentSpecularScale = 0
			Lighting.ShadowSoftness = 0
		elseif saved.light then
			Lighting.EnvironmentSpecularScale = saved.light.spec
			Lighting.ShadowSoftness = saved.light.soft
			saved.light = nil
		end
	end)
end

-- TERRAIN: grass decoration, water waves and reflections ------------------------------------------------------------------
function FPS.SetTerrain(v)
	FPS.Terrain = v
	pcall(function()
		local t = workspace.Terrain
		if v then
			saved.terrain = saved.terrain or { dec = t.Decoration, size = t.WaterWaveSize, speed = t.WaterWaveSpeed, refl = t.WaterReflectance }
			t.Decoration = false
			t.WaterWaveSize = 0
			t.WaterWaveSpeed = 0
			t.WaterReflectance = 0
		elseif saved.terrain then
			t.Decoration, t.WaterWaveSize, t.WaterWaveSpeed, t.WaterReflectance = saved.terrain.dec, saved.terrain.size, saved.terrain.speed, saved.terrain.refl
			saved.terrain = nil
		end
	end)
end

-- MESH DETAIL: lower level of detail for every mesh ----------------------------------------------------------------------
local function meshLow(d) if d:IsA("MeshPart") then setProp(d, "RenderFidelity", Enum.RenderFidelity.Performance) end end
local function meshBack(d) if d:IsA("MeshPart") then restoreInst(d, { "RenderFidelity" }) end end
function FPS.SetMeshDetail(v)
	FPS.MeshDetail = v
	if FPS._watch then FPS._watch() end
	pcall(function()
		local r = settings().Rendering
		if v then
			saved.mesh = saved.mesh or r.MeshPartDetailLevel
			r.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level01
		elseif saved.mesh then
			r.MeshPartDetailLevel = saved.mesh
			saved.mesh = nil
		end
	end)
	task.spawn(function() sliced(workspace, v and meshLow or meshBack) end)
end

-- SHADOWS: the biggest single saving, but the world looks flatter ----------------------------------------------------------
local function lightOff(d) if LIGHTS[d.ClassName] then setProp(d, "Shadows", false) end end
local function lightOn(d) if LIGHTS[d.ClassName] then restoreInst(d, { "Shadows" }) end end
function FPS.SetShadows(v)
	FPS.Shadows = v
	if FPS._watch then FPS._watch() end
	pcall(function()
		if v then
			if saved.shadows == nil then saved.shadows = Lighting.GlobalShadows end
			Lighting.GlobalShadows = false
		elseif saved.shadows ~= nil then
			Lighting.GlobalShadows = saved.shadows
			saved.shadows = nil
		end
	end)
	eachWorld(v and lightOff or lightOn)
end

-- PARTICLES: smoke, fire, sparks, trails, beams ------------------------------------------------------------------------------
local function emitOff(d) if EMITTERS[d.ClassName] then setProp(d, "Enabled", false) end end
local function emitOn(d) if EMITTERS[d.ClassName] then restoreInst(d, { "Enabled" }) end end
function FPS.SetParticles(v)
	FPS.Particles = v
	if FPS._watch then FPS._watch() end
	eachWorld(v and emitOff or emitOn)
end

-- GRAPHICS LEVEL ---------------------------------------------------------------------------------------------------------------
function FPS.SetQuality(v)
	FPS.Quality = v
	pcall(function()
		local r = settings().Rendering
		if v then
			saved.quality = saved.quality or r.QualityLevel
			r.QualityLevel = Enum.QualityLevel["Level" .. string.format("%02d", math.clamp(math.floor(FPS.QualityLevel), 1, 21))]
		elseif saved.quality then
			r.QualityLevel = saved.quality
			saved.quality = nil
		end
	end)
end
function FPS.SetQualityLevel(n)
	FPS.QualityLevel = n
	if FPS.Quality then FPS.SetQuality(true) end
end

-- FPS LIMIT ---------------------------------------------------------------------------------------------------------------------
function FPS.SetUnlock(v)
	FPS.Unlock = v
	pcall(function()
		if setfpscap then setfpscap(v and FPS.CapValue or 60) end
	end)
end
function FPS.SetCap(n)
	FPS.CapValue = n
	if FPS.Unlock then FPS.SetUnlock(true) end
end

-- presets -----------------------------------------------------------------------------------------------------------------------
function FPS.Preset(name)
	local invisible = { Effects = true, Lighting = true, Terrain = true, MeshDetail = true }
	local max = { Effects = true, Lighting = true, Terrain = true, MeshDetail = true, Shadows = true, Particles = true }
	local set = name == "max" and max or invisible
	for _, k in ipairs({ "Effects", "Lighting", "Terrain", "MeshDetail", "Shadows", "Particles" }) do
		FPS["Set" .. k](set[k] == true)
	end
end

function FPS.AllOff()
	for _, k in ipairs({ "Effects", "Lighting", "Terrain", "MeshDetail", "Shadows", "Particles", "Quality" }) do
		FPS["Set" .. k](false)
	end
end

-- new objects that appear while an option is on (cars, effects, streamed map) are handled as they arrive
local onAdded
local function watch()
	local need = FPS.Effects or FPS.Particles or FPS.Shadows or FPS.MeshDetail
	if need and not conns.added then
		conns.added = workspace.DescendantAdded:Connect(function(d) pcall(onAdded, d) end)
		conns.lightAdded = Lighting.DescendantAdded:Connect(function(d) pcall(onAdded, d) end)
	elseif not need and conns.added then
		conns.added:Disconnect(); conns.lightAdded:Disconnect()
		conns.added, conns.lightAdded = nil, nil
	end
end
FPS._watch = watch

function onAdded(d)
	if FPS.Effects and EFFECTS[d.ClassName] then setProp(d, "Enabled", false)
	elseif FPS.Particles and EMITTERS[d.ClassName] then setProp(d, "Enabled", false)
	elseif FPS.Shadows and LIGHTS[d.ClassName] then setProp(d, "Shadows", false)
	elseif FPS.MeshDetail and d:IsA("MeshPart") then setProp(d, "RenderFidelity", Enum.RenderFidelity.Performance) end
end

function FPS.Start()
	FPS.Info = "ready"
end

function FPS.Destroy()
	for _, c in pairs(conns) do pcall(function() c:Disconnect() end) end
	conns = {}
	FPS.AllOff()
	pcall(function() if setfpscap and FPS.Unlock then setfpscap(60) end end)
	FPS.Unlock = false
end

return FPS
