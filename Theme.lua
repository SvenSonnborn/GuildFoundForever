local addonName, ns = ...
local L = ns.L

-- Two looks for the addon's windows (docs/specs/2026-10-22-stile.md). "classic" keeps Blizzard's
-- templates and fonts; "modern" draws flat dark panels with 1 px borders, Arial Narrow and one gold
-- accent (palette "Glut"). Every widget is skinned once through a Skin* function and follows each
-- later switch without a /reload: the template's own art turns invisible (never removed, so a
-- template that shows a texture again changes nothing), the flat parts are textures of our own.
-- The style is account-wide (ns.db.style); STYLE_CHANGED fires after a switch.
local Theme = {}
ns.Theme = Theme

local WHITE = "Interface\\Buttons\\WHITE8X8"
local TOOLTIP_BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"
local MODERN_FONT = "Fonts\\ARIALN.TTF"
-- Arial Narrow lacks these clients' characters; they keep their own font in the modern style too.
local NO_ARIAL_NARROW = { koKR = true, zhCN = true, zhTW = true, ruRU = true }
local STYLES = { classic = true, modern = true }

-- Colours by role. Classic: the dark banner look of the message window; modern: palette "Glut".
local COLORS = {
	classic = {
		window = { 0.04, 0.04, 0.06, 0.94 },
		windowBorder = { 0.85, 0.68, 0.2, 1 },
		panel = { 0, 0, 0, 0.35 },
		panelBorder = { 0.35, 0.3, 0.2, 0.8 },
		button = { 0.1, 0.09, 0.07, 0.9 },
		buttonBorder = { 0.45, 0.38, 0.22, 0.9 },
		selectedBorder = { 0.85, 0.68, 0.2, 1 },
		accent = { 1, 0.82, 0, 1 },
		muted = { 0.6, 0.6, 0.6, 1 },
		bar = { 0.478, 0.416, 0.290, 1 },
	},
	modern = {
		window = { 0.071, 0.063, 0.063, 0.97 },
		windowBorder = { 0.227, 0.192, 0.161, 1 },
		title = { 0.094, 0.082, 0.071, 1 },
		line = { 0.165, 0.141, 0.118, 1 },
		panel = { 0.094, 0.082, 0.071, 1 },
		panelBorder = { 0.165, 0.141, 0.118, 1 },
		button = { 0.122, 0.106, 0.090, 1 },
		buttonHover = { 0.165, 0.141, 0.118, 1 },
		buttonBorder = { 0.227, 0.192, 0.161, 1 },
		selectedBorder = { 0.886, 0.639, 0.231, 1 },
		input = { 0.055, 0.047, 0.039, 1 },
		box = { 0.353, 0.310, 0.263, 1 },
		bar = { 0.353, 0.310, 0.263, 1 },
		text = { 0.925, 0.902, 0.863, 1 },
		muted = { 0.561, 0.522, 0.471, 1 },
		accent = { 0.886, 0.639, 0.231, 1 },
		onAccent = { 0.071, 0.063, 0.063, 1 },
	},
}

-- The addon's font objects: classic copies Blizzard's, modern sets Arial Narrow at these sizes in
-- these colours.
local FONTS = {
	{ key = "Normal", blizzard = "GameFontNormal", size = 14, color = "accent" },
	{ key = "Highlight", blizzard = "GameFontHighlight", size = 13, color = "text" },
	{ key = "Disable", blizzard = "GameFontDisable", size = 13, color = "muted" },
	{ key = "NormalSmall", blizzard = "GameFontNormalSmall", size = 12, color = "accent" },
	{ key = "HighlightSmall", blizzard = "GameFontHighlightSmall", size = 12, color = "text" },
	{ key = "DisableSmall", blizzard = "GameFontDisableSmall", size = 12, color = "muted" },
	{ key = "NormalLarge", blizzard = "GameFontNormalLarge", size = 17, color = "accent" },
	{ key = "Huge", blizzard = "GameFontNormalHuge", size = 28, color = "text" },
	{ key = "OnAccent", blizzard = "GameFontNormal", size = 13, color = "onAccent" },
}
Theme.Fonts = {}
for _, font in ipairs(FONTS) do
	local name = addonName .. "Font" .. font.key
	font.object = CreateFont(name)
	Theme.Fonts[font.key] = name
