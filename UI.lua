local addonName, ns = ...
local L = ns.L

local UI = {}
ns.UI = UI

local WIDTH, HEIGHT = 780, 540
local LEFT, RIGHT = 16, 400 -- column offsets inside a tab
local ROW = 24
local DEATHLOG_ROWS = 16
local DEATHLOG_ROW_HEIGHT = 18

-- Pages of the window: these tabs, plus the settings page behind the gear button in the title bar.
local TABS = {
	{ key = "rules", label = "TAB_RULES" },
	-- only when the officers switched professions on
	{ key = "professions", label = "TAB_PROFESSIONS", visible = function() return ns.Professions.IsEnabled() end },
	-- only when the officers switched the dungeon finder on
	{ key = "finder", label = "TAB_FINDER", visible = function() return ns.Finder.IsEnabled() end },
	{ key = "deathlog", label = "TAB_DEATHLOG" },
	{ key = "audit", label = "TAB_AUDIT" },
}
local TAB_SPACING = 146
local SETTINGS_ICONS = { "Interface\\Icons\\INV_Misc_Gear_01", "Interface\\Icons\\Trade_Engineering" }
local SETTINGS_BUTTON_GAP = 8 -- space between the gear and the close button

local RULE_SECTIONS = {
	{
		title = "SECTION_TRADE",
		rules = {
			{ key = "blockAuctionHouse", label = "RULE_AH", tip = "RULE_AH_TIP" },
			{ key = "blockMail", label = "RULE_MAIL", tip = "RULE_MAIL_TIP" },
			{ key = "tradeConjured", label = "RULE_CONJURED", tip = "RULE_CONJURED_TIP" },
			{ key = "tradeHealthstones", label = "RULE_HEALTHSTONES", tip = "RULE_HEALTHSTONES_TIP" },
			{ key = "tradeQuestItems", label = "RULE_QUESTITEMS", tip = "RULE_QUESTITEMS_TIP" },
			{ key = "tradeGold", label = "RULE_GOLD", tip = "RULE_GOLD_TIP" },
			{ key = "servicesOutgoing", label = "RULE_SERVICES_OUT", tip = "RULE_SERVICES_OUT_TIP" },
			{ key = "lockpickIncoming", label = "RULE_LOCKPICK_IN", tip = "RULE_LOCKPICK_IN_TIP" },
		},
	},
	{
		title = "SECTION_TRAVEL",
		rules = {
			{ key = "transportSummon", label = "RULE_SUMMON", tip = "RULE_SUMMON_TIP" },
			{ key = "transportPortal", label = "RULE_PORTAL", tip = "RULE_PORTAL_TIP" },
		},
	},
}

local ANNOUNCE_TYPES = {
	{ chatKey = "chatLevelCap", notifyKey = "levelCap", label = "ANN_TYPE_LEVELCAP" },
	{ chatKey = "chatDeath", notifyKey = "death", label = "ANN_TYPE_DEATH" },
	{ chatKey = "chatEpic", notifyKey = "epic", label = "ANN_TYPE_EPIC" },
	{ chatKey = "chatRare", notifyKey = "rare", label = "ANN_TYPE_RARE" },
	{ chatKey = "chatRecipe", notifyKey = "recipe", label = "ANN_TYPE_RECIPE" },
}

local frame
local pages = {}       -- page key -> frame
local tabButtons = {}  -- page key -> tab button
local lastTab = "rules" -- where the gear button returns to
local ruleCheckboxes = {}   -- guild rules, including the guild chat announcements
local personalCheckboxes = {} -- personal settings (ns.db.notify)
local deathRows = {}
local deathOffset = 0
local controls = {}

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------

local function FileExists(path)
	return GetFileIDFromPath == nil or GetFileIDFromPath(path) ~= nil
end

local function AtlasExists(atlas)
	return C_Texture and C_Texture.GetAtlasExists and C_Texture.GetAtlasExists(atlas) and true or false
end

