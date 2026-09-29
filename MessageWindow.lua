local addonName, ns = ...
local L = ns.L

local MessageWindow = {}
ns.MessageWindow = MessageWindow

local WIDTH, HEIGHT = 520, 470
local ROWS, ROW_HEIGHT = 10, 26
local LIST_TOP = -76
local DETAIL_TOP = LIST_TOP - ROWS * ROW_HEIGHT - 12
local DETAIL_HEIGHT = 84
local DETAIL_LINES = 6
local BUTTON_SIZE = 36
local MAX_BADGE = 99
local TOAST_WIDTH, TOAST_HEIGHT = 300, 40
local TOAST_SECONDS, TOAST_FADE_IN, TOAST_FADE_OUT = 4, 0.25, 0.5
local DEFAULT_WINDOW = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 60 }
local DEFAULT_BUTTON = { point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -40, y = -240 }
local FILTERS = {
	{ key = "all", width = 58 },
	{ key = "blocked", width = 86 },
	{ key = "guild", width = 66 },
	{ key = "audit", width = 66 },
	{ key = "finder", width = 112 },
	{ key = "system", width = 74 },
}

local WHITE = "Interface\\Buttons\\WHITE8X8"
local BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"
local BUTTON_ICON = "Interface\\Icons\\INV_Shirt_GuildTabard_01"
-- Banner style: dark, slightly transparent, thin gold frame
local BACKGROUND = { 0.04, 0.04, 0.06, 0.94 }
local GOLD = { 1, 0.82, 0 }
local FRAME_BORDER = { 0.85, 0.68, 0.2, 1 }
local PANEL = { 0, 0, 0, 0.35 }
local PANEL_BORDER = { 0.35, 0.3, 0.2, 0.8 }
local BUTTON_BACKGROUND = { 0.1, 0.09, 0.07, 0.9 }
local BUTTON_BORDER = { 0.45, 0.38, 0.22, 0.9 }
local BADGE_BACKGROUND = { 0.6, 0.08, 0.08, 1 }

local window, counterButton, toast
local highlight = {} -- entries that were unread when the window opened, or arrived while it was open

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function FileExists(path)
	return GetFileIDFromPath == nil or GetFileIDFromPath(path) ~= nil
end

local function StyleBox(frame, background, border, edgeSize)
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = BORDER, edgeSize = edgeSize or 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	frame:SetBackdropColor(background[1], background[2], background[3], background[4])
	frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
end

local function ColorCode(key)
	local c = ns.Messages.GetCategory(key).color
	return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

-- The category's icon, or a square in its colour when the icon is missing in WoW Forever.
local function SetCategoryIcon(texture, key)
	local category = ns.Messages.GetCategory(key)
	if FileExists(category.icon) then
		texture:SetTexture(category.icon)
		texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		texture:SetVertexColor(1, 1, 1)
	else
		texture:SetTexture(WHITE)
		texture:SetTexCoord(0, 1, 0, 1)
		texture:SetVertexColor(category.color[1], category.color[2], category.color[3])
	end
end

local function FirstLine(text)
	return (tostring(text or ""):match("^[^\n]*"))
end

local function FormatTime(t)
	if date("%d.%m.%Y", t) == date("%d.%m.%Y", GetServerTime()) then
		return date("%H:%M", t)
	end
	return date("%d.%m.", t)
end

local function SavePosition(frame, key)
	local point, _, relativePoint, x, y = frame:GetPoint()
	ns.db.messages[key] = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function RestorePosition(frame, key, default)
	local position = ns.db.messages[key]
	if type(position) ~= "table" or not position.point then
		position = default
	end
	frame:ClearAllPoints()
	frame:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
end

local function CreateFlatButton(parent, width)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(width, 22)
	StyleBox(b, BUTTON_BACKGROUND, BUTTON_BORDER, 10)
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.label:SetPoint("CENTER", 0, 0)
	local hover = b:CreateTexture(nil, "HIGHLIGHT")
	hover:SetTexture(WHITE)
	hover:SetPoint("TOPLEFT", 3, -3)
	hover:SetPoint("BOTTOMRIGHT", -3, 3)
	hover:SetVertexColor(1, 1, 1, 0.08)
	return b