end

-- Blizzard's textures of UICheckButtonTemplate, set again when a check box returns to classic.
local CHECK_TEXTURES = {
	Normal = "Interface\\Buttons\\UI-CheckBox-Up",
	Pushed = "Interface\\Buttons\\UI-CheckBox-Down",
	Highlight = "Interface\\Buttons\\UI-CheckBox-Highlight",
	Checked = "Interface\\Buttons\\UI-CheckBox-Check",
	DisabledChecked = "Interface\\Buttons\\UI-CheckBox-Check-Disabled",
}

local skins = {} -- apply(style) of every skinned widget

function Theme.Get()
	local style = ns.db and ns.db.style
	return STYLES[style] and style or "classic"
end

function Theme.IsModern()
	return Theme.Get() == "modern"
end

-- The colour of a role in the current style; roles only the modern style has fall back to it.
function Theme.Color(role)
	return COLORS[Theme.Get()][role] or COLORS.modern[role]
end

local function ApplyFonts(style)
	local arialNarrow = style == "modern" and not NO_ARIAL_NARROW[GetLocale()]
	for _, font in ipairs(FONTS) do
		font.object:CopyFontObject(_G[font.blizzard])
		if style == "modern" then
			if arialNarrow then
				font.object:SetFont(MODERN_FONT, font.size, "")
			end
			local c = COLORS.modern[font.color]
			font.object:SetTextColor(c[1], c[2], c[3])
		end
	end
end

-- Usable before the saved style is known (INIT).
ApplyFonts("classic")

local function Apply()
	local style = Theme.Get()
	ApplyFonts(style)
	for _, apply in ipairs(skins) do
		apply(style)
	end
end

-- Switches to "classic" or "modern"; anything else is ignored.
function Theme.Set(style)
	if not STYLES[style] or not ns.db then
		return false
	end
	if style ~= Theme.Get() then
		ns.db.style = style
		Apply()
		ns.Fire("STYLE_CHANGED", style)
	end
	return true
end

function Theme.Toggle()
	return Theme.Set(Theme.IsModern() and "classic" or "modern")
end

