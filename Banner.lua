local addonName, ns = ...
local L = ns.L

local Banner = {}
ns.Banner = Banner

Banner.PREVIEW_ICON = "Interface\\Icons\\INV_Sword_39"

local WIDTH, HEIGHT = 460, 84
local ICON_SIZE = 52
local SHOW_SECONDS = 5
local CAP_SHOW_SECONDS = 7
local FADE_IN_SECONDS, FADE_OUT_SECONDS = 0.25, 0.8
local MAX_QUEUE = 5
local DEFAULT_POSITION = { point = "TOP", relativePoint = "TOP", x = 0, y = -170 }
local SEPARATOR = "  ·  "

local WHITE = "Interface\\Buttons\\WHITE8X8"
local BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"
local GLOW = "Interface\\Cooldown\\star4"
local SKULLS = { "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01" }
local SKULL_ATLAS = "BossBanner-SkullCircle"
local INFO_ICON = "Interface\\Icons\\INV_Shirt_GuildTabard_01"
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Colours { r, g, b } per style. Loot banners take their accent from the item quality.
local STYLES = {
	loot = {
		background = { 0.05, 0.05, 0.08, 0.94 },
		accent = { 0.64, 0.21, 0.93 },
		main = { 1, 1, 1 },
		sub = { 0.8, 0.8, 0.8 },
	},
	death = {
		background = { 0.06, 0.01, 0.01, 0.96 },
		accent = { 0.55, 0.06, 0.06 },
		title = { 0.86, 0.16, 0.16 },
		main = { 0.92, 0.85, 0.85 },
		sub = { 0.7, 0.55, 0.55 },
	},
	cap = {
		background = { 0.18, 0.11, 0.02, 0.95 },
		accent = { 1, 0.78, 0.2 },
		title = { 1, 0.88, 0.4 },
		main = { 1, 0.97, 0.85 },
		sub = { 1, 0.93, 0.72 },
		celebrate = true,
	},
	info = {
		background = { 0.03, 0.07, 0.12, 0.94 },
		accent = { 0.35, 0.65, 1 },
		title = { 0.55, 0.78, 1 },
		main = { 1, 1, 1 },
		sub = { 0.75, 0.8, 0.9 },
	},
}

local LOOT_TITLES = { epic = "BANNER_LOOT_EPIC", rare = "BANNER_LOOT_RARE", recipe = "BANNER_LOOT_RECIPE" }
local QUALITY_COLORS = { [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 } }

local frame
local queue = {}
local current -- banner on screen

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Not every texture of the retail client is guaranteed to ship with WoW Forever.
local function FileExists(path)
	return GetFileIDFromPath == nil or GetFileIDFromPath(path) ~= nil
end

local function SetSkull(texture)
	for _, path in ipairs(SKULLS) do
		if FileExists(path) then
			texture:SetTexture(path)
			texture:SetTexCoord(0, 1, 0, 1)
			return
		end
	end
	if C_Texture and C_Texture.GetAtlasExists and C_Texture.GetAtlasExists(SKULL_ATLAS) then
		texture:SetAtlas(SKULL_ATLAS)
	end
end

local function SetColor(texture, color, alpha)
	texture:SetColorTexture(color[1], color[2], color[3], alpha)
end

local function Join(...)
	local parts = {}
	for i = 1, select("#", ...) do
		local part = select(i, ...)
		if part and part ~= "" then
			parts[#parts + 1] = part
		end
	end
	return table.concat(parts, SEPARATOR)
end

local function ItemIcon(link)
	local itemID = tonumber(link:match("item:(%d+)"))
	return itemID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
end

local function QualityColor(quality)
	if quality and C_Item and C_Item.GetItemQualityColor then
		local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
		if ok and type(r) == "number" then
			return { r, g, b }
		end
	end
	return QUALITY_COLORS[quality]
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local ShowNext

local function Finish()
	current = nil
	if frame then
		frame:Hide()
	end
	ShowNext()
end

local function Dismiss()
	if frame then
		frame.fade:Stop()
	end
	Finish()
end

local function ApplyPosition(f)
	local position = ns.db.bannerPosition or DEFAULT_POSITION
	f:ClearAllPoints()
	f:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
end

local function CreateText(parent, font)
	local text = parent:CreateFontString(nil, "OVERLAY", font)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)
	return text
end