end

local function FindIn(list, entry)
	for i, e in ipairs(list) do
		if e == entry then
			return i
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function CreateRow(w, index)
	local row = CreateFrame("Button", nil, w)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 16, LIST_TOP - (index - 1) * ROW_HEIGHT)
	row:SetPoint("TOPRIGHT", -16, LIST_TOP - (index - 1) * ROW_HEIGHT)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetTexture(WHITE)
	local hover = row:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetTexture(WHITE)
	hover:SetVertexColor(1, 1, 1, 0.06)
	row.stripe = row:CreateTexture(nil, "ARTWORK")
	row.stripe:SetTexture(WHITE)
	row.stripe:SetPoint("TOPLEFT", 0, -3)
	row.stripe:SetPoint("BOTTOMLEFT", 0, 3)
	row.stripe:SetWidth(2)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(18, 18)
	row.icon:SetPoint("LEFT", 8, 0)
	row.time = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.time:SetPoint("RIGHT", -8, 0)
	row.time:SetJustifyH("RIGHT")
	row.dot = row:CreateTexture(nil, "OVERLAY")
	row.dot:SetTexture(WHITE)
	row.dot:SetSize(6, 6)
	row.dot:SetPoint("RIGHT", row.time, "LEFT", -8, 0)
	row.dot:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.text:SetPoint("RIGHT", row.dot, "LEFT", -8, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row:SetScript("OnClick", function(self)
		w.selected = self.entry
		w.detailOffset = 0
		MessageWindow.Refresh()
	end)
	row:SetScript("OnEnter", function(self)
		local entry = self.entry
		if not entry then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if entry.l then
			GameTooltip:SetHyperlink(entry.l:match("|H(.-)|h") or entry.l)
		else
			GameTooltip:SetText(entry.m, 1, 1, 1, 1, true)
			if entry.d then
				GameTooltip:AddLine(entry.d, 0.8, 0.8, 0.8, true)
			end
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

local function Window()
	if window then
		return window
	end
	local w = CreateFrame("Frame", addonName .. "Messages", UIParent, "BackdropTemplate")
	w:SetSize(WIDTH, HEIGHT)
	w:SetFrameStrata("DIALOG")
	w:SetToplevel(true)
	w:SetClampedToScreen(true)
	w:SetMovable(true)
	w:EnableMouse(true)
	w:RegisterForDrag("LeftButton")
	w:SetScript("OnDragStart", function(self) self:StartMoving() end)
	w:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition(self, "window")
	end)
	w:SetScript("OnHide", function() wipe(highlight) end)
	StyleBox(w, BACKGROUND, FRAME_BORDER)
	RestorePosition(w, "window", DEFAULT_WINDOW)
	w:Hide()
	tinsert(UISpecialFrames, w:GetName())
	w.offset, w.detailOffset = 0, 0

	w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	w.title:SetPoint("TOPLEFT", 16, -12)
	w.title:SetText(L.MSG_TITLE)
	w.count = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	w.count:SetPoint("LEFT", w.title, "RIGHT", 10, -1)
	local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function() MessageWindow.Toggle() end)
	local line = w:CreateTexture(nil, "ARTWORK")
	line:SetTexture(WHITE)
	line:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.5)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", 12, -36)
	line:SetPoint("TOPRIGHT", -12, -36)

	w.filters = {}
	local x = 14
	for _, def in ipairs(FILTERS) do
		local b = CreateFlatButton(w, def.width)
		b:SetPoint("TOPLEFT", x, -44)
		b.key = def.key
		b:SetScript("OnClick", function(self)
			w.filter = self.key ~= "all" and self.key or nil
			w.offset = 0
			MessageWindow.Refresh()
		end)
		w.filters[def.key] = b
		x = x + def.width + 6
	end

	local listBox = CreateFrame("Frame", nil, w, "BackdropTemplate")
	listBox:SetPoint("TOPLEFT", 12, LIST_TOP + 4)
	listBox:SetPoint("TOPRIGHT", -12, LIST_TOP + 4)
	listBox:SetHeight(ROWS * ROW_HEIGHT + 8)
	StyleBox(listBox, PANEL, PANEL_BORDER, 10)
	w.rows = {}
	for i = 1, ROWS do
		w.rows[i] = CreateRow(w, i)
	end
	w.empty = w:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	w.empty:SetPoint("TOP", listBox, "TOP", 0, -40)
	w.empty:SetText(L.MSG_EMPTY)

	local detailBox = CreateFrame("Frame", nil, w, "BackdropTemplate")
	detailBox:SetPoint("TOPLEFT", 12, DETAIL_TOP)
	detailBox:SetPoint("TOPRIGHT", -12, DETAIL_TOP)
	detailBox:SetHeight(DETAIL_HEIGHT)
	StyleBox(detailBox, PANEL, PANEL_BORDER, 10)
	w.detail = detailBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	w.detail:SetPoint("TOPLEFT", 10, -8)
	w.detail:SetPoint("BOTTOMRIGHT", -10, 8)
	w.detail:SetJustifyH("LEFT")
	w.detail:SetJustifyV("TOP")
	w.detail:SetSpacing(2)
	detailBox:EnableMouseWheel(true)
	detailBox:SetScript("OnMouseWheel", function(_, delta)
		w.detailOffset = w.detailOffset - delta
		MessageWindow.Refresh()
	end)

	w.clear = CreateFlatButton(w, 90)
	w.clear:SetPoint("BOTTOMRIGHT", -12, 10)
	w.clear.label:SetText(L.BTN_MSG_CLEAR)
	w.clear:SetScript("OnClick", function() ns.Messages.Clear(w.filter) end)

	w:EnableMouseWheel(true)
	w:SetScript("OnMouseWheel", function(_, delta)
		w.offset = w.offset - delta * 2
		MessageWindow.Refresh()
	end)
	window = w
	return w