local function Register(apply)
	skins[#skins + 1] = apply
	apply(Theme.Get())
end

ns.RegisterCallback("INIT", Apply)

---------------------------------------------------------------------------
-- Parts
---------------------------------------------------------------------------

local function Flat(parent, layer, sublevel, color)
	local texture = parent:CreateTexture(nil, layer, nil, sublevel)
	texture:SetTexture(WHITE)
	if color then
		texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
	end
	return texture
end

-- Four 1 px lines along the widget's edges.
local function Border(parent, color)
	local top, bottom, left, right = Flat(parent, "BORDER", 7, color), Flat(parent, "BORDER", 7, color), Flat(parent, "BORDER", 7, color), Flat(parent, "BORDER", 7, color)
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	top:SetHeight(1)
	bottom:SetPoint("BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT")
	bottom:SetHeight(1)
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")
	left:SetWidth(1)
	right:SetPoint("TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT")
	right:SetWidth(1)
	return { top, bottom, left, right }
end

local function SetShown(list, shown)
	for _, region in ipairs(list) do
		region:SetShown(shown)
	end
end

-- The template's own art: its textures so far, its button state textures and the frames some
-- templates add for it (NineSlice, Inset).
local function TemplateArt(widget)
	local art = {}
	for _, region in ipairs({ widget:GetRegions() }) do
		if region:GetObjectType() == "Texture" then
			art[#art + 1] = region
		end
	end
	for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
		local texture = widget[getter] and widget[getter](widget)
		if texture then
			art[#art + 1] = texture
		end
	end
	for _, key in ipairs({ "NineSlice", "Inset" }) do
		if type(widget[key]) == "table" and widget[key].SetAlpha then
			art[#art + 1] = widget[key]
		end
	end
	return art
end

local function ShowArt(art, shown)
	for _, region in ipairs(art) do
		region:SetAlpha(shown and 1 or 0)
	end
end

---------------------------------------------------------------------------
-- Skins
---------------------------------------------------------------------------

-- Blizzard's red close button; modern: a plain "×".
function Theme.SkinCloseButton(button)
	local art = TemplateArt(button)
	local skin = { cross = button:CreateFontString(nil, "OVERLAY", Theme.Fonts.Highlight) }
	button.skin = skin
	skin.cross:SetPoint("CENTER", 0, 1)
	skin.cross:SetText("×")
	Register(function(style)
		local modern = style == "modern"
		ShowArt(art, not modern)
		skin.cross:SetShown(modern)
	end)
end

-- A window made from BasicFrameTemplateWithInset; modern: flat background, a title strip with a
-- line under it, a 1 px frame and the title on the left after an accent square.
local TITLE_HEIGHT = 24
function Theme.SkinWindow(frame, title)
	local art = TemplateArt(frame)
	local c = COLORS.modern
	local skin = {
		bg = Flat(frame, "BACKGROUND", -8, c.window),
		title = Flat(frame, "BACKGROUND", -7, c.title),
		titleLine = Flat(frame, "BORDER", 0, c.line),
		mark = Flat(frame, "ARTWORK", 0, c.accent),
		border = Border(frame, c.windowBorder),
	}
	frame.skin = skin
	skin.bg:SetAllPoints()
	skin.title:SetPoint("TOPLEFT")
	skin.title:SetPoint("TOPRIGHT")
	skin.title:SetHeight(TITLE_HEIGHT)
	skin.titleLine:SetPoint("TOPLEFT", 0, -TITLE_HEIGHT)
	skin.titleLine:SetPoint("TOPRIGHT", 0, -TITLE_HEIGHT)
	skin.titleLine:SetHeight(1)
	skin.mark:SetSize(8, 8)
	skin.mark:SetPoint("TOPLEFT", 12, -8)
	if frame.CloseButton then
		Theme.SkinCloseButton(frame.CloseButton)
	end
	Register(function(style)
		local modern = style == "modern"
		ShowArt(art, not modern)
		SetShown({ skin.bg, skin.title, skin.titleLine, skin.mark }, modern)
		SetShown(skin.border, modern)
		if title then
			title:ClearAllPoints()
			if modern then
				title:SetPoint("TOPLEFT", 26, -6)
			else
				title:SetPoint("TOP", 0, -5)
			end
		end
	end)
end

-- A UIPanelButtonTemplate button; modern: a flat surface with a frame, lighter under the mouse.
-- kind "primary": filled with the accent colour.
function Theme.SkinButton(button, kind)
	local art = TemplateArt(button)
	local c = COLORS.modern
	local primary = kind == "primary"
	local normal = primary and c.accent or c.button
	local skin = { bg = Flat(button, "BACKGROUND", 1, normal), border = Border(button, primary and c.accent or c.buttonBorder) }
	button.skin = skin
	skin.bg:SetAllPoints()
	button:HookScript("OnEnter", function()
		if Theme.IsModern() and not primary then
			skin.bg:SetVertexColor(c.buttonHover[1], c.buttonHover[2], c.buttonHover[3], 1)
		end
	end)
	button:HookScript("OnLeave", function()
		skin.bg:SetVertexColor(normal[1], normal[2], normal[3], 1)
	end)
	Register(function(style)
		local modern = style == "modern"
		ShowArt(art, not modern)
		skin.bg:SetShown(modern)
		SetShown(skin.border, modern)
		if modern then
			button:SetNormalFontObject(primary and Theme.Fonts.OnAccent or Theme.Fonts.Highlight)
			button:SetHighlightFontObject(primary and Theme.Fonts.OnAccent or Theme.Fonts.Highlight)
			button:SetDisabledFontObject(Theme.Fonts.Disable)
		else
			button:SetNormalFontObject("GameFontNormal")
			button:SetHighlightFontObject("GameFontHighlight")
			button:SetDisabledFontObject("GameFontDisable")
		end
	end)
end

-- A tab made from a UIPanelButtonTemplate button; modern: just its text, the open tab bright and
-- underlined in the accent colour. Theme.SelectTab marks the open one.
local function ApplyTab(button, style)
	local skin, selected = button.skin, button.skin.selected
	if style == "modern" then
		button:UnlockHighlight()
		skin.line:SetShown(selected)
		local font = selected and Theme.Fonts.Highlight or Theme.Fonts.Disable
		button:SetNormalFontObject(font)
		button:SetHighlightFontObject(Theme.Fonts.Highlight)
	else
		skin.line:Hide()
		if selected then
			button:LockHighlight()
		else
			button:UnlockHighlight()
		end
		button:SetNormalFontObject("GameFontNormal")
		button:SetHighlightFontObject("GameFontHighlight")
	end
end

function Theme.SkinTab(button)
	local art = TemplateArt(button)
	local skin = { line = Flat(button, "ARTWORK", 0, COLORS.modern.accent), selected = false }
	button.skin = skin
	skin.line:SetPoint("BOTTOMLEFT", 8, 0)
	skin.line:SetPoint("BOTTOMRIGHT", -8, 0)
	skin.line:SetHeight(2)
	Register(function(style)
		ShowArt(art, style ~= "modern")
		ApplyTab(button, style)
	end)
end

function Theme.SelectTab(button, selected)
	button.skin.selected = selected and true or false
	ApplyTab(button, Theme.Get())
end

-- A UICheckButtonTemplate check box; modern: a 14 px box with a 1 px frame, checked a filled square
-- in the accent colour. Its state textures change; classic gets Blizzard's files again.
local CHECK_INSETS = { Normal = 5, Pushed = 5, Highlight = 5, Checked = 8, DisabledChecked = 8 }
function Theme.SkinCheckbox(checkbox)
	local c = COLORS.modern
	local modernColors = { Normal = c.box, Pushed = c.box, Highlight = { c.accent[1], c.accent[2], c.accent[3], 0.15 }, Checked = c.accent, DisabledChecked = c.muted }
	local skin = { fill = Flat(checkbox, "BORDER", 0, c.input) }
	checkbox.skin = skin
	skin.fill:SetPoint("TOPLEFT", 6, -6)
	skin.fill:SetPoint("BOTTOMRIGHT", -6, 6)
	local layers = {}
	for state in pairs(CHECK_TEXTURES) do
		local texture = checkbox["Get" .. state .. "Texture"](checkbox)
		layers[state] = texture and texture:GetDrawLayer()
	end
	Register(function(style)
		local modern = style == "modern"
		skin.fill:SetShown(modern)
		for state, file in pairs(CHECK_TEXTURES) do
			checkbox["Set" .. state .. "Texture"](checkbox, modern and WHITE or file)
			local texture = checkbox["Get" .. state .. "Texture"](checkbox)
			if texture then
				texture:ClearAllPoints()
				if modern then
					local inset, color = CHECK_INSETS[state], modernColors[state]
					texture:SetPoint("TOPLEFT", inset, -inset)
					texture:SetPoint("BOTTOMRIGHT", -inset, inset)
					texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
					if state == "Normal" or state == "Pushed" then
						texture:SetDrawLayer("BACKGROUND")
					end
				else
					texture:SetAllPoints()
					texture:SetVertexColor(1, 1, 1, 1)
					if layers[state] then
						texture:SetDrawLayer(layers[state])
					end
				end
			end
		end
	end)
end

-- An InputBoxTemplate edit box; modern: a dark field with a 1 px frame.
function Theme.SkinEditBox(box)
	local art = TemplateArt(box)
	local c = COLORS.modern
	local skin = { bg = Flat(box, "BACKGROUND", 0, c.input), border = {} }
	box.skin = skin
	skin.bg:SetPoint("TOPLEFT", -5, 0)
	skin.bg:SetPoint("BOTTOMRIGHT", 0, 0)
	for i, point in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local line = Flat(box, "BORDER", 7, c.windowBorder)
		line:SetPoint(point[1], skin.bg, point[1])
		line:SetPoint(point[2], skin.bg, point[2])
		if point[3] then
			line:SetHeight(1)
		else
			line:SetWidth(1)
		end
		skin.border[i] = line
	end
	Register(function(style)
		local modern = style == "modern"
		ShowArt(art, not modern)
		skin.bg:SetShown(modern)
		SetShown(skin.border, modern)
		box:SetFontObject(modern and Theme.Fonts.Highlight or "ChatFontNormal")
	end)
end

-- A BackdropTemplate frame in a role ("window", "panel" or "button"); classic: Blizzard's tooltip
-- border in gold tones, modern: flat with a 1 px frame.
local BOX_EDGE = { window = 14, panel = 10, button = 10 }
function Theme.SkinBox(frame, role)
	Register(function(style)
		if style == "modern" then
			frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
		else
			local inset = 3
			frame:SetBackdrop({ bgFile = WHITE, edgeFile = TOOLTIP_BORDER, edgeSize = BOX_EDGE[role], insets = { left = inset, right = inset, top = inset, bottom = inset } })
		end
		local colors = COLORS[style]
		local bg, border = colors[role], colors[role .. "Border"]
		frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
		frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
	end)
end

---------------------------------------------------------------------------
-- The switch in the title bar: "Classic" [track] "Modern"
---------------------------------------------------------------------------

local SWITCH_TRACK_WIDTH, SWITCH_TRACK_HEIGHT, SWITCH_KNOB = 30, 14, 10
local SWITCH_LABEL_WIDTH, SWITCH_GAP = 56, 6

function Theme.CreateSwitch(parent, name)
	local switch = CreateFrame("Button", name, parent)
	switch:SetSize(SWITCH_TRACK_WIDTH + 2 * (SWITCH_LABEL_WIDTH + SWITCH_GAP), 18)
	local track = Flat(switch, "ARTWORK", 0)
	track:SetSize(SWITCH_TRACK_WIDTH, SWITCH_TRACK_HEIGHT)
	track:SetPoint("CENTER")
	local frameLines = {}
	for i = 1, 4 do
		frameLines[i] = Flat(switch, "ARTWORK", 1, { 0.69, 0.55, 0.24, 1 })
	end
	frameLines[1]:SetPoint("TOPLEFT", track)
	frameLines[1]:SetPoint("TOPRIGHT", track)
	frameLines[1]:SetHeight(1)
	frameLines[2]:SetPoint("BOTTOMLEFT", track)
	frameLines[2]:SetPoint("BOTTOMRIGHT", track)
	frameLines[2]:SetHeight(1)
	frameLines[3]:SetPoint("TOPLEFT", track)
	frameLines[3]:SetPoint("BOTTOMLEFT", track)
	frameLines[3]:SetWidth(1)
	frameLines[4]:SetPoint("TOPRIGHT", track)
	frameLines[4]:SetPoint("BOTTOMRIGHT", track)
	frameLines[4]:SetWidth(1)
	local knob = Flat(switch, "OVERLAY", 0)
	knob:SetSize(SWITCH_KNOB, SWITCH_KNOB)
	local classicLabel = switch:CreateFontString(nil, "OVERLAY")
	classicLabel:SetPoint("RIGHT", track, "LEFT", -SWITCH_GAP, 0)
	classicLabel:SetText(L.STYLE_CLASSIC)
	local modernLabel = switch:CreateFontString(nil, "OVERLAY")
	modernLabel:SetPoint("LEFT", track, "RIGHT", SWITCH_GAP, 0)
	modernLabel:SetText(L.STYLE_MODERN)
	switch.skin = { track = track, knob = knob, frame = frameLines }

	switch:SetScript("OnClick", function()
		Theme.Toggle()
	end)
	switch:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(L.STYLE_SWITCH, 1, 1, 1)
		GameTooltip:AddLine(L.STYLE_SWITCH_TIP, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	switch:SetScript("OnLeave", GameTooltip_Hide)

	Register(function(style)
		local modern = style == "modern"
		local c = modern and COLORS.modern.accent or { 0.07, 0.06, 0.04, 1 }
		track:SetVertexColor(c[1], c[2], c[3], 1)
		SetShown(frameLines, not modern)
		local k = modern and COLORS.modern.onAccent or COLORS.classic.accent
		knob:SetVertexColor(k[1], k[2], k[3], 1)
		knob:ClearAllPoints()
		if modern then
			knob:SetPoint("RIGHT", track, "RIGHT", -2, 0)
		else
			knob:SetPoint("LEFT", track, "LEFT", 2, 0)
		end
		classicLabel:SetFontObject(modern and Theme.Fonts.DisableSmall or Theme.Fonts.NormalSmall)
		modernLabel:SetFontObject(modern and Theme.Fonts.HighlightSmall or Theme.Fonts.DisableSmall)
	end)
	return switch
end
