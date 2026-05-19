local widget = widget ---@type Widget

-- Testing:
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
-- 		repair/build 		=> kept same behavior (only in range nanos are receiving the command other are stopped) provided by engine
-- 		reclaim (m or e) 	=> kept same behavior (only in range nanos are receiving the command other are stopped) provided by engine
--							   if area reclaim while targetting a metal or wreck, the widget Smart area reclaim will make the out of range nanos keep their active command
-- 		reclaim building 	=> reclaiming building doesn't seem to work without Area Command Filters
-- 							   it works by transforming the area order into a queue with all units in the area
--  						   alt: reclaims all the targeted unit type
-- 							   ctrl: reclaims all insine the area
--  						   ctrl is a conflict between this widget and Area Command Filters widget

function widget:GetInfo()
	return {
		name    = "Construction Turrets range assist",
		desc    = "When a command is given to a construction turret, it will check if it is in range to execute it. If not the command will not be given to the turret",
		author  = "mreasyfrag",
		date    = "17/05/2026",
		license = "GNU GPL v2",
		layer   = -1,
		-- -1 to exec before unit_smart_area_reclaim or area reclaim command from metal or energy isn't received
		enabled = true,
	}
end

local spGetSelectedUnits = Spring.GetSelectedUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local UnitDefs = UnitDefs
local spGetUnitInCylinder = Spring.GetUnitsInCylinder
local spGetFeatureInCylinder = Spring.GetFeaturesInCylinder
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitBuildeeRadius = Spring.GetUnitBuildeeRadius
local spGetFeaturePosition = Spring.GetFeaturePosition
local spGetUnitHealth = Spring.GetUnitHealth

-- taken from cmd_nanoturrets_assist_priority.lua 
local nanoDefs = {}
for unitDefID, unitDef in pairs(UnitDefs) do
	if unitDef.isBuilder and not unitDef.canMove and not unitDef.isFactory then
		nanoDefs[unitDefID] = unitDef.buildDistance
	end
end

local function GetUnitPositionAndRadius(unitid)
	local x, z, r
	x, _, z = spGetUnitPosition(unitid)
	r = spGetUnitBuildeeRadius(unitid) or 0
	return x, z, r
end

local function GetFeaturePositionAndRadius(featureid)
	local x, z
	x, _, z = spGetFeaturePosition(featureid)
	return x, z, 0
end

-- based on GetUnitOrFeaturePosition from cmd_commandinsert.lua
local function GetUnitOrFeaturePositionAndBuildeeRadius(id)
	if id < Game.maxUnits then
		-- it's a unit
		return GetUnitPositionAndRadius(id)
	end
	-- it's a feature
	return GetFeaturePositionAndRadius(id - Game.maxUnits)
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
		local x, z, r = GetUnitOrFeaturePositionAndBuildeeRadius(params[1])
		targetsPosition[1] = { x = x , z = z , r = r }
	elseif #params == 4 then
		-- circle with potentially multiple targets inside
		local x, _, z, r = params[1], params[2], params[3], params[4]

		if id == CMD.REPAIR or id == CMD.RECLAIM then
			local units = spGetUnitInCylinder(x, z, r)
			for _, unitID in ipairs(units) do
				local health, maxHealth, _, _, buildProgress = spGetUnitHealth(unitID)
				if health < maxHealth or buildProgress < 1 then
					local x, z, r = GetUnitPositionAndRadius(unitID)
					targetsPosition[#targetsPosition + 1] = { x = x, z = z, r = r }
				end
			end
		elseif id == CMD.RECLAIM then
			local features = spGetFeatureInCylinder(x, z, r)
			for _, featureID in ipairs(features) do
				local x, z, r = GetFeaturePositionAndRadius(featureID)
				targetsPosition[#targetsPosition + 1] = { x = x, z = z, r = r }
			end
		end
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