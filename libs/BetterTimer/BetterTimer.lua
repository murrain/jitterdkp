local lib = LibStub:NewLibrary("BetterTimer-1.0", 1)
if not lib then return end

local AceTimer = LibStub("AceTimer-3.0")

-- cancelAllCounter is used when rescheduling a paused repeating timer
-- it lets us trivially determine if CancelAllTimers() was called when
-- we call our initial re-scheduled timer so we can avoid scheulding
-- a repeating timer
local cancelAllCounter = 0

local function scheduleTimer(self, delay, callback, repeating, arg)
	if type(callback) == "string" then
		method = self[callback]
		callback = function(...)
			method(self, ...)
		end
	end
	local timer = {
		start = GetTime(),
		runtime = 0,
		repeating = repeating,
		delay = delay,
		arg = arg,
		object = self,
	}
	timer.handler = function(arg)
		local now = GetTime()
		callback(timer, now - timer.start + timer.runtime, arg)
		timer.start = now
		timer.runtime = 0
	end
	if repeating then
		timer.acetimer = AceTimer.ScheduleRepeatingTimer(self, timer.handler, delay, arg)
	else
		timer.acetimer = AceTimer.ScheduleTimer(self, timer.handler, delay, arg)
	end
	return timer
end

function lib:CancelTimer(timer, silent)
	timer.cancelled = true
	return AceTimer.CancelTimer(self, timer.acetimer, silent)
end

function lib:CancelAllTimers()
	cancelAllCounter = cancelAllCounter + 1
	AceTimer.CancelAllTimers(self)
end

function lib:ScheduleTimer(callback, delay, arg)
	return scheduleTimer(self, delay, callback, false, arg)
end

function lib:ScheduleRepeatingTimer(callback, delay, arg)
	return scheduleTimer(self, delay, callback, true, arg)
end

function lib:TimeLeft(timer)
	return AceTimer.TimeLeft(self, timer.acetimer)
end

function lib:PauseTimer(timer)
	if not timer.acetimer or timer.cancelled then return false end
	timer.runtime = timer.runtime + (GetTime() - timer.start)
	local result = AceTimer.CancelTimer(self, timer.acetimer)
	timer.acetimer = nil
	return result
end

function lib:ResumeTimer(timer)
	if timer.acetimer or timer.cancelled then return false end
	timer.start = GetTime()
	local handler
	if timer.repeating then
		-- need to schedule a one-shot to make up for the remaining time
		-- and re-schedule a repeating at that point
		handler = function(arg)
			local cancelCount = cancelAllCounter
			timer.handler(arg)
			if timer.acetimer and not timer.cancelled and cancelCount == cancelAllCounter then -- ensure we're still valid
				timer.acetimer = AceTimer.ScheduleRepeatingTimer(self, timer.handler, timer.delay, arg)
			end
		end
	else
		handler = timer.handler
	end
	timer.acetimer = AceTimer.ScheduleTimer(self, handler, timer.delay - timer.runtime, timer.arg)
	return not not timer.acetimer
end

lib.mixinTargets = lib.mixinTargets or {}
local mixins = {
	"CancelAllTimers", "CancelTimer",
	"PauseTimer", "ResumeTimer",
	"ScheduleRepeatingTimer", "ScheduleTimer",
	"TimeLeft"
}

function lib:Embed(target)
	for _,name in pairs(mixins) do
		target[name] = lib[name]
	end
	lib.mixinTargets[target] = true
end

-- re-mixin
for target,_ in pairs(lib.mixinTargets) do
	lib:Embed(target)
end