end

local function RefreshDetail(w)
	local entry = w.selected
	if not entry then
		w.detail:SetText("|cff999999" .. L.MSG_PICK .. "|r")
		return
	end
	local category = ns.Messages.GetCategory(entry.c)
	local text = ("%s%s|r  |cff999999%s|r\n%s"):format(ColorCode(entry.c), L[category.label], date("%d.%m.%Y %H:%M", entry.t), entry.m)
	if entry.d then
		text = text .. "\n\n" .. entry.d
	end
	local lines = { strsplit("\n", text) }
	w.detailOffset = math.max(0, math.min(w.detailOffset, #lines - DETAIL_LINES))
	w.detail:SetText(table.concat(lines, "\n", w.detailOffset + 1, math.min(#lines, w.detailOffset + DETAIL_LINES)))
end

function MessageWindow.Refresh()
	local w = window
	if not w or not w:IsShown() then
		return
	end
	local all = ns.Messages.GetList()
	if w.selected and not FindIn(all, w.selected) then
		w.selected = nil
	end
	local newCounts, newTotal = {}, 0
	for _, entry in ipairs(all) do
		if highlight[entry] then
			newCounts[entry.c] = (newCounts[entry.c] or 0) + 1
			newTotal = newTotal + 1
		end
	end
	w.count:SetText(newTotal > 0 and L.MSG_NEW:format(newTotal) or "")
	for _, def in ipairs(FILTERS) do
		local b = w.filters[def.key]
		local label, count
		if def.key == "all" then
			label, count = L.MSG_FILTER_ALL, newTotal
		else
			label = ColorCode(def.key) .. L[ns.Messages.GetCategory(def.key).label] .. "|r"
			count = newCounts[def.key] or 0
		end
		b.label:SetText(count > 0 and (label .. " |cffffffff" .. count .. "|r") or label)
		local border = (w.filter or "all") == def.key and FRAME_BORDER or BUTTON_BORDER
		b:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
	end

	local list = ns.Messages.GetList(w.filter)
	w.offset = math.max(0, math.min(w.offset, #list - ROWS))
	for i, row in ipairs(w.rows) do
		local entry = list[w.offset + i]
		row.entry = entry
		if entry then
			local color = ns.Messages.GetCategory(entry.c).color
			SetCategoryIcon(row.icon, entry.c)
			row.stripe:SetVertexColor(color[1], color[2], color[3], 0.9)
			row.text:SetText(FirstLine(entry.m))
			row.time:SetText(FormatTime(entry.t))
			local new = highlight[entry] == true
			row.dot:SetShown(new)
			row.bg:SetVertexColor(1, 1, 1, entry == w.selected and 0.12 or (new and 0.07 or 0.02))
			row:Show()
		else
			row:Hide()
		end
	end
	w.empty:SetShown(#list == 0)
	RefreshDetail(w)
end

---------------------------------------------------------------------------
-- Hint next to the button
---------------------------------------------------------------------------

local function CounterButton()
	if counterButton then
		return counterButton
	end
	local b = CreateFrame("Button", addonName .. "MessagesButton", UIParent, "BackdropTemplate")
	b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	b:SetFrameStrata("MEDIUM")
	b:SetClampedToScreen(true)
	b:SetMovable(true)
	b:RegisterForDrag("LeftButton")
	StyleBox(b, BACKGROUND, FRAME_BORDER, 12)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 5, -5)
	b.icon:SetPoint("BOTTOMRIGHT", -5, 5)
	b.icon:SetTexture(BUTTON_ICON)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.glow = b:CreateTexture(nil, "OVERLAY")
	b.glow:SetTexture(WHITE)
	b.glow:SetPoint("TOPLEFT", -4, 4)
	b.glow:SetPoint("BOTTOMRIGHT", 4, -4)
	b.glow:SetBlendMode("ADD")
	b.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.35)
	b.glow:Hide()
	b.pulse = b.glow:CreateAnimationGroup()
	b.pulse:SetLooping("BOUNCE")
	local fade = b.pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(0.15)
	fade:SetToAlpha(0.8)
	fade:SetDuration(0.9)
	b.badge = CreateFrame("Frame", nil, b, "BackdropTemplate")
	b.badge:SetSize(24, 18)
	b.badge:SetPoint("TOPRIGHT", 10, 8)
	StyleBox(b.badge, BADGE_BACKGROUND, FRAME_BORDER, 8)
	b.count = b.badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.count:SetPoint("CENTER", 0, 0)
	b:SetScript("OnClick", function() MessageWindow.Toggle() end)
	b:SetScript("OnDragStart", function(self) self:StartMoving() end)
	b:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition(self, "button")
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(ns.title, 1, 1, 1)
		GameTooltip:AddLine(L.MSG_UNREAD:format(ns.Messages.CountUnread()), GOLD[1], GOLD[2], GOLD[3])
		GameTooltip:AddLine(L.MSG_BUTTON_TIP, 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	RestorePosition(b, "button", DEFAULT_BUTTON)
	counterButton = b
	return b
end

local function UpdateButton()
	if not (ns.db and ns.char) then
		return
	end
	local b = CounterButton()
	b:SetShown(ns.db.messages.showButton and true or false)
	local unread = ns.Messages.CountUnread()
	b.badge:SetShown(unread > 0)
	b.count:SetText(unread > MAX_BADGE and (MAX_BADGE .. "+") or tostring(unread))
	local important = ns.Messages.HasImportantUnread()
	b.glow:SetShown(important)
	if important then
		b.pulse:Play()
	else
		b.pulse:Stop()
	end
end

local function Toast()
	if toast then
		return toast
	end
	local t = CreateFrame("Button", addonName .. "MessagesToast", UIParent, "BackdropTemplate")
	t:SetSize(TOAST_WIDTH, TOAST_HEIGHT)
	t:SetFrameStrata("HIGH")
	StyleBox(t, BACKGROUND, FRAME_BORDER)
	t.accent = t:CreateTexture(nil, "ARTWORK")
	t.accent:SetTexture(WHITE)
	t.accent:SetPoint("TOPLEFT", 4, -4)
	t.accent:SetPoint("BOTTOMLEFT", 4, 4)
	t.accent:SetWidth(3)
	t.icon = t:CreateTexture(nil, "ARTWORK")
	t.icon:SetSize(24, 24)
	t.icon:SetPoint("LEFT", 14, 0)
	t.text = t:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	t.text:SetPoint("LEFT", t.icon, "RIGHT", 10, 0)
	t.text:SetPoint("RIGHT", -12, 0)
	t.text:SetJustifyH("LEFT")
	t.text:SetWordWrap(false)
	t:SetScript("OnClick", function(self) MessageWindow.Show(nil, self.entry) end)
	t:SetScript("OnEnter", function(self)
		self.hovered = true
		self:SetAlpha(1)
	end)
	t:SetScript("OnLeave", function(self)
		self.hovered = false
		self.age = TOAST_FADE_IN
	end)
	-- Fade in, stay, fade out; hovering holds it.
	t:SetScript("OnUpdate", function(self, elapsed)
		if self.hovered then
			return
		end
		self.age = self.age + elapsed
		if self.age >= TOAST_SECONDS then
			self:Hide()
		elseif self.age < TOAST_FADE_IN then
			self:SetAlpha(self.age / TOAST_FADE_IN)
		elseif self.age > TOAST_SECONDS - TOAST_FADE_OUT then
			self:SetAlpha((TOAST_SECONDS - self.age) / TOAST_FADE_OUT)
		else
			self:SetAlpha(1)
		end
	end)
	t:Hide()
	toast = t
	return t
end

-- A newer important message replaces the one on screen; nothing piles up.
local function ShowToast(entry)
	local t = Toast()
	t:ClearAllPoints()
	t:SetPoint("RIGHT", CounterButton(), "LEFT", -8, 0)
	t.entry = entry
	SetCategoryIcon(t.icon, entry.c)
	local color = ns.Messages.GetCategory(entry.c).color
	t.accent:SetVertexColor(color[1], color[2], color[3], 1)
	t.text:SetText(FirstLine(entry.m))
	t.age, t.hovered = 0, false
	t:SetAlpha(0)
	t:Show()
end

local function HideToast()
	if toast then
		toast:Hide()
	end
end

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------

-- filter: a category or nil for all; entry: the message to select.
function MessageWindow.Show(filter, entry)
	local w = Window()
	w.filter = filter
	w.offset = 0
	if entry then
		w.selected = entry
		w.detailOffset = 0
	end
	if not w:IsShown() then
		wipe(highlight)
		for _, e in ipairs(ns.Messages.GetList()) do
			if not e.r then
				highlight[e] = true
			end
		end
		w:Show()
		ns.Messages.MarkAllRead()
	end
	if entry then
		local index = FindIn(ns.Messages.GetList(filter), entry)
		if index then
			w.offset = math.max(0, index - ROWS)
		end
	end
	HideToast()
	MessageWindow.Refresh()
end

function MessageWindow.IsShown()
	return window ~= nil and window:IsShown()
end

-- Puts window and button where they were saved, or at their default place.
function MessageWindow.RestorePositions()
	if window then
		RestorePosition(window, "window", DEFAULT_WINDOW)
	end
	if counterButton then
		RestorePosition(counterButton, "button", DEFAULT_BUTTON)
	end
end

function MessageWindow.Toggle()
	if MessageWindow.IsShown() then
		window:Hide()
		wipe(highlight)
	else
		MessageWindow.Show()
	end
end

ns.RegisterCallback("MESSAGES_UPDATED", function(entry)
	if entry and not entry.r then
		if MessageWindow.IsShown() then
			entry.r = true
			highlight[entry] = true
		elseif entry.i then
			ShowToast(entry)
		end
	end
	MessageWindow.Refresh()
	UpdateButton()
end)
ns.RegisterCallback("LOGIN", UpdateButton)
ns.RegisterCallback("SETTINGS_CHANGED", UpdateButton)
