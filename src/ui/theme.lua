-- UI theme: the colour tokens every part of the window is drawn with, and the maths that turns two picked colours (accent, background)
-- into a whole palette. ui/window.lua applies a palette (every bound colour is recomputed).
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local function pickFont(n, fb) local ok, f = pcall(function() return Enum.Font[n] end); return (ok and f) or fb end
local T = {
	-- v5 "Frost": graphite surfaces with a cool mint-aqua accent
	bg = Color3.fromRGB(10, 11, 13),
	side = Color3.fromRGB(15, 16, 19),
	panel = Color3.fromRGB(18, 19, 23),
	elem = Color3.fromRGB(26, 28, 33),
	hover = Color3.fromRGB(33, 35, 41),
	stroke = Color3.fromRGB(30, 32, 38),
	text = Color3.fromRGB(241, 243, 247),
	sub = Color3.fromRGB(148, 153, 166),
	dim = Color3.fromRGB(96, 101, 114),
	accent = Color3.fromRGB(72, 220, 196),
	accentDim = Color3.fromRGB(19, 45, 44),
	off = Color3.fromRGB(46, 49, 57),
	chip = Color3.fromRGB(160, 240, 226),
	gradA = Color3.fromRGB(52, 176, 210),
	gradB = Color3.fromRGB(110, 236, 190),
	strokeOn = Color3.fromRGB(36, 104, 96),
	font = pickFont("BuilderSansMedium", Enum.Font.Gotham),
	bold = pickFont("BuilderSansBold", Enum.Font.GothamBold),
	semi = pickFont("BuilderSansBold", Enum.Font.GothamBold),
}

local Theme = { T = T }
local PALETTE_KEYS = { "accent", "accentDim", "chip", "gradA", "gradB", "strokeOn", "bg", "side", "panel", "elem", "hover", "stroke", "off", "dim" }
local function lift(c, d) return Color3.fromRGB(math.clamp(c.R * 255 + d, 0, 255), math.clamp(c.G * 255 + d, 0, 255), math.clamp(c.B * 255 + d, 0, 255)) end
local DEFAULT_P = {}
for _, k in ipairs(PALETTE_KEYS) do DEFAULT_P[k] = T[k] end
local curP = {}
for k, v in pairs(DEFAULT_P) do curP[k] = v end

-- every colour of the theme derived from two picked colours
function Theme.Palette(accent, bg)
	if not accent and not bg then return DEFAULT_P end
	accent, bg = accent or DEFAULT_P.accent, bg or DEFAULT_P.bg
	return {
		accent = accent, accentDim = bg:Lerp(accent, .16), chip = accent:Lerp(WHITE, .45), gradA = accent:Lerp(BLACK, .15),
		gradB = accent:Lerp(WHITE, .3), strokeOn = bg:Lerp(accent, .42),
		bg = bg, side = lift(bg, 3), panel = lift(bg, 7), elem = lift(bg, 15), hover = lift(bg, 22), stroke = lift(bg, 21), off = lift(bg, 40), dim = lift(bg, 80),
	}
end

local function ckey(c) return math.floor(c.R * 255 + .5) .. "," .. math.floor(c.G * 255 + .5) .. "," .. math.floor(c.B * 255 + .5) end

-- recolour everything under root whose colour is a key of map (key -> new Color3); used for the HUD pieces outside the window
function Theme.Remap(root, map)
	local function fix(c) return map[ckey(c)] end
	local function visit(o)
		pcall(function()
			if o:IsA("GuiObject") then
				local n = fix(o.BackgroundColor3); if n then o.BackgroundColor3 = n end
				if o:IsA("ImageLabel") or o:IsA("ImageButton") then local ic = fix(o.ImageColor3); if ic then o.ImageColor3 = ic end end
				if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then local t = fix(o.TextColor3); if t then o.TextColor3 = t end end
			elseif o:IsA("UIStroke") then
				local n = fix(o.Color); if n then o.Color = n end
			end
		end)
	end
	visit(root)
	for _, o in ipairs(root:GetDescendants()) do visit(o) end
end

function Theme.PaletteMap(old, new_)
	local map = {}
	for _, k in ipairs(PALETTE_KEYS) do
		if old[k] and new_[k] and ckey(old[k]) ~= ckey(new_[k]) then map[ckey(old[k])] = new_[k] end
	end
	return map
end

Theme.KEYS, Theme.cur = PALETTE_KEYS, curP
return Theme