local function CreateBannerFrame()
	local f = CreateFrame("Frame", addonName .. "Banner", UIParent, "BackdropTemplate")
	f:SetSize(WIDTH, HEIGHT)
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:Hide()
	f:SetBackdrop({ bgFile = WHITE, edgeFile = BORDER, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })

	-- Accent colour fading out from the left, thin lines along the top and bottom edge
	f.wash = f:CreateTexture(nil, "BORDER")
	f.wash:SetTexture(WHITE)
	f.wash:SetPoint("TOPLEFT", 4, -4)
	f.wash:SetPoint("BOTTOMLEFT", 4, 4)
	f.wash:SetWidth(WIDTH * 0.6)
	f.topLine = f:CreateTexture(nil, "ARTWORK")
	f.topLine:SetPoint("TOPLEFT", 4, -4)
	f.topLine:SetPoint("TOPRIGHT", -4, -4)
	f.topLine:SetHeight(2)
	f.bottomLine = f:CreateTexture(nil, "ARTWORK")
	f.bottomLine:SetPoint("BOTTOMLEFT", 4, 4)
	f.bottomLine:SetPoint("BOTTOMRIGHT", -4, 4)
	f.bottomLine:SetHeight(2)

	-- Left: icon with a coloured frame, or the skull, or the level badge with a turning glow
	f.iconFrame = f:CreateTexture(nil, "ARTWORK")
	f.iconFrame:SetSize(ICON_SIZE + 4, ICON_SIZE + 4)
	f.iconFrame:SetPoint("LEFT", 16, 0)
	f.glow = f:CreateTexture(nil, "ARTWORK", nil, -1)
	f.glow:SetSize(ICON_SIZE * 2.2, ICON_SIZE * 2.2)
	f.glow:SetPoint("CENTER", f.iconFrame)
	f.glow:SetBlendMode("ADD")
	f.glowSpin = f.glow:CreateAnimationGroup()
	local spin = f.glowSpin:CreateAnimation("Rotation")
	spin:SetDegrees(-360)
	spin:SetDuration(12)
	f.glowSpin:SetLooping("REPEAT")
	f.icon = f:CreateTexture(nil, "OVERLAY")
	f.icon:SetPoint("CENTER", f.iconFrame)
	f.badge = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	f.badge:SetPoint("CENTER", f.iconFrame)
	local fontFile = GameFontNormalHuge and GameFontNormalHuge:GetFont()
	if fontFile then
		f.badge:SetFont(fontFile, 30, "THICKOUTLINE")
	end

	-- Right: title, main line, details
	f.title = CreateText(f, "GameFontNormalSmall")
	f.title:SetPoint("TOPLEFT", f.iconFrame, "TOPRIGHT", 16, 0)
	f.title:SetPoint("RIGHT", -16, 0)
	f.main = CreateText(f, "GameFontNormalLarge")
	f.main:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
	f.main:SetPoint("RIGHT", -16, 0)
	f.sub = CreateText(f, "GameFontHighlightSmall")
	f.sub:SetPoint("TOPLEFT", f.main, "BOTTOMLEFT", 0, -4)
	f.sub:SetPoint("RIGHT", -16, 0)

	-- Fade in, hold, fade out
	f.fade = f:CreateAnimationGroup()
	if f.fade.SetToFinalAlpha then
		f.fade:SetToFinalAlpha(true)
	end
	local fadeIn = f.fade:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(FADE_IN_SECONDS)
	fadeIn:SetOrder(1)
	f.hold = f.fade:CreateAnimation("Alpha")
	f.hold:SetFromAlpha(1)
	f.hold:SetToAlpha(1)
	f.hold:SetOrder(2)
	local fadeOut = f.fade:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)
	fadeOut:SetDuration(FADE_OUT_SECONDS)
	fadeOut:SetOrder(3)
	f.fade:SetScript("OnFinished", Finish)

	-- Celebration: the banner springs open
	f.pop = f:CreateAnimationGroup()
	local grow = f.pop:CreateAnimation("Scale")
	if grow.SetScaleFrom then
		grow:SetScaleFrom(0.6, 0.6)
		grow:SetScaleTo(1, 1)
	else
		grow:SetFromScale(0.6, 0.6)
		grow:SetToScale(1, 1)
	end
	grow:SetDuration(0.35)
	grow:SetSmoothing("OUT")

	-- Hover pauses it (and shows the item), right click closes it, shift-drag moves it
	f:SetScript("OnEnter", function(self)
		self.fade:Pause()
		if current and current.link then
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			pcall(GameTooltip.SetHyperlink, GameTooltip, current.link)
			GameTooltip:Show()
		end
	end)
	f:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
		if self:IsShown() then
			self.fade:Play()
		end
	end)
	f:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then
			Dismiss()
		end
	end)
	f:SetScript("OnDragStart", function(self)
		if IsShiftKeyDown() then
			self:StartMoving()
		end
	end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relativePoint, x, y = self:GetPoint()
		ns.db.bannerPosition = { point = point, relativePoint = relativePoint, x = x, y = y }
	end)
	return f
end

