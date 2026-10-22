local _, ns = ...

-- The audit protocol between players. Members push their own new entries to at most RECIPIENTS
-- online holders (officers, or members when the guild rule V is on). The online holders, sorted by
-- key, form a ring; each one syncs in turn with its successor, its predecessor and the holder
-- half-way round, one per round, so an entry reaches every holder with at most three transfers
-- each. Every message goes through one paced queue. The engine talks to the game only through the
-- env table given to Sync.New, so the tests can run several players in one Lua state. No WoW API
-- calls, no module state.
--
-- Messages (all whispered):
--   AUDX <member>\t<raw>\030<raw>...   entries about members; several groups of
--        [\029<member>\t<raw>...]       "<member>\t<raws>" joined by character 29
--   AUDS <since1>\t<since2>            "send me what you stored since these times" (tier 1, tier 2)
--   AUDE <tier>\t<now>                 end of tier 1 or 2 of an AUDS answer, or of an AUDM answer (3)
--   AUDM <member>\t<since>             ask for the details (tier 2) of one member
--
-- env, every field required:
--   self, selfName               own key and full name
--   key(name)                    normalized key of a name
--   now()                        server time
--   after(seconds, fn)           timer
--   send(message, target)        whisper to a full name, returns ok, code; code "retry" (throttled)
--                                means the same message is tried again
--   holders()                    { { key, name }, ... }: online officers and relays with capability A, not self
--   isHolder(key)                officer or relay, online or not
--   capable(key)                 online with capability A
--   isMember(key)                in the guild roster
--   amHolder()                   whether we are an officer or relay ourselves
--   store()                      the guild's store, nil without a role or guild name; the engine
--                                keeps gs.peers[key] = { s1, s2 } and gs.base in it
--   ownSince(since)              own encoded entries from since on (Audit.OwnRaws)
--   sent()                       push watermark per recipient, [key] = time
--   onStored(key, raw, at)       a foreign entry was newly stored
--   onSyncDone(peerKey, tier)    tier 1 or 2 of a sync with that peer is complete
local R = ns.AuditRecords
local St = ns.AuditStore
local Sync = {}
ns.AuditSync = Sync

Sync.RECIPIENTS = 3
Sync.PACE_SECONDS = 1
Sync.BUNDLE_SECONDS = 2
Sync.INTERVAL_SECONDS = 300
Sync.FIRST_CONTACT_SECONDS = 864000
Sync.MESSAGE_LIMIT = 240
-- A throttled message stays at the head and is tried again RETRY_SECONDS later, RETRIES times at most.
Sync.RETRIES = 10
Sync.RETRY_SECONDS = 3 * Sync.PACE_SECONDS

local SEPARATOR = "\030"
local GROUP = "\029"
local HEAD = "AUDX\t"

-- Queue priorities, the lowest goes first; within one priority first in, first out.
local ASK, OWN, MEMBER_ANSWER, TIER1_ANSWER, TIER2_ANSWER = 0, 1, 2, 3, 4
local LAST_PRIORITY = TIER2_ANSWER

-- djb2 over "member|holder": every member ranks the holders in its own fixed order.
function Sync.Score(memberKey, holderKey)
	local h, s = 5381, memberKey .. "|" .. holderKey
	for i = 1, #s do
		h = (h * 33 + s:byte(i)) % 4294967296
	end
	return h
end

local function TierOf(raw)
	return R.Tier((strsplit("\t", raw)))
end

