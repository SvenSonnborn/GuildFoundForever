local _, ns = ...

local Messages = {}
ns.Messages = Messages

local MAX_MESSAGES = 300

-- Order of the filters, colour { r, g, b } and icon per category. Missing icons fall back to a
-- square in the category's colour (MessageWindow.lua).
Messages.CATEGORIES = {
	{ key = "blocked", label = "MSG_CAT_BLOCKED", color = { 1, 0.33, 0.33 }, icon = "Interface\\Icons\\INV_Shield_06" },
	{ key = "guild", label = "MSG_CAT_GUILD", color = { 1, 0.82, 0 }, icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01" },
	{ key = "audit", label = "MSG_CAT_AUDIT", color = { 0.4, 0.73, 1 }, icon = "Interface\\Icons\\INV_Misc_Book_09" },
	{ key = "finder", label = "MSG_CAT_FINDER", color = { 0.33, 0.87, 0.47 }, icon = "Interface\\Icons\\INV_Sword_04" },
	{ key = "system", label = "MSG_CAT_SYSTEM", color = { 0.67, 0.67, 0.67 }, icon = "Interface\\Icons\\INV_Misc_Gear_01" },
}
local byKey = {}
for _, category in ipairs(Messages.CATEGORIES) do
	byKey[category.key] = category
end

-- Calls of ns.Print/Warn/Alert without a category while the modules move over (Core.lua).
Messages.legacyCalls = 0

local pending = {} -- messages from before the saved variables are loaded

function Messages.IsCategory(key)
	return byKey[key] ~= nil
end

function Messages.GetCategory(key)
	return byKey[key] or byKey.system
end

local function Store()
	return ns.char and ns.char.messages
end

local function Trim(store)
	while #store > MAX_MESSAGES do
		table.remove(store, 1)
	end
end

-- opts: details (further lines), link (item link for the tooltip), important (hint next to the
-- button), silent (counts as read). Returns the entry.
function Messages.Add(category, text, opts)
	opts = opts or {}
	if not byKey[category] then
		geterrorhandler()(("%s: unknown message category %s"):format(ns.name, tostring(category)))
		category = "system"
	end
	local entry = { t = GetServerTime(), c = category, m = tostring(text or ""), r = opts.silent and true or false }
	if opts.details and opts.details ~= "" then
		entry.d = opts.details
	end
	if opts.link then
		entry.l = opts.link
	end
	if opts.important then
		entry.i = true
	end
	local store = Store()
	if not store then
		pending[#pending + 1] = entry
		return entry
	end
	store[#store + 1] = entry
	Trim(store)
	ns.Fire("MESSAGES_UPDATED", entry)
	return entry
end

-- Newest first; category nil means all.
function Messages.GetList(category)
	local list, store = {}, Store() or {}
	for i = #store, 1, -1 do
		local entry = store[i]
		if not category or entry.c == category then
			list[#list + 1] = entry
		end
	end
	return list
end

function Messages.CountUnread(category)
	local count = 0
	for _, entry in ipairs(Store() or {}) do
		if not entry.r and (not category or entry.c == category) then
			count = count + 1
		end
	end
	return count
end

function Messages.HasImportantUnread()
	for _, entry in ipairs(Store() or {}) do
		if entry.i and not entry.r then
			return true
		end
	end
	return false
end

function Messages.MarkAllRead()
	for _, entry in ipairs(Store() or {}) do
		entry.r = true
	end
	ns.Fire("MESSAGES_UPDATED")
end

function Messages.Clear(category)
	local store = Store()
	if not store then
		return
	end
	for i = #store, 1, -1 do
		if not category or store[i].c == category then
			table.remove(store, i)
		end
	end
	ns.Fire("MESSAGES_UPDATED")
end

-- The blocked actions logged before there was a message window come over once, as read messages.
-- The log itself stays: officers fetch it in the audit.
function Messages.ImportLog()
	local char = ns.char
	if not char or char.messagesImported then
		return
	end
	char.messagesImported = true
	local merged = {}
	for _, logEntry in ipairs(char.log) do
		merged[#merged + 1] = { t = logEntry.t, c = "blocked", m = logEntry.m, r = true }
	end
	for _, entry in ipairs(char.messages) do
		merged[#merged + 1] = entry
	end
	Trim(merged)
	char.messages = merged
end

function Messages.FlushPending()
	local store = Store()
	if not store then
		return
	end
	for _, entry in ipairs(pending) do
		store[#store + 1] = entry
	end
	wipe(pending)
	Trim(store)
end

ns.RegisterCallback("INIT", function()
	Messages.ImportLog()
	Messages.FlushPending()
end)