local function Apply(f, info)
	local style = STYLES[info.style]
	local accent = info.accent or style.accent

	f:SetBackdropColor(unpack(style.background))
	f:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
	local gradientSet = pcall(f.wash.SetGradient, f.wash, "HORIZONTAL",
		CreateColor(accent[1], accent[2], accent[3], 0.4), CreateColor(accent[1], accent[2], accent[3], 0))
	if not gradientSet then
		f.wash:SetVertexColor(accent[1], accent[2], accent[3], 0.15)
	end
	SetColor(f.topLine, accent, 0.9)
	SetColor(f.bottomLine, accent, 0.5)

	f.icon:Hide()
	f.iconFrame:Hide()
	f.badge:Hide()
	f.glow:Hide()
	f.glowSpin:Stop()
	f.icon:SetVertexColor(1, 1, 1)
	if info.style == "death" then
		f.icon:SetSize(ICON_SIZE + 8, ICON_SIZE + 8)
		SetSkull(f.icon)
		f.icon:SetVertexColor(0.92, 0.86, 0.86)
		f.icon:Show()
	elseif info.style == "cap" then
		f.badge:SetText(tostring(info.level))
		f.badge:SetTextColor(1, 0.86, 0.3)
		f.badge:Show()
		if FileExists(GLOW) then
			f.glow:SetTexture(GLOW)
			f.glow:SetVertexColor(1, 0.8, 0.25, 0.9)
			f.glow:Show()
			f.glowSpin:Play()
		end
	else
		f.icon:SetSize(ICON_SIZE, ICON_SIZE)
		f.icon:SetTexture(info.icon or FALLBACK_ICON)
		f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		f.icon:Show()
		SetColor(f.iconFrame, accent, 1)
		f.iconFrame:Show()
	end

	local titleColor = style.title or accent
	f.title:SetText(info.title)
	f.title:SetTextColor(titleColor[1], titleColor[2], titleColor[3])
	f.main:SetText(info.main)
	f.main:SetTextColor(style.main[1], style.main[2], style.main[3])
	f.sub:SetText(info.sub or "")
	f.sub:SetTextColor(style.sub[1], style.sub[2], style.sub[3])
	f.hold:SetDuration(style.celebrate and CAP_SHOW_SECONDS or SHOW_SECONDS)
end

ShowNext = function()
	if current or #queue == 0 then
		return
	end
	current = table.remove(queue, 1)
	frame = frame or CreateBannerFrame()
	ApplyPosition(frame)
	Apply(frame, current)
	frame:Show()
	frame.fade:Stop()
	frame.fade:Play()
	if STYLES[current.style].celebrate then
		frame.pop:Play()
	end
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------

-- info: style ("loot", "death", "cap", "info"), title, main, sub, and depending on the style
-- icon, link, accent { r, g, b } or level. Banners are shown one after another.
function Banner.Show(info)
	if #queue >= MAX_QUEUE then
		table.remove(queue, 1)
	end
	queue[#queue + 1] = info
	ShowNext()
end

-- name: the class coloured player name.
function Banner.ShowAnnouncement(kind, name, data)
	if kind == "death" then
		Banner.Show({
			style = "death",
			title = L.BANNER_DEATH_TITLE,
			main = L.BANNER_DEATH_TEXT:format(name),
			sub = Join(L.BANNER_LEVEL:format(data.level), data.zone, data.extra),
		})
	elseif kind == "cap" then
		Banner.Show({
			style = "cap",
			level = data.level,
			title = L.BANNER_CAP_TITLE,
			main = L.BANNER_CAP_TEXT:format(name, data.level),
			sub = L.BANNER_CAP_SUB,
		})
	elseif LOOT_TITLES[kind] then
		local link = data.extra
		Banner.Show({
			style = "loot",
			title = L[LOOT_TITLES[kind]],
			main = link,
			sub = Join(name, data.zone),
			link = link:find("|H", 1, true) and link or nil,
			icon = data.icon or ItemIcon(link),
			accent = QualityColor(ns.Announce.GetQuality(link)),
		})
	else
		Banner.Show({
			style = "info",
			icon = INFO_ICON,
			title = L.BANNER_TEST_TITLE,
			main = L.BANNER_TEST_TEXT:format(name),
			sub = L.BANNER_TEST_SUB,
		})
	end
end

-- Shows the three announcement banners locally, without sending anything.
function Banner.Preview()
	local name = ns.Announce.ClassColored(UnitName("player"), UnitClassBase("player"))
	Banner.Show({
		style = "loot",
		title = L.BANNER_LOOT_EPIC,
		main = "|cffa335ee[" .. L.BANNER_PREVIEW_ITEM .. "]|r",
		sub = Join(name, L.BANNER_PREVIEW_ZONE),
		icon = Banner.PREVIEW_ICON,
		accent = QUALITY_COLORS[4],
	})
	Banner.ShowAnnouncement("death", name, { level = UnitLevel("player"), zone = L.BANNER_PREVIEW_ZONE, extra = L.BANNER_PREVIEW_CAUSE })
	Banner.ShowAnnouncement("cap", name, { level = GetMaxPlayerLevel() })
end

function Banner.ResetPosition()
	ns.db.bannerPosition = nil
	if frame then
		ApplyPosition(frame)
	end
	ns.Print("system", L.BANNER_RESET_DONE)
end
