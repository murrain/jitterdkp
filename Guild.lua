-- Tracks guild info
local addonName, addonTable = ...

local guild = {}
addonTable.guild = guild

local utils = addonTable.utilities

local ADDON_MSG_PREFIX = addonName .. "Guild"

local defaults = {
	profile = {
		cache = {}
	}
}

LibStub("AceEvent-3.0"):Embed(guild)
LibStub("AceComm-3.0"):Embed(guild)
LibStub("AceSerializer-3.0"):Embed(guild)
LibStub("AceTimer-3.0"):Embed(guild)

function guild:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("JitterDKPDB_Data",defaults)

	self.guild_info = {}
	self.cachedPlayers = {}
	self.lastUpdate = 0 

	self.pendingChanges = {public = {}, officer = {}}
	self.pendingTimer = nil

	hooksecurefunc("GuildRosterSetPublicNote", function (...)
		self:Hook_GuildRosterSetPublicNote(...)
	end)
	hooksecurefunc("GuildRosterSetOfficerNote", function (...)
		self:Hook_GuildRosterSetOfficerNote(...)
	end)
end

function guild:OnEnable()
	self:RegisterEvent("GUILD_ROSTER_UPDATE")

	self:RegisterComm(ADDON_MSG_PREFIX)

	if IsInGuild() and GetGuildInfo("player") then
		self:ScanGuild()
	end
end

function guild:Hook_GuildRosterSetPublicNote(idx, note)
	local fullname = GetGuildRosterInfo(idx)
	local words = {}
	if not fullname then return end -- wtf?
	for word in fullname:gmatch("([^-]+)") do
		table.insert(words,word)
	end
	name = words[1]
	realm = words[2]

	local info = self.guild_info[name]
	if info then
		info.note.note = note
		info.note.cached = true
		table.insert(self.cachedPlayers, name)
	end
	self.pendingChanges.public[name] = note
	self:setupPendingTimer()
end

function guild:Hook_GuildRosterSetOfficerNote(idx, note)
	local fullname = GetGuildRosterInfo(idx)
	local words = {}
	if not fullname then return end -- wtf?
	for word in fullname:gmatch("([^-]+)") do
		table.insert(words,word)
	end
	name = words[1]
	realm = words[2]
	local info = self.guild_info[name]
	if info then
		info.officernote.note = note
		info.officernote.cached = true
		table.insert(self.cachedPlayers, name)
	end
	self.pendingChanges.officer[name] = note
	self:setupPendingTimer()
end

function guild:setupPendingTimer()
	if not self.pendingTimer then
		self.pendingTimer = self:ScheduleTimer(function ()
			if next(self.pendingChanges.public) then
				local names, notes = {}, {}
				for k,v in pairs(self.pendingChanges.public) do
					table.insert(names, k)
					table.insert(notes, v)
				end
				self:broadcastChanges("N", names, notes)
				table.wipe(self.pendingChanges.public)
			end
			if next(self.pendingChanges.officer) then
				local names, notes = {}, {}
				for k,v in pairs(self.pendingChanges.officer) do
					table.insert(names, k)
					table.insert(notes, v)
				end
				self:broadcastChanges("O", names, notes)
				table.wipe(self.pendingChanges.officer)
			end
			self.pendingTimer = nil
		end, 0.1)
	end
end

local eventIdxs = {}
function guild:OnCommReceived(prefix, message, channel, sender)
	if sender == UnitName("player") then return end -- ignore messages from self
	local command, idx, rest = strsplit(" ", message, 3)
	if command == "Event" then
		local tbl = eventIdxs[sender] or {} -- reuse tables if we can
		tbl[idx] = GetTime()
		eventIdxs[sender] = tbl
	else
		-- Assuming messages always arrive in the same order they were broadcast, we can
		-- safely process all events, even if multiple events are broadcast before we
		-- process any. However, we should not process any events that were fired after
		-- we last updated the guild roster.
		local eventTime
		if eventIdxs[sender] then
			eventTime = eventIdxs[sender][idx]
			eventIdxs[sender][idx] = nil
		end
		if (eventTime or -1) < self.lastUpdate then
			return
		end
		if command == "N" or command == "O" then
			local key = command == "N" and "note" or "officernote"
			local success, names, notes = self:Deserialize(rest)
			if success then
				for _,name,note in utils.ipairs(names, notes) do
					local info = self.guild_info[name]
					if info then
						info[key].note = note
						info[key].cached = true
					end
				end
			end
			GuildRoster()
		end -- N or O
	end
end

function guild:GUILD_ROSTER_UPDATE(event, update)
	local name, rank, rankIndex = GetGuildInfo("player")
	if update or name ~= self.guild_info.name then
		self:ScanGuild()
	elseif #self.cachedPlayers > 0 then
		-- scan just those players
		for _,name in self.cachedPlayers do
			local info = self.guild_info[name]
			if info then
				local fullname, rank, rankIndex, level, class, zone, note, officernote, online, status, classFileName, achievementPoints, achievementRank, isMobile = GetGuildRosterInfo(info.index)
				for word in fullname:gmatch("([^-]+)") do
					table.insert(words,word)
				end
				name = words[1]
				realm = words[2]
				if name ~= info.name then
					-- indexes changed? Weird. Rescan the guild
					self:ScanGuild()
					break
				end
				info.note.note = note
				info.note.cached = false
				info.officernote.note = officernote
				info.officernote.cached = false
			end
		end
		table.wipe(self.cachedPlayers)
	end
	self.lastUpdate = GetTime()
