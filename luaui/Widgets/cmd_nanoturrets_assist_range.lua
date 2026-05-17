local widget = widget ---@type Widget

-- Testing:
-- repair/build => kept same behavior (all turret focus the target)
-- CTRL + repair/build => *almost* all in range focus the target
-- 		some of the farthest nanos don't change focus in single target but do when using an area
-- 		TODO: investigate and fix (wrong coordinates are taken from nanos/targets to do calculation or formula is wrong)
-- repair/build in area => kept same behavior: only in range nano are receiving the command
--		NOTE/TODO: the out of range nanos don't keep their old command (like if the player sent a stop command to them)
--		validate if we want to keep this stop or keep the previous command (done by this widget, because it doesn't send command to out of range nanos)
-- reclaim => kept same behavior (all turret focus the target)
-- reclaim in area on metal or energy on the map => it is already working as wanted so keep it
-- CTRL + reclaim => *almost* all in range focus the target (I guess there's the same issue regarding the farthest nanos)
--		TODO: investigate and fix
-- reclaim in area on building (with CTRL and/or ALT)
-- CTRL + reclaim in area
-- 		=> both doesn't work I belive it is because of the interaction with cmd_area_commands_filter.lua
--		TODO: investigate and fix
-- guard => kept same behavior (all turret focus the target)
-- CTRL + guard =>  *almost* all in range guard the target (still farthest nanos to check)
--		NOTE: if the target of the command is a con all turret in range of the con will guard it but they might not be able to reach the con's target
--		I believe we need to keep as is

function widget:GetInfo()
	return {
		name    = "Construction Turrets range assist",
		desc    = "When a command is given to a construction turret, it will check if it is in range to execute it. If not the command will not be given to the turret",
		author  = "mreasyfrag",
		date    = "17/05/2026",
		license = "GNU GPL v2",
		layer   = 0,
		enabled = true,
	}
end

local spGetSelectedUnits = Spring.GetSelectedUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local GetUnitDefID = Spring.GetUnitDefID
local UnitDefs = UnitDefs
local spGetUnitPosition = Spring.GetUnitPosition

-- taken from cmd_nanoturrets_assist_priority.lua 
local nanoDefs = {}
for unitDefID, unitDef in pairs(UnitDefs) do
	if unitDef.isBuilder and not unitDef.canMove and not unitDef.isFactory then
		nanoDefs[unitDefID] = unitDef.buildDistance
	end
end

function widget:CommandNotify(id, params, options)
	-- ctrl = smart command so we apply this only if crtl is pressed
	-- and we keep the current behavior if not (should have no impact on how players play)
	if not options.ctrl then return false end

	-- when repair in area the engien handle as wanted
	if #params == 4 and id == CMD.REPAIR then return false end

	local targetsPosition = {} -- { x, z } 
	if #params == 1 then
		-- single target
		local _, _, _, x, _, z = spGetUnitPosition(params[1], true)
		targetsPosition[1] = { x = x or 0, z = z or 0 }
	elseif #params == 4 then
		-- circle with potentially multiple targets inside
		for _, unitID in ipairs(units) do
			local _, _, _, x, _, z = spGetUnitPosition(unitID, true)
			targetsPosition[#targetsPosition + 1] = { x = x or 0, z = z or 0 }
		end
	end

	local selectedUnits = spGetSelectedUnits()

	for i = 1, #selectedUnits do
		local unitID = selectedUnits[i]
		local unitDefID = spGetUnitDefID(unitID)

		if nanoDefs[unitDefID] ~= nil then
			-- coordinate of the nano
			local _, _, _, x, _, z = spGetUnitPosition(unitID, true)

			-- check if any of the target is in range
			local inRange = false
			for _, target in ipairs(targetsPosition) do
				if (x - target.x) * (x - target.x) + (z - target.z) * (z - target.z) <= nanoDefs[unitDefID] * nanoDefs[unitDefID] then
					inRange = true
					break
				end
			end

			if inRange then
				spGiveOrderToUnit(unitID, id, params, options)
			--else
			--	not in range so don't change the current command	
			end
		else
			-- the selected unit is not a nano so we pass the command
			spGiveOrderToUnit(unitID, id, params, options)
		end
	end
	-- if a new command is given to units it was done earlier
	-- other nanos that weren't included earlier are out of range so we stop the command 
	return true
end