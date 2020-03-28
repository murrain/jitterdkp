local addonName, addonTable = ...

local utils = {}
addonTable.utilities = utils

-- stable mergesort
-- returns the sorted list
-- the comp function is optional, and if provided must return whether
-- the first argument is strictly less than the second. If not provided
-- the < operator is used instead
function utils.mergesort(t, comp)
	if #t <= 1 then return t end
	comp = comp or function(a,b) return a<b end
	local left, right, result = {}, {}, {}
	local pivot = math.floor(#t / 2)
	for i=1,pivot do
		table.insert(left, t[i])
	end
	for i=pivot+1,#t do
		table.insert(right, t[i])
	end
	left = utils.mergesort(left, comp)
	right = utils.mergesort(right, comp)
	local li, ri = 1, 1
	while #left >= li or #right >= ri do
		l, r = left[li], right[ri]
		if l and not (r and comp(r, l)) then
			table.insert(result, l)
			li = li + 1
		else -- not l, or r < l
			table.insert(result, r)
			ri = ri + 1
		end
	end
	return result
end

-- parallel ipairs
-- takes multiple tables, returns one value per table per iteration
-- if tables have different lengths, returns nil for the shorter tables' values
-- if given one argument, behaves identically to ipairs
function utils.ipairs(...)
	local results = {}
	return function (s, var)
		var = var + 1
		local nonnil = false
		for i,v in ipairs(s) do
			results[i] = v[var]
			nonnil = nonnil or (v[var] ~= nil)
		end
		if nonnil then
			return var, unpack(results, 1, #s)
		end
		return nil
	end, {...}, 0
end

-- compares two links to determine if they represent the same item
-- uses the itemId and suffixId from inside the link
-- if either link is nil, returns false
function utils.compareLinks(link1, link2)
	if link1 == nil or link2 == nil then return false end
	assert(type(link1) == "string")
	assert(type(link2) == "string")
	local parse = function (link)
		local prefix, itemlink, suffix = link:match("(.+|H)([^|]+)(|h.+)")
		if not prefix then return nil end
		local type, itemId, enchantId, jc1, jc2, jc3, jc4, suffixId, uniqueId, linkLevel, reforgeId = strsplit(":", itemlink)
		if type ~= "item" then return nil end
		return itemId .. ":" .. suffixId
	end
	link1, link2 = parse(link1), parse(link2)
	if not link1 or not link2 then return false end
	return link1 == link2
end

function utils.SendMessages(message, channel, target, messagesPerSecond)
	if messagesPerSecond == nil then messagesPerSecond = 3 end
	local messages = utils.BreakdownMessage(message)
	for delay,body in pairs(messages) do
	  C_Timer.After(delay / messagesPerSecond, function() SendChatMessage(body, channel, nil, target) end)
	end
  end
  
  function utils.BreakdownMessage(message)
	local whispers = {""}
	local current_index = 1;
	for word in message:gmatch("%S+") do 
	  if(string.len(whispers[current_index] .. word) >= 255) then
		current_index = current_index + 1
		whispers[current_index] = ""
	  end
		whispers[current_index] = whispers[current_index] .. " ".. word
	end
  
	return whispers
  end