end

function guild:ScanGuild()
	if not IsInGuild() then
		-- we're not in a guild at this point
		table.wipe(self.guild_info)
		return
	end
	for i = 1, GetNumGuildMembers() do
		local words = {}
		local fullname, rank, rankIndex, level, class, zone, note, officernote, online, status, classFileName, achievementPoints, achievementRank, isMobile = GetGuildRosterInfo(i)
		-- re-use tables if we can, to help the GC
		for word in fullname:gmatch("([^-]+)") do
			table.insert(words,word)
		end
		name = words[1]
		realm = words[2]
		local entry = self.guild_info[name] or {note={}, officernote={}}
		entry.index = i
		entry.rank = rank
		entry.rankIndex = rankIndex
		entry.level = level
		entry.class = class
		entry.note.note = note
		entry.note.cached = false
		entry.officernote.note = officernote
		entry.officernote.cached = false
		entry.mark = true
		self.guild_info[name] = entry
	end
	for k,v in pairs(self.guild_info) do
		if v.mark then
			v.mark = nil
		else
			self.guild_info[k] = nil
		end
	end
end

local broadcastIdx = 0
function guild:broadcastChanges(type, names, notes)
	-- send an alert with an integer first, before sending the bulk event
	-- this lets the receiver ignore the bulk event if it finishes arriving after they get a guild update
	broadcastIdx = broadcastIdx + 1
	self:SendCommMessage(ADDON_MSG_PREFIX, "Event " .. broadcastIdx, "GUILD", nil, "ALERT")
	self:SendCommMessage(ADDON_MSG_PREFIX, type .. " " .. broadcastIdx .. " " .. self:Serialize(names, notes), "GUILD")
end

-- validates that the local info has the correct index for each name
function guild:validateIndexes(names)
	for i,name in ipairs(names) do
		local info = self.guild_info[name]
		if info then
			local fullname = GetGuildRosterInfo(info.index)
			local words = {}
			for word in fullname:gmatch("([^-]+)") do
				table.insert(words,word)
			end
			gname = words[1]
			realm = words[2]
			if gname ~= name then
				self:ScanGuild()
				break
			end
		end
	end
end

function guild:OfficerNote(name)
	assert(type(name) == "string")
	return self.guild_info[name] and self.guild_info[name].officernote.note or nil
end

function guild:SetOfficerNote(name, note)
	assert(type(name) == "string")
	assert(type(note) == "string")
	self:validateIndexes({name})
	local info = self.guild_info[name]
	if info then
		info.officernote.note = note
		info.officernote.cached = true
		table.insert(self.cachedPlayers, name)
		GuildRosterSetOfficerNote(info.index, note)
	end
	local cache_note = {}
	cache_note["note"] = info.note.note
	cache_note["dkp"] = note
	cache_note["last_seen"] = date("%m/%d/%y %H:%M:%S")
	self.db.profile.cache[name] = cache_note
end

-- bulk-set officer notes
-- input is 2 parallel arrays
function guild:SetOfficerNotes(names, notes)
	assert(type(notes) == "table")
	assert(type(names) == "table")
	assert(#names == #notes)
	self:validateIndexes(names)
	for i,name,note in utils.ipairs(names, notes) do
		self:SetOfficerNote(name, note)
	end
end

function guild:GuildNote(name)
	assert(type(name) == "string")
	return self.guild_info[name] and self.guild_info[name].note.note or nil
end

function guild:SetGuildNote(name, note)
	assert(type(name) == "string")
	assert(type(note) == "string")
	self:validateIndexes({name})
	local info = self.guild_info[name]
	if info then
		info.note.note = note
		info.note.cached = true
		table.insert(self.cachedPlayers, name)
		GuildRosterSetPublicNote(info.index, note)
	end
end

-- bulk-set notes
-- input is 2 parallel arrays
function guild:SetGuildNotes(names, notes)
	assert(type(notes) == "table")
	assert(type(names) == "table")
	assert(#names == #notes)
	self:validateIndexes(names)
	for i,name,note in utils.ipairs(names, notes) do
		self:SetGuildNote(name, note)
	end
end

function guild:IsInGuild(name)
	assert(type(name) == "string")
	return not not self.guild_info[name]
end

local function makeIter(key)
	return function (t, obj)
		local k,v = next(t, obj)
		if k == nil then return nil end
		return k, v[key].note
	end
end

local function makeIterRaidGroup(key)
	return function (t, obj)
		local raider = {}
		local k,v = next(t, obj)
		if k == nil then return nil end
		raider.group = v.note.note
		raider.note = v[key].note
		return k, raider
	end
end

function guild:GuildNotePairs()
	return makeIter("note"), self.guild_info, nil
end

function guild:OfficerNotePairs()
	return makeIter("officernote"), self.guild_info, nil
end

function guild:OfficerNotePairsRaidGroup(raid_group)
	return makeIterRaidGroup("officernote"), self.guild_info, nil
end
