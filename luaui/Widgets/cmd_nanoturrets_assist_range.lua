local widget = widget ---@type Widget

-- Testing:
-- repair/build => kept same behavior (all turret focus the target)
-- CTRL + repair/build => all in range focus the target
-- repair/build in area => kept same behavior: only in range nano are receiving the command
--		NOTE/TODO: the out of range nanos don't keep their old command (like if the player sent a stop command to them)
--		validate if we want to keep this stop or keep the previous command (done by this widget, because it doesn't send command to out of range nanos)
-- reclaim => kept same behavior (all turret focus the target)
-- reclaim in area on metal or energy on the map => it is already working as wanted so keep it
-- CTRL + reclaim => all in range focus the target
-- reclaim in area on building (with CTRL and/or ALT)
-- CTRL + reclaim in area
-- 		=> both doesn't work I belive it is because of the interaction with cmd_area_commands_filter.lua
--		TODO: investigate and fix
-- guard => kept same behavior (all turret focus the target)
-- CTRL + guard =>  all in range guard the target 
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
local spGetUnitBuildeeRadius = Spring.GetUnitBuildeeRadius

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

	-- when repair in area the engine handle as wanted
	if #params == 4 and id == CMD.REPAIR then return false end

	local targetsPosition = {} -- { x, z, r } x, z coordinates and radius 
	if #params == 1 then
		-- single target
		local x, _, z = spGetUnitPosition(params[1])
		local buildeeRadius = spGetUnitBuildeeRadius(params[1])
		targetsPosition[1] = { x = x or 0, z = z or 0, r = buildeeRadius }
	elseif #params == 4 then
		-- circle with potentially multiple targets inside
		for _, unitID in ipairs(units) do
			local x, _, z = spGetUnitPosition(unitID)
			local buildeeRadius = spGetUnitBuildeeRadius(unitID)
			targetsPosition[#targetsPosition + 1] = { x = x or 0, z = z or 0, r = buildeeRadius }
		end
	end

	local selectedUnits = spGetSelectedUnits()

	for i = 1, #selectedUnits do
		local unitID = selectedUnits[i]
		local unitDefID = spGetUnitDefID(unitID)

		if nanoDefs[unitDefID] ~= nil then
			-- coordinate of the nano
			local x, _, z = spGetUnitPosition(unitID)

			-- check if any of the target is in range
			local inRange = false
			for _, target in ipairs(targetsPosition) do
				local adjustedRange = nanoDefs[unitDefID] + target.r
				local dx = x - target.x
				local dz = z - target.z
				if dx * dx + dz * dz <= adjustedRange * adjustedRange then
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