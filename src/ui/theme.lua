-- UI theme: the colour tokens every part of the window is drawn with, and the maths that turns two picked colours (accent, background)
-- into a whole palette. ui/window.lua applies a palette (every bound colour is recomputed).
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local function pickFont(n, fb) local ok, f = pcall(function() return Enum.Font[n] end); return (ok and f) or fb end
local T = {
	-- v6 "Mocha": warm espresso surfaces, cream text, a soft latte-cream accent
	bg = Color3.fromRGB(16, 14, 13),
	side = Color3.fromRGB(21, 19, 17),
	panel = Color3.fromRGB(25, 22, 20),
	elem = Color3.fromRGB(35, 31, 28),
	hover = Color3.fromRGB(44, 39, 35),
	stroke = Color3.fromRGB(40, 36, 32),
	text = Color3.fromRGB(245, 239, 229),
	sub = Color3.fromRGB(172, 162, 150),
	dim = Color3.fromRGB(114, 106, 97),
	accent = Color3.fromRGB(236, 211, 172),
	accentDim = Color3.fromRGB(52, 45, 37),
	off = Color3.fromRGB(62, 56, 50),
	chip = Color3.fromRGB(247, 233, 209),
	gradA = Color3.fromRGB(214, 176, 128),
	gradB = Color3.fromRGB(247, 230, 202),
	strokeOn = Color3.fromRGB(104, 88, 68),
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