local function AttachTooltip(widget, title, text)
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title, 1, 1, 1)
		GameTooltip:AddLine(text, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", GameTooltip_Hide)
end

local function CreateHeader(parent, x, y, text)
	local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	header:SetPoint("TOPLEFT", x, y)
	header:SetText(text)
	return header
end

local function CreateNote(parent, x, y, width)
	local note = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", x, y)
	note:SetWidth(width)
	note:SetJustifyH("LEFT")
	return note
end

local function CreateCheckbox(parent, x, y, labelText, tipText, onClick)
	local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	checkbox:SetSize(24, 24)
	checkbox:SetPoint("TOPLEFT", x - 2, y)
	local label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("LEFT", checkbox, "RIGHT", 4, 1)
	label:SetText(labelText)
	checkbox.label = label
	checkbox:SetScript("OnClick", onClick)
	AttachTooltip(checkbox, labelText, tipText)
	return checkbox
end

-- A checkbox for a guild rule: officers and players without guild rules can edit it.
local function AddRuleCheckbox(parent, x, y, key, labelText, tipText)
	local checkbox = CreateCheckbox(parent, x, y, labelText, tipText, function(self)
		ns.Rules.Set(key, self:GetChecked() and true or false)
	end)
	checkbox.ruleKey = key
	ruleCheckboxes[#ruleCheckboxes + 1] = checkbox
end

-- A checkbox for a personal setting ns.db[group][key].
local function AddPersonalCheckbox(parent, x, y, group, key, labelText, tipText)
	local checkbox = CreateCheckbox(parent, x, y, labelText, tipText, function(self)
		ns.db[group][key] = self:GetChecked() and true or false
		ns.Fire("SETTINGS_CHANGED")
	end)
	checkbox.group, checkbox.key = group, key
	personalCheckboxes[#personalCheckboxes + 1] = checkbox
end

-- The box commits its text through onCommit(text) when it loses focus; Escape discards the edit.
local function SetupEditBox(box, tipTitle, tipText, onCommit)
	box:SetAutoFocus(false)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnEscapePressed", function(self)
		self.cancelled = true
		self:ClearFocus()
	end)
	box:SetScript("OnEditFocusLost", function(self)
		if not self.cancelled then
			onCommit(self:GetText())
		end
		self.cancelled = nil
		UI.Refresh()
	end)
	AttachTooltip(box, tipTitle, tipText)
end

-- Label with a small number box behind it; onCommit receives the number or nil.
local function CreateNumberBox(parent, x, y, labelText, tipText, onCommit)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("TOPLEFT", x + 4, y)
	label:SetText(labelText)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(36, 20)
	box:SetPoint("LEFT", label, "RIGHT", 12, 0)
	box:SetNumeric(true)
	box:SetMaxLetters(3)
	box:SetJustifyH("CENTER")
	SetupEditBox(box, labelText, tipText, function(text)
		onCommit(tonumber(text))
	end)
	return box
end

local function CreateButton(parent, text, width, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local function SetFieldText(box, text)
	if not box:HasFocus() then
		box:SetText(text)
	end
end

---------------------------------------------------------------------------
-- Tab: rules
---------------------------------------------------------------------------

local function BuildRulesPanel(panel)
	local y = -4
	for _, section in ipairs(RULE_SECTIONS) do
		CreateHeader(panel, LEFT, y, L[section.title])
		y = y - 18
		for _, def in ipairs(section.rules) do
			AddRuleCheckbox(panel, LEFT, y, def.key, L[def.label], L[def.tip])
			y = y - ROW
		end
		y = y - 14
	end

	CreateHeader(panel, RIGHT, -4, L.SECTION_GROUPS)
	controls.groupLock = CreateNumberBox(panel, RIGHT, -28, L.RULE_GROUPLOCK, L.RULE_GROUPLOCK_TIP, function(value)
		if value then
			ns.Rules.Set("groupLockLevel", math.min(value, 255))
		end
	end)

	CreateHeader(panel, RIGHT, -64, L.SECTION_PARTNERS)
	local partners = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	partners:SetSize(WIDTH - RIGHT - 30, 20)
	partners:SetPoint("TOPLEFT", RIGHT + 8, -82)
	partners:SetMaxLetters(200)
	SetupEditBox(partners, L.SECTION_PARTNERS, L.PARTNERS_HINT, function(text)
		ns.Rules.SetPartnerGuilds(ns.Rules.ParseNameList(text))
	end)
	controls.partners = partners
	CreateNote(panel, RIGHT + 4, -108, WIDTH - RIGHT - 24):SetText(L.PARTNERS_HINT)

	CreateHeader(panel, RIGHT, -164, L.SECTION_PERSONAL)
	controls.leaveDelay = CreateNumberBox(panel, RIGHT, -188, L.LEAVE_DELAY, L.LEAVE_DELAY_TIP, function(value)
		if value then
			ns.db.groupLeaveDelay = math.min(value, 120)
		end
	end)

	CreateHeader(panel, RIGHT, -226, L.SECTION_FEATURES)
	AddRuleCheckbox(panel, RIGHT, -244, "audit", L.RULE_AUDIT, L.RULE_AUDIT_TIP)
	AddRuleCheckbox(panel, RIGHT, -268, "professions", L.RULE_PROFESSIONS, L.RULE_PROFESSIONS_TIP)
	AddRuleCheckbox(panel, RIGHT, -292, "dungeonFinder", L.RULE_FINDER, L.RULE_FINDER_TIP)
end

---------------------------------------------------------------------------
-- Settings page (gear button): announcements
---------------------------------------------------------------------------

local function BuildSettingsPanel(panel)
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", LEFT, -2)
	title:SetText(L.SETTINGS_TITLE)
	CreateHeader(panel, LEFT, -30, L.SECTION_CHAT)
	CreateHeader(panel, RIGHT, -30, L.SECTION_NOTIFY)
	local y = -48
	for _, def in ipairs(ANNOUNCE_TYPES) do
		AddRuleCheckbox(panel, LEFT, y, def.chatKey, L[def.label], L.CHAT_RULE_TIP)
		AddPersonalCheckbox(panel, RIGHT, y, "notify", def.notifyKey, L[def.label], L.NOTIFY_TIP)
		y = y - ROW
	end
	CreateNote(panel, LEFT + 4, y - 8, RIGHT - LEFT - 20):SetText(L.ANNOUNCE_NOTE)

	CreateHeader(panel, LEFT, -262, L.SECTION_MESSAGES)
	AddPersonalCheckbox(panel, LEFT, -280, "messages", "showButton", L.MSG_BUTTON_SHOW, L.MSG_BUTTON_SHOW_TIP)

	AddPersonalCheckbox(panel, RIGHT, y, "notify", "screen", L.NOTIFY_SCREEN, L.NOTIFY_SCREEN_TIP)
	controls.deathMinLevel = CreateNumberBox(panel, RIGHT, y - 34, L.DEATH_MIN_LEVEL, L.DEATH_MIN_LEVEL_TIP, function(value)
		if value then
			ns.db.notify.deathMinLevel = math.min(value, 255)
		end
	end)
	local test = CreateButton(panel, L.BTN_TEST, 186, function() ns.Announce.SendTest() end)
	test:SetPoint("TOPLEFT", RIGHT + 4, y - 66)
	AttachTooltip(test, L.BTN_TEST, L.BTN_TEST_TIP)
	local preview = CreateButton(panel, L.BTN_PREVIEW, 186, function() ns.Banner.Preview() end)
	preview:SetPoint("TOPLEFT", test, "BOTTOMLEFT", 0, -6)
	AttachTooltip(preview, L.BTN_PREVIEW, L.BTN_PREVIEW_TIP)
end

---------------------------------------------------------------------------
-- Tab: deathlog
---------------------------------------------------------------------------

local function BuildDeathlogPanel(panel)
	controls.deathHeader = CreateHeader(panel, LEFT, -4, "")
	for i = 1, DEATHLOG_ROWS do
		local row = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row:SetPoint("TOPLEFT", LEFT + 4, -24 - (i - 1) * DEATHLOG_ROW_HEIGHT)
		row:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
		row:SetJustifyH("LEFT")
		row:SetWordWrap(false)
		deathRows[i] = row
	end
	controls.deathFooter = CreateNote(panel, LEFT + 4, -30 - DEATHLOG_ROWS * DEATHLOG_ROW_HEIGHT, WIDTH - 40)
	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(_, delta)
		deathOffset = deathOffset - delta * 3
		UI.RefreshDeathlog()
	end)
end

function UI.RefreshDeathlog()
	if not frame or not frame:IsShown() or not pages.deathlog:IsShown() then
		return
	end
	local deaths = ns.Announce.GetDeaths()
	deathOffset = math.min(math.max(deathOffset, 0), math.max(0, #deaths - DEATHLOG_ROWS))
	controls.deathHeader:SetText(L.DEATHLOG_TITLE:format(#deaths))
	for i, row in ipairs(deathRows) do
		local entry = deaths[deathOffset + i]
		row:SetText(entry and ns.Announce.FormatDeath(entry) or "")
	end
	if #deaths == 0 then
		controls.deathFooter:SetText(L.DEATHLOG_EMPTY .. " " .. L.DEATHLOG_NOTE)
	else
		local last = math.min(deathOffset + DEATHLOG_ROWS, #deaths)
		controls.deathFooter:SetText(L.DEATHLOG_FOOTER:format(deathOffset + 1, last, #deaths) .. " " .. L.DEATHLOG_NOTE)
	end
end

---------------------------------------------------------------------------
-- Tab: audit (officers see every member, everybody else their own data)
---------------------------------------------------------------------------

local AUDIT_LIST_WIDTH = 220
local AUDIT_MEMBER_ROWS = 17
local AUDIT_DETAIL_ROWS = 11
local AUDIT_ROW_HEIGHT = 18
local AUDIT_DETAIL_X = LEFT + AUDIT_LIST_WIDTH + 20
local AUDIT_DETAIL_WIDTH = WIDTH - AUDIT_DETAIL_X - 16
local AUDIT_VIEWS = {
	{ key = "snapshots", label = "AUDIT_VIEW_HISTORY", format = "FormatSnapshot" },
	{ key = "trades", label = "AUDIT_VIEW_TRADES", format = "FormatTrade" },
	{ key = "mail", label = "AUDIT_VIEW_MAIL", format = "FormatMail" },
	{ key = "log", label = "AUDIT_VIEW_BLOCKED", format = "FormatLog" },
}

local audit = { view = 1, memberOffset = 0, detailOffset = 0, memberRows = {}, detailRows = {}, viewButtons = {} }

local function CreateListRow(parent, x, y, width)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(width, AUDIT_ROW_HEIGHT)
	row:SetPoint("TOPLEFT", x, y)
	row.selected = row:CreateTexture(nil, "BACKGROUND")
	row.selected:SetAllPoints()
	row.selected:SetColorTexture(0.3, 0.5, 1, 0.25)
	row.selected:Hide()
	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", 4, 0)
	row.text:SetPoint("RIGHT", -4, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	return row
end

local function AuditEntries()
	if ns.Audit.CanView() then
		return ns.Guild.GetRosterEntries()
	end
	local name, realm = UnitFullName("player")
	return { {
		key = ns.Guild.GetPlayerKey(),
		fullName = realm and (name .. "-" .. realm) or name,
		level = UnitLevel("player"),
		class = UnitClassBase("player"),
		online = true,
	} }
end

local function BuildAuditPanel(panel)
	controls.auditListHeader = CreateHeader(panel, LEFT, -4, "")
	for i = 1, AUDIT_MEMBER_ROWS do
		local row = CreateListRow(panel, LEFT, -22 - (i - 1) * AUDIT_ROW_HEIGHT, AUDIT_LIST_WIDTH)
		row:SetScript("OnClick", function(self)
			audit.selected = self.key
			audit.detailOffset = 0
			UI.RefreshAudit()
		end)
		audit.memberRows[i] = row
	end

	controls.auditName = CreateHeader(panel, AUDIT_DETAIL_X, -4, "")
	controls.auditStatus = CreateNote(panel, AUDIT_DETAIL_X, -24, AUDIT_DETAIL_WIDTH - 170)
	controls.auditRequest = CreateButton(panel, L.BTN_AUDIT_REQUEST, 160, function()
		ns.Audit.Request(audit.selectedName)
	end)
	controls.auditRequest:SetPoint("TOPRIGHT", -16, -2)
	AttachTooltip(controls.auditRequest, L.BTN_AUDIT_REQUEST, L.BTN_AUDIT_REQUEST_TIP)
	controls.auditSummary = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	controls.auditSummary:SetPoint("TOPLEFT", AUDIT_DETAIL_X, -46)
	controls.auditFlags = CreateNote(panel, AUDIT_DETAIL_X, -68, AUDIT_DETAIL_WIDTH)
	controls.auditFlags:SetFontObject("GameFontNormalSmall")
	controls.auditFlags:SetSpacing(2)

	for i, view in ipairs(AUDIT_VIEWS) do
		local button = CreateButton(panel, L[view.label], 110, function()
			audit.view = i
			audit.detailOffset = 0
			UI.RefreshAudit()
		end)
		button:SetPoint("TOPLEFT", AUDIT_DETAIL_X + (i - 1) * 116, -114)
		audit.viewButtons[i] = button
	end
	for i = 1, AUDIT_DETAIL_ROWS do
		local row = CreateListRow(panel, AUDIT_DETAIL_X, -142 - (i - 1) * AUDIT_ROW_HEIGHT, AUDIT_DETAIL_WIDTH)
		row:SetScript("OnEnter", function(self)
			if self.fullText and self.fullText ~= "" then
				GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
				GameTooltip:SetText(self.fullText, 1, 1, 1, 1, true)
				GameTooltip:Show()
			end
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		audit.detailRows[i] = row
	end

	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(_, delta)
		local x = GetCursorPosition() / panel:GetEffectiveScale()
		if x - panel:GetLeft() < AUDIT_DETAIL_X then
			audit.memberOffset = audit.memberOffset - delta * 3
		else
			audit.detailOffset = audit.detailOffset - delta * 3
		end
		UI.RefreshAudit()
	end)
end

local function RefreshAuditMembers(entries)
	audit.memberOffset = math.min(math.max(audit.memberOffset, 0), math.max(0, #entries - AUDIT_MEMBER_ROWS))
	for i, row in ipairs(audit.memberRows) do
		local entry = entries[audit.memberOffset + i]
		if entry then
			local name = Ambiguate(entry.fullName, "guild")
			name = entry.online and ns.Announce.ClassColored(name, entry.class) or ("|cff777777" .. name .. "|r")
			local fetched = ns.db.auditCache[entry.key] and " |cff66bbff*|r" or ""
			row.key = entry.key
			row.text:SetText(("%s |cff999999%d|r%s"):format(name, entry.level or 0, fetched))
			row.selected:SetShown(entry.key == audit.selected)
			row:Show()
		else
			row:Hide()
		end
	end
end

local function AuditStatus(key, data)
	if data and data.own then
		return L.AUDIT_STATUS_OWN
	end
	local state, count = ns.Audit.GetRequestState(key)
	if state == "running" then
		return L.AUDIT_STATUS_RUNNING:format(count)
	elseif state == "denied" then
		return L.AUDIT_STATUS_DENIED
	elseif state == "timeout" then
		return L.AUDIT_STATUS_TIMEOUT
	elseif data and data.fetched then
		return L.AUDIT_STATUS_FETCHED:format(date("%d.%m. %H:%M", data.fetched))
	end
	return L.AUDIT_STATUS_NONE
end

local function AuditFlagsText(data)
	local flags = ns.Audit.GetFlags(data)
	if #flags == 0 then
		return "|cff55ff55" .. L.AUDIT_NO_FLAGS .. "|r"
	end
	local lines = { "|cffff5555" .. L.AUDIT_FLAGS:format(#flags) .. "|r" }
	for i = 1, math.min(3, #flags) do
		lines[#lines + 1] = ("|cff999999%s|r  %s"):format(date("%d.%m. %H:%M", flags[i].t), flags[i].text)
	end
	return table.concat(lines, "\n")
end

local function RefreshAuditDetails(data)
	local view = AUDIT_VIEWS[audit.view]
	for i, button in ipairs(audit.viewButtons) do
		if i == audit.view then
			button:LockHighlight()
		else
			button:UnlockHighlight()
		end
	end
	local list = data and data[view.key] or {}
	audit.detailOffset = math.min(math.max(audit.detailOffset, 0), math.max(0, #list - AUDIT_DETAIL_ROWS))
	for i, row in ipairs(audit.detailRows) do
		-- newest first
		local entry = list[#list - audit.detailOffset - i + 1]
		local text = ""
		if entry then
			text = ns.Audit[view.format](entry)
		elseif i == 1 then
			text = "|cff999999" .. L.AUDIT_EMPTY .. "|r"
		end
		row.fullText = entry and text or nil
		row.text:SetText(text)
	end
end

function UI.RefreshAudit()
	if not frame or not frame:IsShown() or not pages.audit:IsShown() then
		return
	end
	local officer = ns.Audit.CanView()
	local entries = AuditEntries()
	local ownKey = ns.Guild.GetPlayerKey()
	if not officer or not audit.selected then
		audit.selected = ownKey
	end
	controls.auditListHeader:SetText(officer and L.AUDIT_MEMBERS:format(#entries) or L.AUDIT_OWN_DATA)
	RefreshAuditMembers(entries)

	local selected
	for _, entry in ipairs(entries) do
		if entry.key == audit.selected then
			selected = entry
		end
	end
	audit.selectedName = selected and selected.fullName
	local data = ns.Audit.GetData(audit.selected)
	controls.auditName:SetText(selected and ns.Announce.ClassColored(Ambiguate(selected.fullName, "guild"), selected.class) or "")
	controls.auditStatus:SetText(AuditStatus(audit.selected, data))

	local isOwn = audit.selected == ownKey
	controls.auditRequest:SetShown(officer and not isOwn)
	controls.auditRequest:SetEnabled(selected and selected.online and ns.Audit.GetRequestState(audit.selected) ~= "running" or false)

	local last = data and data.snapshots[#data.snapshots]
	if last then
		local played = last.p and L.AUDIT_PLAYED:format(ns.Audit.FormatDuration(last.p)) or ""
		controls.auditSummary:SetText(("%s   %s   %s"):format(L.AUDIT_LEVEL:format(last.l, last.x), ns.Audit.FormatMoney(last.m), played))
	else
		controls.auditSummary:SetText("")
	end
	controls.auditFlags:SetText(data and AuditFlagsText(data) or "")
	RefreshAuditDetails(data)
end

---------------------------------------------------------------------------
-- Tab: professions (professions, their members by skill, recipes of the clicked member)
---------------------------------------------------------------------------

local PROF_LIST_WIDTH = 190
local PROF_MEMBER_X = LEFT + 200
local PROF_MEMBER_WIDTH = 220
local PROF_RECIPE_X = LEFT + 430
local PROF_RECIPE_WIDTH = WIDTH - PROF_RECIPE_X - 16
local PROF_LIST_ROWS = 14
local PROF_MEMBER_ROWS = 16
local PROF_RECIPE_ROWS = 14
local PROF_ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"

local prof = { memberOffset = 0, recipeOffset = 0, listRows = {}, memberRows = {}, recipeRows = {} }

local function BuildProfessionsPanel(panel)
	CreateHeader(panel, LEFT, -4, L.PROF_LIST)
	for i = 1, PROF_LIST_ROWS do
		local row = CreateListRow(panel, LEFT, -24 - (i - 1) * 20, PROF_LIST_WIDTH)
		row:SetHeight(20)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(16, 16)
		row.icon:SetPoint("LEFT", 4, 0)
		row.text:ClearAllPoints()
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
		row.text:SetPoint("RIGHT", -4, 0)
		row:SetScript("OnClick", function(self)
			prof.selected = self.skillLineID
			prof.memberKey = nil
			prof.memberOffset, prof.recipeOffset = 0, 0
			UI.RefreshProfessions()
		end)
		prof.listRows[i] = row
	end

	controls.profMembers = CreateHeader(panel, PROF_MEMBER_X, -4, "")
	for i = 1, PROF_MEMBER_ROWS do
		local row = CreateListRow(panel, PROF_MEMBER_X, -24 - (i - 1) * AUDIT_ROW_HEIGHT, PROF_MEMBER_WIDTH)
		row:SetScript("OnClick", function(self)
			prof.memberKey = self.member.key
			prof.recipeOffset = 0
			-- Fetch right away if nothing is known yet.
			local data, state = ns.Professions.GetRecipes(self.member.key, prof.selected)
			if not self.member.own and self.member.online and not data and state ~= "running" then
				ns.Professions.RequestRecipes(self.member.fullName, prof.selected)
			end
			UI.RefreshProfessions()
		end)
		prof.memberRows[i] = row
	end

	controls.profRecipes = CreateHeader(panel, PROF_RECIPE_X, -4, "")
	controls.profStatus = CreateNote(panel, PROF_RECIPE_X, -22, PROF_RECIPE_WIDTH)
	controls.profRequest = CreateButton(panel, L.BTN_PROF_REQUEST, 160, function()
		if prof.member then
			ns.Professions.RequestRecipes(prof.member.fullName, prof.selected)
		end
	end)
	controls.profRequest:SetPoint("TOPLEFT", PROF_RECIPE_X, -50)
	AttachTooltip(controls.profRequest, L.BTN_PROF_REQUEST, L.BTN_PROF_REQUEST_TIP)
	for i = 1, PROF_RECIPE_ROWS do
		local row = CreateListRow(panel, PROF_RECIPE_X, -80 - (i - 1) * AUDIT_ROW_HEIGHT, PROF_RECIPE_WIDTH)
		row:SetScript("OnEnter", function(self)
			if self.recipeID then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetSpellByID(self.recipeID)
				GameTooltip:Show()
			end
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		prof.recipeRows[i] = row
	end

	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(_, delta)
		local x = GetCursorPosition() / panel:GetEffectiveScale() - panel:GetLeft()
		if x >= PROF_RECIPE_X then
			prof.recipeOffset = prof.recipeOffset - delta * 3
		elseif x >= PROF_MEMBER_X then
			prof.memberOffset = prof.memberOffset - delta * 3
		end
		UI.RefreshProfessions()
	end)
end

local function RecipeStatus(member, data, state, count)
	if member.own then
		return data.scanned > 0 and L.PROF_STATUS_OWN:format(date("%d.%m. %H:%M", data.scanned)) or L.PROF_STATUS_OWN_NONE
	elseif state == "running" then
		return L.PROF_STATUS_RUNNING:format(count)
	elseif state == "denied" then
		return L.PROF_STATUS_DENIED
	elseif state == "timeout" then
		return L.PROF_STATUS_TIMEOUT
	elseif data then
		return data.scanned > 0 and L.PROF_STATUS_FETCHED:format(date("%d.%m. %H:%M", data.fetched)) or L.PROF_STATUS_NOT_SCANNED
	elseif not member.online then
		return L.PROF_STATUS_OFFLINE
	end
	return L.PROF_STATUS_NONE
end

local function RefreshRecipes(members)
	prof.member = nil
	for _, member in ipairs(members) do
		if member.key == prof.memberKey then
			prof.member = member
		end
	end
	local member = prof.member
	local recipes = {}
	if member then
		local data, state, count = ns.Professions.GetRecipes(member.key, prof.selected)
		controls.profRecipes:SetText(L.PROF_RECIPES_OF:format(ns.Announce.ClassColored(Ambiguate(member.fullName, "guild"), member.class)))
		controls.profStatus:SetText(RecipeStatus(member, data, state, count))
		controls.profRequest:SetShown(not member.own)
		controls.profRequest:SetEnabled(member.online and state ~= "running" or false)
		for _, recipeID in ipairs(data and data.ids or {}) do
			recipes[#recipes + 1] = { id = recipeID, name = C_Spell.GetSpellName(recipeID) or ("#" .. recipeID) }
		end
		table.sort(recipes, function(a, b) return a.name < b.name end)
	else
		controls.profRecipes:SetText(L.PROF_RECIPES)
		controls.profStatus:SetText(L.PROF_PICK_MEMBER)
		controls.profRequest:Hide()
	end
	prof.recipeOffset = math.min(math.max(prof.recipeOffset, 0), math.max(0, #recipes - PROF_RECIPE_ROWS))
	for i, row in ipairs(prof.recipeRows) do
		local recipe = recipes[prof.recipeOffset + i]
		row.recipeID = recipe and recipe.id
		if recipe then
			row.text:SetText(recipe.name)
		elseif i == 1 and member and #recipes == 0 then
			row.text:SetText("|cff999999" .. L.PROF_NO_RECIPES .. "|r")
		else
			row.text:SetText("")
		end
	end
end

function UI.RefreshProfessions()
	if not frame or not frame:IsShown() or not pages.professions:IsShown() then
		return
	end
	local P = ns.Professions
	local list = P.GetList()
	prof.selected = prof.selected or list[1]
	for i, row in ipairs(prof.listRows) do
		local skillLineID = list[i]
		if skillLineID then
			local count = #P.GetMembers(skillLineID)
			row.skillLineID = skillLineID
			row.icon:SetTexture(P.GetIcon(skillLineID) or PROF_ICON_FALLBACK)
			row.icon:SetDesaturated(count == 0)
			row.text:SetText(("%s |cff999999(%d)|r"):format(P.GetName(skillLineID), count))
			row.text:SetFontObject(count > 0 and "GameFontHighlightSmall" or "GameFontDisableSmall")
			row.selected:SetShown(skillLineID == prof.selected)
			row:Show()
		else
			row:Hide()
		end
	end

	local members = P.GetMembers(prof.selected)
	controls.profMembers:SetText(L.PROF_MEMBERS:format(P.GetName(prof.selected), #members))
	prof.memberOffset = math.min(math.max(prof.memberOffset, 0), math.max(0, #members - PROF_MEMBER_ROWS))
	for i, row in ipairs(prof.memberRows) do
		local member = members[prof.memberOffset + i]
		row.member = member
		if member then
			local name = Ambiguate(member.fullName, "guild")
			name = member.online and ns.Announce.ClassColored(name, member.class) or ("|cff777777" .. name .. "|r")
			row.text:SetText(("%s  |cffffd100%d|r|cff999999/%d|r"):format(name, member.skill or 0, member.max or 0))
			row.selected:SetShown(member.key == prof.memberKey)
			row:Show()
		else
			row:Hide()
		end
	end
	RefreshRecipes(members)
end

---------------------------------------------------------------------------
-- Tab: dungeon finder (dungeons and raids on the left, listings on the right, own listing below)
---------------------------------------------------------------------------

local FINDER_LIST_WIDTH = 236
local FINDER_LIST_ROWS = 15
local FINDER_RIGHT_X = LEFT + 252
local FINDER_RIGHT_WIDTH = WIDTH - FINDER_RIGHT_X - 16
local FINDER_LISTING_ROWS = 6
local FINDER_LISTING_HEIGHT = 40
local FINDER_SLOTS = 5
local FINDER_SLOT_SIZE = 20
local FINDER_SLOT_X = 210
local FINDER_OWN_Y = -272
local LEVEL_COLORS = { fit = "|cff40ff40", low = "|cffff6060", high = "|cff808080" }
local ROLE_ATLASES = {
	TANK = { "groupfinder-icon-role-large-tank", "roleicon-tiny-tank" },
	HEALER = { "groupfinder-icon-role-large-heal", "roleicon-tiny-healer" },
	DAMAGER = { "groupfinder-icon-role-large-dps", "roleicon-tiny-dps" },
}
local EMPTY_SLOT_ATLAS = "groupfinder-icon-emptyslot"
local ROLE_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local CLASS_ICONS = "Interface\\WorldStateFrame\\Icons-Classes"
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"
local CHECK_MARK = "Interface\\Buttons\\UI-CheckBox-Check"

local finder = { listOffset = 0, listingOffset = 0, listRows = {}, listingRows = {} }

-- Role icon of a group slot; members without a known role show their class, empty slots a dim circle.
local function SetSlotIcon(texture, member)
	texture:SetTexCoord(0, 1, 0, 1)
	texture:SetVertexColor(1, 1, 1)
	if member and member.role then
		for _, atlas in ipairs(ROLE_ATLASES[member.role]) do
			if AtlasExists(atlas) then
				texture:SetAtlas(atlas)
				return
			end
		end
		if GetTexCoordsForRoleSmallCircle and FileExists(ROLE_TEXTURE) then
			texture:SetTexture(ROLE_TEXTURE)
			texture:SetTexCoord(GetTexCoordsForRoleSmallCircle(member.role))
			return
		end
	end
	if member then
		local coords = member.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[member.class]
		if coords and FileExists(CLASS_ICONS) then
			texture:SetTexture(CLASS_ICONS)
			texture:SetTexCoord(unpack(coords))
		else
			texture:SetTexture(QUESTION_MARK)
		end
	elseif AtlasExists(EMPTY_SLOT_ATLAS) then
		texture:SetAtlas(EMPTY_SLOT_ATLAS)
	else
		texture:SetColorTexture(0, 0, 0, 0.4)
	end
end

local function RoleName(role)
	return role and L["ROLE_" .. role] or L.ROLE_NONE
end

-- Picked activities that the game still knows, in list order; as a set too.
local function SelectedActivities()
	local selected = ns.char.finder.selected
	local ids, set = {}, {}
	for _, activity in ipairs(ns.Finder.GetActivities()) do
		if selected[activity.id] then
			ids[#ids + 1] = activity.id
			set[activity.id] = true
		end
	end
	return ids, set
end

-- Rows of the left list: headers for dungeons and raids, then the activities.
local function FinderEntries(level)
	local F, settings = ns.Finder, ns.char.finder
	local entries, lastRaid = {}, nil
	for _, activity in ipairs(F.GetActivities()) do
		local fit = F.GetLevelFit(activity, level)
		if not settings.onlyFitting or fit == nil or fit == "fit" or settings.selected[activity.id] then
			if activity.raid ~= lastRaid then
				entries[#entries + 1] = { header = activity.raid and L.FINDER_RAIDS or L.FINDER_DUNGEONS }
				lastRaid = activity.raid
			end
			entries[#entries + 1] = { activity = activity, fit = fit }
		end
	end
	return entries
end

local function ActivityNames(ids, level)
	local names = {}
	for _, id in ipairs(ids) do
		local activity = ns.Finder.GetActivity(id)
		local fit = ns.Finder.GetLevelFit(activity, level)
		local color = (fit == "low" or fit == "high") and "|cff808080" or "|cffffd100"
		names[#names + 1] = color .. (activity and activity.name or ("#" .. id)) .. "|r"
	end
	return table.concat(names, ", ")
end

local function FormatAge(seconds)
	local minutes = math.floor(math.max(0, seconds) / 60)
	return minutes < 1 and L.FINDER_AGE_NEW or L.FINDER_AGE:format(minutes)
end

local function ShowListingTooltip(row)
	local listing = row.listing
	if not listing then
		return
	end
	local F = ns.Finder
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	local leader = listing.members[1]
	GameTooltip:SetText(ns.Announce.ClassColored(Ambiguate(listing.name, "guild"), leader and leader.class), 1, 1, 1)
	for _, id in ipairs(listing.activities) do
		local activity = F.GetActivity(id)
		GameTooltip:AddDoubleLine(activity and activity.name or ("#" .. id), F.FormatLevels(activity), 1, 0.82, 0, 0.7, 0.7, 0.7)
	end
	GameTooltip:AddLine(" ")
	if #listing.members > 0 then
		for _, member in ipairs(listing.members) do
			local name = member.name and ns.Announce.ClassColored(Ambiguate(member.name, "guild"), member.class) or "?"
			GameTooltip:AddLine(("%s: %s - %s"):format(RoleName(member.role), name, F.DescribeMember(member.class, member.level, member.role, member.spec)), 1, 1, 1)
		end
	end
	local counts = listing.counts
	GameTooltip:AddLine(L.FINDER_COUNTS:format(counts.TANK, counts.HEALER, counts.DAMAGER, listing.total, listing.size), 0.7, 0.7, 0.7)
	GameTooltip:AddLine(FormatAge(GetTime() - listing.created), 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function CreateActivityRow(panel, index)
	local row = CreateListRow(panel, LEFT, -24 - (index - 1) * AUDIT_ROW_HEIGHT, FINDER_LIST_WIDTH)
	row.check = row:CreateTexture(nil, "ARTWORK")
	row.check:SetSize(14, 14)
	row.check:SetPoint("LEFT", 2, 0)
	row.check:SetTexture(CHECK_MARK)
	row.levels = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.levels:SetPoint("RIGHT", -4, 0)
	row.levels:SetWidth(44)
	row.levels:SetJustifyH("RIGHT")
	row.text:ClearAllPoints()
	row.text:SetPoint("LEFT", 18, 0)
	row.text:SetPoint("RIGHT", row.levels, "LEFT", -4, 0)
	row:SetScript("OnClick", function(self)
		if self.activityID then
			local selected = ns.char.finder.selected
			selected[self.activityID] = not selected[self.activityID] or nil
			finder.listingOffset = 0
			UI.RefreshFinder()
		end
	end)
	row:SetScript("OnEnter", function(self)
		local activity = self.activityID and ns.Finder.GetActivity(self.activityID)
		if activity then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(activity.name, 1, 1, 1)
			local levels = ns.Finder.FormatLevels(activity)
			GameTooltip:AddLine(levels ~= "" and L.FINDER_TIP_LEVELS:format(levels) or L.FINDER_NO_LEVELS, 0.8, 0.8, 0.8)
			if activity.raid then
				GameTooltip:AddLine(L.FINDER_RAID_SIZE:format(activity.size), 0.8, 0.8, 0.8)
			end
			GameTooltip:AddLine(L.FINDER_TIP_PICK, 0.6, 0.6, 0.6, true)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

local function CreateListingRow(panel, index)
	local row = CreateFrame("Button", nil, panel)
	row:SetSize(FINDER_RIGHT_WIDTH, FINDER_LISTING_HEIGHT - 2)
	row:SetPoint("TOPLEFT", FINDER_RIGHT_X, -24 - (index - 1) * FINDER_LISTING_HEIGHT)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.06)

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.name:SetPoint("TOPLEFT", 6, -4)
	row.name:SetWidth(FINDER_SLOT_X - 60)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.age = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.age:SetPoint("TOPRIGHT", row, "TOPLEFT", FINDER_SLOT_X - 6, -5)
	row.age:SetJustifyH("RIGHT")
	row.dungeons = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.dungeons:SetPoint("BOTTOMLEFT", 6, 5)
	row.dungeons:SetWidth(FINDER_SLOT_X - 12)
	row.dungeons:SetJustifyH("LEFT")
	row.dungeons:SetWordWrap(false)

	row.slots = {}
	for i = 1, FINDER_SLOTS do
		local slot = row:CreateTexture(nil, "ARTWORK")
		slot:SetSize(FINDER_SLOT_SIZE, FINDER_SLOT_SIZE)
		slot:SetPoint("LEFT", FINDER_SLOT_X + (i - 1) * (FINDER_SLOT_SIZE + 1), 0)
		row.slots[i] = slot
	end
	row.counts = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.counts:SetPoint("LEFT", FINDER_SLOT_X, 0)
	row.counts:SetWidth(FINDER_SLOTS * (FINDER_SLOT_SIZE + 1) + 10)
	row.counts:SetJustifyH("LEFT")

	row.whisper = CreateButton(row, L.FINDER_BTN_WHISPER, 70, function(self)
		ns.Finder.Whisper(self:GetParent().listing)
	end)
	row.whisper:SetPoint("RIGHT", -4, 0)
	row.action = CreateButton(row, "", 84, function(self)
		local listing = self:GetParent().listing
		if self.kind == "invite" then
			ns.Finder.Invite(listing)
		elseif self.kind == "request" then
			ns.Finder.RequestJoin(listing)
		end
	end)
	row.action:SetPoint("RIGHT", row.whisper, "LEFT", -4, 0)
	row:SetScript("OnEnter", ShowListingTooltip)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

local function BuildFinderPanel(panel)
	CreateHeader(panel, LEFT, -4, L.FINDER_LIST)
	for i = 1, FINDER_LIST_ROWS do
		finder.listRows[i] = CreateActivityRow(panel, i)
	end
	controls.finderEmpty = CreateNote(panel, LEFT + 4, -28, FINDER_LIST_WIDTH - 8)
	controls.finderOnlyFitting = CreateCheckbox(panel, LEFT, -24 - FINDER_LIST_ROWS * AUDIT_ROW_HEIGHT - 6, L.FINDER_ONLY_FITTING,
		L.FINDER_ONLY_FITTING_TIP, function(self)
			ns.char.finder.onlyFitting = self:GetChecked() and true or false
			finder.listOffset = 0
			UI.RefreshFinder()
		end)
	controls.finderClear = CreateButton(panel, L.FINDER_BTN_CLEAR, 150, function()
		wipe(ns.char.finder.selected)
		UI.RefreshFinder()
	end)
	controls.finderClear:SetPoint("TOPLEFT", LEFT + 2, -24 - FINDER_LIST_ROWS * AUDIT_ROW_HEIGHT - 32)

	controls.finderHeader = CreateHeader(panel, FINDER_RIGHT_X, -4, "")
	controls.finderNone = CreateNote(panel, FINDER_RIGHT_X + 4, -30, FINDER_RIGHT_WIDTH - 8)
	for i = 1, FINDER_LISTING_ROWS do
		finder.listingRows[i] = CreateListingRow(panel, i)
	end

	CreateHeader(panel, FINDER_RIGHT_X, FINDER_OWN_Y, L.FINDER_OWN)
	controls.finderRole = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	controls.finderRole:SetPoint("TOPRIGHT", panel, "TOPLEFT", FINDER_RIGHT_X + FINDER_RIGHT_WIDTH, FINDER_OWN_Y - 2)
	controls.finderRole:SetJustifyH("RIGHT")
	controls.finderStatus = CreateNote(panel, FINDER_RIGHT_X + 4, FINDER_OWN_Y - 18, FINDER_RIGHT_WIDTH - 8)
	controls.finderStatus:SetFontObject("GameFontHighlightSmall")
	controls.finderPost = CreateButton(panel, L.FINDER_BTN_POST, 150, function()
		local ids = SelectedActivities()
		local ok, reason = ns.Finder.Post(ids)
		if not ok then
			ns.Warn("finder", reason)
		end
	end)
	controls.finderPost:SetPoint("TOPLEFT", FINDER_RIGHT_X + 2, FINDER_OWN_Y - 54)
	AttachTooltip(controls.finderPost, L.FINDER_BTN_POST, L.FINDER_BTN_POST_TIP)
	controls.finderCancel = CreateButton(panel, L.FINDER_BTN_CANCEL, 120, function()
		ns.Finder.Cancel()
	end)
	controls.finderCancel:SetPoint("LEFT", controls.finderPost, "RIGHT", 8, 0)

	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(_, delta)
		local x = GetCursorPosition() / panel:GetEffectiveScale() - panel:GetLeft()
		if x < FINDER_RIGHT_X then
			finder.listOffset = finder.listOffset - delta * 3
		else
			finder.listingOffset = finder.listingOffset - delta
		end
		UI.RefreshFinder()
	end)
end

local function RefreshActivityList(level, counts)
	local entries = FinderEntries(level)
	finder.listOffset = math.min(math.max(finder.listOffset, 0), math.max(0, #entries - FINDER_LIST_ROWS))
	local selected = ns.char.finder.selected
	for i, row in ipairs(finder.listRows) do
		local entry = entries[finder.listOffset + i]
		row.activityID = entry and entry.activity and entry.activity.id
		if not entry then
			row:Hide()
		elseif entry.header then
			row.text:SetText(entry.header)
			row.text:SetFontObject("GameFontNormal")
			row.levels:SetText("")
			row.check:Hide()
			row.selected:Hide()
			row:Show()
		else
			local activity = entry.activity
			local count = counts[activity.id]
			row.text:SetText(activity.name .. (count and (" |cff66bbff(" .. count .. ")|r") or ""))
			row.text:SetFontObject(entry.fit == "fit" and "GameFontHighlightSmall" or "GameFontDisableSmall")
			row.levels:SetText((LEVEL_COLORS[entry.fit] or "|cffcccccc") .. ns.Finder.FormatLevels(activity) .. "|r")
			row.check:SetShown(selected[activity.id] and true or false)
			row.selected:SetShown(selected[activity.id] and true or false)
			row:Show()
		end
	end
	controls.finderEmpty:SetText(#entries == 0 and L.FINDER_NO_ACTIVITIES or "")
	controls.finderOnlyFitting:SetChecked(ns.char.finder.onlyFitting)
	controls.finderClear:SetEnabled(next(selected) ~= nil)
end

local function RefreshListingRow(row, listing, level)
	local F = ns.Finder
	row.listing = listing
	local leader = listing.members[1]
	local suffix = listing.own and (" |cff66bbff" .. L.FINDER_YOU .. "|r") or (listing.mine and (" |cff66ff66" .. L.FINDER_YOUR_GROUP .. "|r")) or ""
	row.name:SetText(ns.Announce.ClassColored(Ambiguate(listing.name, "guild"), leader and leader.class)
		.. (leader and leader.level and leader.level > 0 and (" |cff999999" .. leader.level .. "|r") or "") .. suffix)
	row.age:SetText(FormatAge(GetTime() - listing.created))
	row.dungeons:SetText(ActivityNames(listing.activities, level))
	if listing.own then
		row.bg:SetColorTexture(0.2, 0.4, 0.8, 0.18)
	elseif listing.mine then
		row.bg:SetColorTexture(0.2, 0.8, 0.3, 0.12)
	else
		row.bg:SetColorTexture(1, 1, 1, 0.03)
	end

	-- Groups show their five places, raids their numbers.
	local showSlots = listing.size <= FINDER_SLOTS and (#listing.members > 0 or listing.total <= 1)
	for i, slot in ipairs(row.slots) do
		if showSlots then
			SetSlotIcon(slot, listing.members[i])
			slot:Show()
		else
			slot:Hide()
		end
	end
	local counts = listing.counts
	row.counts:SetText(showSlots and "" or L.FINDER_COUNTS_SHORT:format(counts.TANK, counts.HEALER, counts.DAMAGER, listing.total, listing.size))

	local action = F.GetAction(listing)
	row.action.kind = action
	if action then
		row.action:SetText(action == "invite" and L.FINDER_BTN_INVITE or action == "request" and L.FINDER_BTN_REQUEST or L.FINDER_BTN_REQUESTED)
		row.action:SetEnabled(action ~= "requested")
		row.action:Show()
	else
		row.action:Hide()
	end
	row.whisper:SetShown(not listing.own)
	row:Show()
end

local function RefreshOwnListing(level)
	local F = ns.Finder
	local role, specID = F.GetOwnRole()
	local specName = F.GetSpecInfo(specID)
	controls.finderRole:SetText(L.FINDER_YOUR_ROLE:format(specName and ("%s (%s)"):format(specName, RoleName(role)) or RoleName(role)))

	local own = F.GetOwnListing()
	local ids = SelectedActivities()
	local canPost, reason = F.CanPost()
	if own then
		-- Two lines at most, the buttons sit right below.
		local names = #own.activities <= 2 and ActivityNames(own.activities, level) or L.FINDER_N_ACTIVITIES:format(#own.activities)
		controls.finderStatus:SetText(L.FINDER_OWN_ACTIVE:format(names, math.ceil(F.GetRemainingSeconds() / 60)))
	elseif not canPost then
		controls.finderStatus:SetText(reason)
	elseif #ids == 0 then
		controls.finderStatus:SetText(L.FINDER_OWN_PICK)
	else
		controls.finderStatus:SetText(L.FINDER_OWN_READY:format(#ids))
	end
	controls.finderPost:SetText(own and L.FINDER_BTN_UPDATE or L.FINDER_BTN_POST)
	controls.finderPost:SetEnabled(canPost and #ids > 0)
	controls.finderCancel:SetEnabled(own ~= nil)
end

function UI.RefreshFinder()
	if not frame or not frame:IsShown() or not pages.finder:IsShown() then
		return
	end
	local F = ns.Finder
	local level = UnitLevel("player")
	RefreshActivityList(level, F.CountListings())

	local ids, filter = SelectedActivities()
	local listings = F.GetListings(#ids > 0 and filter or nil)
	local total = #F.GetListings()
	controls.finderHeader:SetText(#ids > 0 and L.FINDER_LISTINGS_FILTERED:format(#listings, total) or L.FINDER_LISTINGS:format(total))
	controls.finderNone:SetText(#listings == 0 and (total == 0 and L.FINDER_NO_LISTINGS or L.FINDER_NO_MATCHES) or "")
	finder.listingOffset = math.min(math.max(finder.listingOffset, 0), math.max(0, #listings - FINDER_LISTING_ROWS))
	for i, row in ipairs(finder.listingRows) do
		local listing = listings[finder.listingOffset + i]
		if listing then
			RefreshListingRow(row, listing, level)
		else
			row.listing = nil
			row:Hide()
		end
	end
	RefreshOwnListing(level)
end

---------------------------------------------------------------------------
-- Publishing: addons may not write the guild info, so officers copy the tags and paste them
-- there themselves. The dialog closes once the guild info matches. Removing works by hand too.
---------------------------------------------------------------------------

local COPY_DIALOG_WIDTH = 540
local COPY_CHECK_SECONDS = 2

local copyDialog

local function CreateCopyDialog()
	local d = CreateFrame("Frame", addonName .. "CopyDialog", UIParent, "BasicFrameTemplateWithInset")
	d:SetSize(COPY_DIALOG_WIDTH, 210)
	d:SetPoint("CENTER", 0, 140)
	d:SetFrameStrata("FULLSCREEN_DIALOG")
	d:SetToplevel(true)
	d:SetClampedToScreen(true)
	d:SetMovable(true)
	d:EnableMouse(true)
	d:RegisterForDrag("LeftButton")
	d:SetScript("OnDragStart", d.StartMoving)
	d:SetScript("OnDragStop", d.StopMovingOrSizing)
	d:Hide()
	tinsert(UISpecialFrames, d:GetName())

	local title = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", 0, -5)
	title:SetText(L.PUBLISH_DIALOG_TITLE)
	d.text = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	d.text:SetPoint("TOPLEFT", 18, -36)
	d.text:SetPoint("RIGHT", -18, 0)
	d.text:SetJustifyH("LEFT")
	d.text:SetSpacing(3)

	-- Read-only: whatever is typed, the text to copy comes back, selected.
	local box = CreateFrame("EditBox", nil, d, "InputBoxTemplate")
	box:SetHeight(22)
	box:SetPoint("BOTTOMLEFT", 24, 76)
	box:SetPoint("BOTTOMRIGHT", -20, 76)
	box:SetAutoFocus(false)
	box:SetMaxLetters(0)
	box:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(d.copyText or "")
			self:HighlightText()
		end
	end)
	-- Not box.HighlightText directly: the handler gets more arguments, which HighlightText would
	-- take for its start and stop position.
	box:SetScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)
	box:SetScript("OnEscapePressed", function() d:Hide() end)
	d.box = box

	d.note = CreateNote(d, 22, -154, COPY_DIALOG_WIDTH - 44)
	d.note:SetText(L.PUBLISH_DIALOG_NOTE)
	local close = CreateButton(d, L.BTN_CLOSE, 120, function() d:Hide() end)
	close:SetPoint("BOTTOMRIGHT", -16, 14)
	d:SetScript("OnHide", function()
		if d.ticker then
			d.ticker:Cancel()
			d.ticker = nil
		end
	end)
	return d
end

-- replacing: the guild info has older tags, which the officer has to replace.
function UI.ShowPublishDialog(tags, replacing)
	copyDialog = copyDialog or CreateCopyDialog()
	local d = copyDialog
	d.copyText = tags
	d.text:SetText(L.PUBLISH_DIALOG_TEXT .. (replacing and (" " .. L.PUBLISH_DIALOG_REPLACE) or ""))
	d.box:SetText(tags)
	d:Show()
	d.box:SetFocus()
	d.box:HighlightText()
	-- Saving the guild info fires no event we could rely on; look at the text every few seconds.
	d.ticker = d.ticker or C_Timer.NewTicker(COPY_CHECK_SECONDS, ns.Guild.CheckInfoText)
end

-- Closes the dialog once the guild info contains the draft; follows the draft while it is open.
local function CheckCopyDialog()
	local d = copyDialog
	if not d or not d:IsShown() then
		return
	end
	local tags = ns.Guild.GetDraftTags()
	if ns.Guild.GetPublishedTags() == tags then
		d:Hide()
	elseif tags ~= d.copyText then
		d.copyText = tags
		d.box:SetText(tags)
	end
end

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------

-- Pages behind hidden tabs (professions switched off) cannot be shown.
local function IsPageAvailable(key)
	if not pages[key] then
		return false
	end
	for _, tab in ipairs(TABS) do
		if tab.key == key and tab.visible then
			return tab.visible()
		end
	end
	return true
end

-- Places the visible tab buttons next to each other.
local function LayoutTabs()
	local x = LEFT
	for _, tab in ipairs(TABS) do
		local button = tabButtons[tab.key]
		if not tab.visible or tab.visible() then
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", x, -30)
			button:Show()
			x = x + TAB_SPACING
		else
			button:Hide()
		end
	end
end

-- Shows one page; unknown or hidden pages (e.g. tab numbers saved by older versions) fall back to the rules.
local function ShowPage(key)
	if not IsPageAvailable(key) then
		key = "rules"
	end
	ns.db.lastTab = key
	if key ~= "settings" then
		lastTab = key
	end
	for pageKey, page in pairs(pages) do
		page:SetShown(pageKey == key)
	end
	for tabKey, button in pairs(tabButtons) do
		if tabKey == key then
			button:LockHighlight()
		else
			button:UnlockHighlight()
		end
	end
	controls.settingsButton:SetButtonState(key == "settings" and "PUSHED" or "NORMAL", key == "settings")
	UI.Refresh()
end

-- Opens the window on the given page.
local function OpenPage(key)
	ns.db.lastTab = key
	if frame and frame:IsShown() then
		ShowPage(key)
	else
		UI.Show()
	end
end

function UI.ShowAudit(name)
	if name then
		audit.selected = ns.Guild.NormalizeName(name)
	end
	OpenPage("audit")
end

function UI.ShowSettings()
	OpenPage("settings")
end

function UI.ShowDeathlog()
	OpenPage("deathlog")
end

-- Gear button left of the close button in the title bar; toggles the settings page.
local function CreateSettingsButton(f)
	local button = CreateFrame("Button", addonName .. "SettingsButton", f)
	button:SetSize(18, 18)
	if f.CloseButton then
		button:SetPoint("RIGHT", f.CloseButton, "LEFT", -SETTINGS_BUTTON_GAP, 0)
	else
		button:SetPoint("TOPRIGHT", -26 - SETTINGS_BUTTON_GAP, -3)
	end
	local icon = SETTINGS_ICONS[#SETTINGS_ICONS]
	for _, path in ipairs(SETTINGS_ICONS) do
		if FileExists(path) then
			icon = path
			break
		end
	end
	button:SetNormalTexture(icon)
	button:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button:SetPushedTexture(icon)
	button:GetPushedTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button:GetPushedTexture():SetVertexColor(0.6, 0.6, 0.6)
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetScript("OnClick", function()
		ShowPage(ns.db.lastTab == "settings" and lastTab or "settings")
	end)
	AttachTooltip(button, L.BTN_SETTINGS, L.BTN_SETTINGS_TIP)
	return button
end

local function CreateMainFrame()
	local f = CreateFrame("Frame", addonName .. "Frame", UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(WIDTH, HEIGHT)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relativePoint, x, y = self:GetPoint()
		ns.db.window = { point = point, relativePoint = relativePoint, x = x, y = y }
	end)
	local position = ns.db.window
	if position.point then
		f:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
	else
		f:SetPoint("CENTER")
	end
	f:Hide()
	tinsert(UISpecialFrames, f:GetName())

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", 0, -5)
	title:SetText(("%s |cff999999v%s|r"):format(ns.title, ns.version))

	local function CreatePage(key)
		local page = CreateFrame("Frame", nil, f)
		page:SetPoint("TOPLEFT", 0, -110)
		page:SetPoint("BOTTOMRIGHT", 0, 74)
		page:Hide()
		pages[key] = page
		return page
	end
	for _, tab in ipairs(TABS) do
		tabButtons[tab.key] = CreateButton(f, L[tab.label], 140, function() ShowPage(tab.key) end)
		CreatePage(tab.key)
	end
	LayoutTabs()
	BuildRulesPanel(pages.rules)
	BuildProfessionsPanel(pages.professions)
	BuildFinderPanel(pages.finder)
	BuildDeathlogPanel(pages.deathlog)
	BuildAuditPanel(pages.audit)
	BuildSettingsPanel(CreatePage("settings"))
	controls.settingsButton = CreateSettingsButton(f)

	local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("TOPLEFT", LEFT + 2, -62)
	status:SetPoint("RIGHT", -16, 0)
	status:SetJustifyH("LEFT")
	status:SetSpacing(3)
	controls.status = status

	-- Bottom: hint on the left, buttons on the right
	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOMLEFT", LEFT + 4, 18)
	hint:SetWidth(RIGHT - LEFT - 20)
	hint:SetJustifyH("LEFT")
	controls.hint = hint

	local buttonWidth = 186
	controls.publish = CreateButton(f, L.BTN_PUBLISH, buttonWidth, function() ns.Guild.PublishRules() end)
	controls.publish:SetPoint("BOTTOMRIGHT", -16, 42)
	AttachTooltip(controls.publish, L.BTN_PUBLISH, L.BTN_PUBLISH_TIP)
	local log = CreateButton(f, L.BTN_LOG, buttonWidth, function() ns.MessageWindow.Show("blocked") end)
	log:SetPoint("BOTTOMRIGHT", -16, 14)
	local check = CreateButton(f, L.BTN_CHECK, buttonWidth, function() ns.Comm.StartCheck() end)
	check:SetPoint("RIGHT", log, "LEFT", -8, 0)

	f:SetScript("OnShow", function()
		ShowPage(ns.db.lastTab)
	end)
	return f
end

function UI.Refresh()
	if not frame or not frame:IsShown() then
		return
	end
	-- The professions and dungeon finder tabs come and go with the guild rules.
	LayoutTabs()
	if not IsPageAvailable(ns.db.lastTab) then
		ShowPage("rules")
		return
	end
	local Rules, Guild = ns.Rules, ns.Guild
	local fromGuild = Rules.FromGuild()
	-- Officers edit their local settings as a draft even while guild rules apply.
	local officer = Guild.CanPublish()
	local lockLevel = Rules.GetGroupLockLevel()

	local lines = {}
	if IsInGuild() then
		lines[1] = L.STATUS_GUILD:format(Guild.GetName() or "?", Guild.GetMemberCount())
	else
		lines[1] = L.STATUS_NO_GUILD
	end
	lines[2] = fromGuild and L.STATUS_SOURCE_GUILD or L.STATUS_SOURCE_LOCAL
	if lockLevel == 0 then
		lines[3] = L.STATUS_GROUP_OFF
	else
		lines[3] = L.STATUS_GROUP:format(lockLevel, UnitLevel("player"), Rules.IsGroupLocked() and L.STATUS_LOCKED or L.STATUS_UNLOCKED)
	end
	controls.status:SetText(table.concat(lines, "\n"))

	for _, checkbox in ipairs(ruleCheckboxes) do
		local key = checkbox.ruleKey
		local editable = officer or not Rules.IsGuildSetting(key)
		local value
		if editable then
			value = ns.db.rules[key]
		else
			value = Rules.Get(key)
		end
		checkbox:SetChecked(value and true or false)
		checkbox:SetEnabled(editable)
		checkbox.label:SetFontObject(editable and "GameFontHighlight" or "GameFontDisable")
	end
	for _, checkbox in ipairs(personalCheckboxes) do
		checkbox:SetChecked(ns.db[checkbox.group][checkbox.key] and true or false)
	end

	local lockEditable = officer or not Rules.IsGuildSetting("groupLockLevel")
	SetFieldText(controls.groupLock, tostring(lockEditable and ns.db.rules.groupLockLevel or lockLevel))
	controls.groupLock:SetEnabled(lockEditable)

	local partnersEditable = officer or not Rules.IsGuildSetting("partnerGuilds")
	local partnerList = partnersEditable and ns.db.partnerGuilds or Rules.GetPartnerGuilds()
	SetFieldText(controls.partners, table.concat(partnerList, ", "))
	controls.partners:SetEnabled(partnersEditable)

	SetFieldText(controls.leaveDelay, tostring(ns.db.groupLeaveDelay))
	SetFieldText(controls.deathMinLevel, tostring(ns.db.notify.deathMinLevel))

	if fromGuild then
		controls.hint:SetText(officer and L.OFFICER_DRAFT_HINT or L.GUILD_RULES_LOCKED_HINT)
	else
		controls.hint:SetText(L.LOCAL_RULES_HINT)
	end
	controls.publish:SetEnabled(officer)

	UI.RefreshDeathlog()
	UI.RefreshAudit()
	UI.RefreshProfessions()
	UI.RefreshFinder()
end

function UI.Show()
	if not frame then
		frame = CreateMainFrame()
	end
	frame:Show()
end

function UI.Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		UI.Show()
	end
end

ns.RegisterCallback("RULES_CHANGED", UI.Refresh)
ns.RegisterCallback("RULES_CHANGED", CheckCopyDialog)
ns.RegisterCallback("ROSTER_UPDATED", UI.Refresh)
ns.RegisterCallback("DEATHLOG_UPDATED", UI.RefreshDeathlog)
ns.RegisterCallback("AUDIT_UPDATED", UI.RefreshAudit)
ns.RegisterCallback("PROFESSIONS_UPDATED", UI.RefreshProfessions)
ns.RegisterCallback("FINDER_UPDATED", UI.RefreshFinder)
ns.RegisterCallback("AUDIT_ITEMS_LOADED", function()
	C_Timer.After(0.2, UI.RefreshAudit)
end)
ns.On("PLAYER_LEVEL_UP", function()
	C_Timer.After(0.5, UI.Refresh)
end)

---------------------------------------------------------------------------
-- Settings panel entry and addon compartment (minimap addon menu)
---------------------------------------------------------------------------

ns.RegisterCallback("INIT", function()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
		return
	end
	local panel = CreateFrame("Frame")
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(ns.title)
	local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	text:SetPoint("RIGHT", -16, 0)
	text:SetJustifyH("LEFT")
	text:SetText(L.SETTINGS_DESC)
	local open = CreateButton(panel, L.BTN_OPEN, 160, UI.Show)
	open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
	Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(panel, ns.title))
end)

function GuildFoundForever_OnAddonCompartmentClick()
	UI.Toggle()
end

function GuildFoundForever_OnAddonCompartmentEnter(_, menuButton)
	GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
	GameTooltip:SetText(ns.title, 1, 1, 1)
	GameTooltip:AddLine(L.COMPARTMENT_TIP, nil, nil, nil, true)
	GameTooltip:Show()
end

function GuildFoundForever_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
