local widget = widget ---@type Widget

-- How it works:
-- repair or reclaim or guard 
-- widget send the command only to in range nanos
--
-- CTRL + repair or reclaim or guard
-- current behavior (all turret focus the target)

function widget:GetInfo()
	return {
		name    = "Construction Turrets range assist",
		desc    = "When a command is given to nanos, this widget will check if each nanos is in range to execute it. If not the command will not be given to the out of range nanos. Use CTRL to skip this widget.",
		author  = "mreasyfrag",
		date    = "30/05/2026",
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
local maxUnits = Game.maxUnits

-- taken from cmd_nanoturrets_assist_priority.lua 
local nanoDefs = {}
for unitDefID, unitDef in pairs(UnitDefs) do
	if unitDef.isBuilder and not unitDef.canMove and not unitDef.isFactory then
		nanoDefs[unitDefID] = unitDef.buildDistance
	end
end

function widget:CommandNotify(id, params, options)
	-- if CTRL is pressed skip this widget (aka all selected nanos will get the command)
	if options.ctrl then return false end
	if #params ~= 1 then return false end

	-- we only handle REPAIR, RECLAIM and GUARD commands
	if id ~= CMD.REPAIR and id ~= CMD.RECLAIM and id ~= CMD.GUARD then return false end

	local selectedUnits = spGetSelectedUnits()

	-- we only handle the command if at least one nano is selected
	local hasNano = false
	for _, unitID in ipairs(selectedUnits) do
		if nanoDefs[spGetUnitDefID(unitID)] then
			hasNano = true
			break
		end
	end
	if not hasNano then return false end

	local tx, tz, tr

	if params[1] < maxUnits then
		-- it's a unit
		tx, _, tz = spGetUnitPosition(params[1])
		tr = spGetUnitBuildeeRadius(params[1]) or 0
	else
		-- it's a feature
		tx, _, tz = spGetFeaturePosition(params[1] - maxUnits)
		tr = 0
	end

	-- tx is nil if target died before the command was processed
	if not tx then return false end

	for _, unitID in ipairs(selectedUnits) do
		local unitDefID = spGetUnitDefID(unitID)

		if nanoDefs[unitDefID] ~= nil then
			local nx, _, nz = spGetUnitPosition(unitID)
			-- nx is nil if nano died before the command was processed
			if nx then
				local adjustedRange = nanoDefs[unitDefID] + tr
				local dx = nx - tx
				local dz = nz - tz
				if dx * dx + dz * dz <= adjustedRange * adjustedRange then
					-- in range
					spGiveOrderToUnit(unitID, id, params, options)
				end
			end
		else
			-- the selected unit is not a nano so we pass the command
			spGiveOrderToUnit(unitID, id, params, options)
		end
	end

	return true
end