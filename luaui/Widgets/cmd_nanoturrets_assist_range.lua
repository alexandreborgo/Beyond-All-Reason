local widget = widget ---@type Widget

-- How it works:
-- Click only:
-- 		repair/build 	=> kept same behavior (all turret focus the target)
-- 		reclaim 		=> kept same behavior (all turret focus the target)
-- 		guard 			=> kept same behavior (all turret focus the target)
--
-- CTRL + click:
-- 		repair/build 		=> widget send command to only in range nanos
-- 		reclaim	(m or e)	=> widget send command to only in range nanos
-- 		reclaim (building)	=> widget send command to only in range nanos
-- 		guard				=> widget send command to only in range nanos
--
-- Area:
-- 		area commands are not handled by this widget
-- 		repair/build 		=> kept same behavior (only in range nanos are receiving the command other are stopped) provided by engine
-- 		reclaim (m or e) 	=> kept same behavior (only in range nanos are receiving the command other are stopped) provided by engine
--							   if area reclaim while targetting a metal or wreck, the widget Smart area reclaim will make the out of range nanos keep their active command
-- 		reclaim building 	=> kept same behavior handled by Area Command Filters (and some other widgets)
-- 							   ctrl would be a conflict between this widget and Area Command Filters widget

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
local UnitDefs = UnitDefs
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitBuildeeRadius = Spring.GetUnitBuildeeRadius
local spGetFeaturePosition = Spring.GetFeaturePosition

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

	-- area commands are handled by the engine as expected, if we try to handle it in this widget we will need to resolve conflicts with Area command filters widget 
	if #params == 4 then return false end

	local targetsPosition = {} -- { x, z, r } x, z coordinates and radius
	if #params == 1 then
		-- single target
		local x, z, r
		if params[1] < Game.maxUnits then
			-- it's a unit
			x, _, z = spGetUnitPosition(params[1])
			r = spGetUnitBuildeeRadius(params[1]) or 0
		else
			-- it's a feature
			x, _, z = spGetFeaturePosition(params[1])
			r = 0
		end
		targetsPosition[1] = { x = x , z = z , r = r }
	end

	local selectedUnits = spGetSelectedUnits()

	for _, unitID in ipairs(selectedUnits) do
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
			else
			--	not in range so don't pass the command
			-- 	to have the same behavior as the engine (on area), we can send the stop command
			--	spGiveOrderToUnit(unitID, CMD.STOP, {}, {})
			end
		else
			-- the selected unit is not a nano so we pass the command
			spGiveOrderToUnit(unitID, id, params, options)
		end
	end
	-- if a new command is given to units it was done earlier
	-- other nanos that weren't included earlier are out of range so we don't need to pass the command
	return true
end