-- A copy of the holders, highest Score(memberKey, holder) first; ties by key.
local function Ranked(holders, memberKey)
	local list, scores = {}, {}
	for _, holder in ipairs(holders or {}) do
		list[#list + 1] = holder
		scores[holder.key] = Sync.Score(memberKey, holder.key)
	end
	table.sort(list, function(a, b)
		if scores[a.key] ~= scores[b.key] then
			return scores[a.key] > scores[b.key]
		end
		return a.key < b.key
	end)
	return list
end

-- Cuts text to at most n bytes without splitting a UTF-8 character.
local function Cut(text, n)
	if #text <= n then
		return text
	end
	while n > 0 do
		local byte = text:byte(n + 1)
		if byte < 128 or byte >= 192 then
			break
		end
		n = n - 1
	end
	return text:sub(1, n)
end

-- AUDX messages for a list of { name, raws }: per member a group "<name>\t<raw>\030<raw>...",
-- groups joined by character 29, each message within MESSAGE_LIMIT. No entries, no message.
local function Pack(entries)
	local messages, current, open = {}, nil, nil
	for _, entry in ipairs(entries) do
		local room = Sync.MESSAGE_LIMIT - #HEAD - #entry.name - 1
		for _, raw in ipairs(entry.raws) do
			raw = Cut(raw, room)
			local piece = nil
			if current then
				piece = open == entry and (SEPARATOR .. raw) or (GROUP .. entry.name .. "\t" .. raw)
			end
			if piece and #current + #piece <= Sync.MESSAGE_LIMIT then
				current = current .. piece
			else
				if current then
					messages[#messages + 1] = current
				end
				current = HEAD .. entry.name .. "\t" .. raw
			end
			open = entry
		end
	end
	if current then
		messages[#messages + 1] = current
	end
	return messages
end

-- The given lists merged without duplicates, tier 1 before tier 2, otherwise in order.
local function Ordered(...)
	local seen, first, second = {}, {}, {}
	for i = 1, select("#", ...) do
		for _, raw in ipairs(select(i, ...) or {}) do
			if raw ~= "" and not seen[raw] then
				seen[raw] = true
				local list = TierOf(raw) == 2 and second or first
				list[#list + 1] = raw
			end
		end
	end
	for _, raw in ipairs(second) do
		first[#first + 1] = raw
	end
	return first
end

---------------------------------------------------------------------------
-- The paced queue: one message per PACE_SECONDS for all audit messages together
---------------------------------------------------------------------------

local Pump

-- A failed send (any failure but a "retry" within RETRIES) drops every message still waiting for
-- that target. A recipient that missed
-- messages gets a full push next time; we stop waiting for the answer of a peer we asked.
local function Drop(self, key)
	for prio = 0, LAST_PRIORITY do
		local kept = {}
		for _, item in ipairs(self.queues[prio]) do
			if item.key ~= key then
				kept[#kept + 1] = item
			end
		end
		self.queues[prio] = kept
	end
	self.pushed[key] = nil
	self.asked[key] = nil
end

-- Sends the head message: a throttled one ("retry") waits in self.head ahead of everything else.
function Pump(self)
	local item = self.head
	self.head = nil
	if not item then
		for prio = 0, LAST_PRIORITY do
			local list = self.queues[prio]
			if list[1] then
				item = table.remove(list, 1)
				break
			end
		end
	end
	if not item then
		self.pumping = false
		return
	end
	local ok, code = self.env.send(item.message, item.target)
	local wait = Sync.PACE_SECONDS
	if ok then
		if item.done then
			item.done()
		end
	elseif code == "retry" and item.tries < Sync.RETRIES then
		item.tries = item.tries + 1
		self.head = item
		wait = Sync.RETRY_SECONDS
	else
		Drop(self, item.key)
	end
	self.env.after(wait, function()
		Pump(self)
	end)
end

-- done runs once the message went out successfully.
local function Queue(self, prio, target, message, done)
	local list = self.queues[prio]
	list[#list + 1] = { prio = prio, target = target, key = self.env.key(target), message = message, done = done, tries = 0 }
	if not self.pumping then
		self.pumping = true
		self.env.after(0, function()
			Pump(self)
		end)
	end
end

local function Waiting(self, prio, key)
	local head = self.head
	if head and head.prio == prio and head.key == key then
		return true
	end
	for _, item in ipairs(self.queues[prio]) do
		if item.key == key then
			return true
		end
	end
	return false
end

-- Queues entries ({ { name, raws }, ... }) for a target ({ key, name }). With watermark, the
-- target's push watermark moves there once the last of these messages went out.
local function QueueRaws(self, prio, target, entries, watermark)
	local messages = Pack(entries)
	local done = watermark and function()
		self.env.sent()[target.key] = watermark
	end or nil
	for i, message in ipairs(messages) do
		Queue(self, prio, target.name, message, i == #messages and done or nil)
	end
end

---------------------------------------------------------------------------
-- Own data to the recipients
---------------------------------------------------------------------------

-- Everything since the recipient's watermark (the last 10 days on first contact) plus extra.
local function PushOwn(self, recipient, extra)
	local env = self.env
	local now = env.now()
	local since = env.sent()[recipient.key] or (now - Sync.FIRST_CONTACT_SECONDS)
	self.pushed[recipient.key] = true
	QueueRaws(self, OWN, recipient, { { name = env.selfName, raws = Ordered(env.ownSince(since), extra) } }, now)
end

-- Recipients without a full push this session get one; the others get just the extra entries.
local function Distribute(self, extra)
	local list = self:Recipients()
	local current = {}
	for _, recipient in ipairs(list) do
		current[recipient.key] = true
	end
	for key in pairs(self.pushed) do
		if not current[key] then
			self.pushed[key] = nil
		end
	end
	for _, recipient in ipairs(list) do
		if not self.pushed[recipient.key] then
			PushOwn(self, recipient, extra)
		elseif extra and #extra > 0 then
			QueueRaws(self, OWN, recipient, { { name = self.env.selfName, raws = Ordered(extra) } }, self.env.now())
		end
	end
end

---------------------------------------------------------------------------
-- Sync between holders
---------------------------------------------------------------------------

local function IsHolder(self)
	return self.env.amHolder() and self.env.store() ~= nil
end

-- Sync partners in the ring of the online holders and ourselves, sorted by key: successor,
-- predecessor and the holder half-way round; at most three, never ourselves.
local function Partners(self, holders)
	local env = self.env
	local ring = { { key = env.self, name = env.selfName } }
	for _, holder in ipairs(holders or {}) do
		if holder.key ~= env.self then
			ring[#ring + 1] = holder
		end
	end
	table.sort(ring, function(a, b)
		return a.key < b.key
	end)
	local n, at = #ring, 1
	for i, holder in ipairs(ring) do
		if holder.key == env.self then
			at = i
		end
	end
	local list, seen = {}, { [env.self] = true }
	for _, step in ipairs({ 1, -1, math.floor(n / 2) }) do
		local peer = ring[(at - 1 + step) % n + 1]
		if not seen[peer.key] then
			seen[peer.key] = true
			list[#list + 1] = peer
		end
	end
	return list
end

-- A peer without a mark is asked from gs.base on: a round before our first completed tier 2 sync,
-- 0 before that. So only our very first partner sends us its whole store.
local function Ask(self, peer)
	local gs = self.env.store()
	local mark = gs.peers and gs.peers[peer.key] or {}
	local base = gs.base or 0
	Queue(self, ASK, peer.name, "AUDS\t" .. (mark.s1 or base) .. "\t" .. (mark.s2 or base))
	self.asked[peer.key] = self.env.now()
	self.lastAsked = peer.key
end

-- One tier of an AUDS answer: AUDX with every member but the asker, then AUDE with the time the
-- answer was taken from the store, so entries stored in that same second come again next time.
local function Answer(self, gs, target, since, tier, prio, now)
	local entries = {}
	for _, entry in ipairs(St.Since(gs, since, tier)) do
		if entry.key ~= target.key then
			entries[#entries + 1] = { name = entry.name or entry.key, raws = entry.raws }
		end
	end
	QueueRaws(self, prio, target, entries)
	Queue(self, prio, target.name, "AUDE\t" .. tier .. "\t" .. now)
end

local HANDLERS = {}

-- Every group is checked on its own: from the member itself or from a holder.
function HANDLERS.AUDX(self, sender, senderKey, payload)
	local env = self.env
	if not env.amHolder() then
		return
	end
	local gs = env.store()
	if not gs then
		return
	end
	local now = env.now()
	for group in payload:gmatch("[^\029]+") do
		local name, list = strsplit("\t", group, 2)
		local key = name and name ~= "" and list and env.key(name) or nil
		if key and key ~= env.self and env.isMember(key) and (senderKey == key or env.isHolder(senderKey)) then
			for raw in list:gmatch("[^\030]+") do
				if St.Add(gs, key, name, raw, now) then
					env.onStored(key, raw, now)
				end
			end
		end
	end
end

function HANDLERS.AUDS(self, sender, senderKey, payload)
	local env = self.env
	if senderKey == env.self or not env.amHolder() or not env.isHolder(senderKey) then
		return
	end
	local gs = env.store()
	if not gs then
		return
	end
	local since1, since2 = strsplit("\t", payload)
	local now, target = env.now(), { key = senderKey, name = sender }
	Answer(self, gs, target, tonumber(since1) or 0, 1, TIER1_ANSWER, now)
	-- While an earlier tier 2 answer to this peer is still waiting, it alone goes on: its AUDE 2
	-- moves the peer's mark, and the next AUDS covers what came since.
	if not Waiting(self, TIER2_ANSWER, senderKey) then
		Answer(self, gs, target, tonumber(since2) or 0, 2, TIER2_ANSWER, now)
	end
end

-- Only from a peer we asked. Tier 3 (end of an AUDM answer) needs nothing: its entries came as AUDX.
function HANDLERS.AUDE(self, sender, senderKey, payload)
	local env = self.env
	local tier, at = strsplit("\t", payload)
	tier, at = tonumber(tier), tonumber(at)
	if (tier ~= 1 and tier ~= 2) or not at or not self.asked[senderKey] or not env.amHolder() then
		return
	end
	local gs = env.store()
	if not gs then
		return
	end
	gs.peers = gs.peers or {}
	local mark = gs.peers[senderKey] or {}
	gs.peers[senderKey] = mark
	if tier == 1 then
		mark.s1 = at
	else
		mark.s2 = at
		self.asked[senderKey] = nil
		if not gs.base then
			gs.base = at - Sync.INTERVAL_SECONDS
		end
	end
	self.syncAt, self.syncName = env.now(), sender
	env.onSyncDone(senderKey, tier)
end

-- Only holders get details: about ourselves from our own data, about others from the store.
function HANDLERS.AUDM(self, sender, senderKey, payload)
	local env = self.env
	local name, since = strsplit("\t", payload)
	since = tonumber(since) or 0
	if not name or name == "" or senderKey == env.self or not env.isHolder(senderKey) then
		return
	end
	local key = env.key(name)
	if key == senderKey then
		return
	end
	local target = { key = senderKey, name = sender }
	if key == env.self then
		local raws = {}
		for _, raw in ipairs(env.ownSince(since) or {}) do
			if TierOf(raw) == 2 then
				raws[#raws + 1] = raw
			end
		end
		QueueRaws(self, MEMBER_ANSWER, target, { { name = env.selfName, raws = raws } })
	else
		local gs = env.amHolder() and env.store()
		if not gs then
			return
		end
		local entries = {}
		for _, entry in ipairs(St.Since(gs, since, 2, key)) do
			entries[#entries + 1] = { name = entry.name or entry.key, raws = entry.raws }
		end
		QueueRaws(self, MEMBER_ANSWER, target, entries)
	end
	Queue(self, MEMBER_ANSWER, sender, "AUDE\t3\t" .. env.now())
end

---------------------------------------------------------------------------
-- The engine
---------------------------------------------------------------------------

local Engine = {}
Engine.__index = Engine

function Sync.New(env)
	local self = setmetatable({ env = env, queues = {}, pumping = false, pushed = {}, asked = {}, round = 0 }, Engine)
	for prio = 0, LAST_PRIORITY do
		self.queues[prio] = {}
	end
	return self
end

-- Clears the queue, sends the own data to the recipients and, as a holder, syncs with our
-- successor in the ring.
function Engine:Start()
	for prio = 0, LAST_PRIORITY do
		self.queues[prio] = {}
	end
	self.head = nil
	self.pushed, self.asked, self.lastAsked, self.round = {}, {}, nil, 0
	local extra = self.bundle
	self.bundle = nil
	Distribute(self, extra)
	if IsHolder(self) then
		local successor = Partners(self, self.env.holders())[1]
		if successor then
			Ask(self, successor)
			self.round = 1
		end
	end
end

-- New recipients get the own data since their watermark.
function Engine:PeersChanged()
	Distribute(self, nil)
end

-- A new own entry; everything recorded within BUNDLE_SECONDS goes out together.
function Engine:Record(raw)
	if not raw or raw == "" then
		return
	end
	self.bundle = self.bundle or {}
	self.bundle[#self.bundle + 1] = raw
	if not self.bundling then
		self.bundling = true
		self.env.after(Sync.BUNDLE_SECONDS, function()
			self.bundling = false
			local raws = self.bundle
			self.bundle = nil
			if raws then
				Distribute(self, raws)
			end
		end)
	end
end

-- One sync with the next of our ring partners in turn. Skipped while the last asked peer is online
-- and has not finished (AUDE 2), at most for three intervals.
function Engine:Tick()
	local env = self.env
	if not IsHolder(self) then
		return
	end
	local holders, now = env.holders() or {}, env.now()
	local asked = self.lastAsked and self.asked[self.lastAsked]
	if asked and now - asked < 3 * Sync.INTERVAL_SECONDS then
		for _, holder in ipairs(holders) do
			if holder.key == self.lastAsked then
				return
			end
		end
	end
	local partners = Partners(self, holders)
	if #partners == 0 then
		return
	end
	local peer = partners[self.round % #partners + 1]
	self.round = self.round + 1
	Ask(self, peer)
end

function Engine:Handle(sender, command, payload)
	local handler = HANDLERS[command]
	if handler and sender and sender ~= "" and payload then
		handler(self, sender, self.env.key(sender), payload)
	end
end

-- Details of one member: from the member while it is online with the new version, else from the
-- holder ranked highest for that member (its first recipient).
function Engine:RequestMember(key, name)
	local env = self.env
	name = name or key
	if not key or key == env.self or not IsHolder(self) then
		return
	end
	local target = nil
	if env.capable(key) then
		target = name
	else
		local best = Ranked(env.holders(), key)[1]
		target = best and best.name
	end
	if target then
		Queue(self, ASK, target, "AUDM\t" .. name .. "\t" .. (env.now() - Sync.FIRST_CONTACT_SECONDS))
	end
end

-- The RECIPIENTS holders ranked highest for us.
function Engine:Recipients()
	local ranked, list = Ranked(self.env.holders(), self.env.self), {}
	for i = 1, math.min(Sync.RECIPIENTS, #ranked) do
		list[i] = { key = ranked[i].key, name = ranked[i].name }
	end
	return list
end

function Engine:Queued()
	local count = self.head and 1 or 0
	for prio = 0, LAST_PRIORITY do
		count = count + #self.queues[prio]
	end
	return count
end

function Engine:LastSync()
	return self.syncAt, self.syncName
end
