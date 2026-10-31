local EVENT_ID = "LagerErsetzen"

local snapshot = nil

local function getConstructionEntity(warehouse)
	local ok, entity = pcall(function()
		return api.engine.system.streetConnectorSystem.getConstructionEntityForSubconstruction(warehouse.stockList)
	end)
	if ok and entity ~= nil and entity >= 0 then
		return entity
	end
	return warehouse.construction
end

local function getWarehouses(constructionSet)
	local result = {}
	api.engine.forEachEntityWithComponent(function(entity)
		local warehouse = api.engine.getComponent(entity, api.type.ComponentType.WAREHOUSE)
		if warehouse ~= nil then
			local constructionEntity = getConstructionEntity(warehouse)
			if constructionSet[constructionEntity] or constructionSet[warehouse.construction] then
				result[#result + 1] = { stockList = warehouse.stockList, construction = constructionEntity }
			end
		end
	end, api.type.ComponentType.WAREHOUSE)
	return result
end

local function toSet(entities)
	local set = {}
	for i = 1, #(entities or {}) do
		set[entities[i]] = true
	end
	return set
end

local function getStocks(stockListEntity)
	local stockList = api.engine.getComponent(stockListEntity, api.type.ComponentType.STOCK_LIST)
	if stockList == nil then
		return {}
	end
	return stockList.stocks
end

local function getCargoTypeIds()
	local passengers = api.res.cargoTypeRep.getPassengerCargoTypeId()
	local ids = {}
	for cargoTypeId, _ in pairs(api.res.cargoTypeRep.getAll()) do
		if cargoTypeId ~= passengers then
			ids[#ids + 1] = cargoTypeId
		end
	end
	return ids
end

local function getStockCount(stockListEntity, stockId)
	return api.engine.system.simEntityAtStockSystem.getStockCount(stockListEntity, stockId)
end

local function countCargo(warehouses)
	local totals = {}
	local cargoTypeIds = getCargoTypeIds()
	for __, warehouse in ipairs(warehouses) do
		local stocks = getStocks(warehouse.stockList)
		for i = 1, #stocks do
			for __, cargoTypeId in ipairs(cargoTypeIds) do
				local count = api.engine.system.simEntityAtStockSystem.getStockCountForCargoType(warehouse.stockList, i-1, cargoTypeId)
				if count > 0 then
					totals[cargoTypeId] = (totals[cargoTypeId] or 0) + count
				end
			end
		end
	end
	return totals
end

local function isPinnedTo(stock, cargoTypeId)
	return not stock.mixedTypes and stock.cargoType ~= nil and stock.cargoType == cargoTypeId
end

local function isFreeForPin(stock, stockListEntity, stockId, cargoTypeId)
	return not stock.mixedTypes
		and stock.tag ~= nil and stock.tag >= 0
		and (stock.cargoType == nil or stock.cargoType < 0)
		and api.res.cargoTypeRep.hasCargoType(stock.cargoTypes, cargoTypeId)
		and getStockCount(stockListEntity, stockId) == 0
end

local function queueAction(s, action)
	s.actions = s.actions or {}
	s.nextActionId = (s.nextActionId or 0) + 1
	action.id = s.nextActionId
	s.actions[#s.actions + 1] = action
end

local function placeCargo(s, warehouses, used, cargoTypeId, amount)
	local cargoName = api.res.cargoTypeRep.getName(cargoTypeId)
	for __, warehouse in ipairs(warehouses) do
		local stocks = getStocks(warehouse.stockList)
		for i = 1, #stocks do
			if amount <= 0 then
				return 0
			end
			local stock = stocks[i]
			local stockId = i-1
			if isPinnedTo(stock, cargoTypeId) then
				local key = warehouse.stockList .. ":" .. stockId
				if used[key] == nil then
					used[key] = getStockCount(warehouse.stockList, stockId)
				end
				local free = stock.capacity-used[key]
				if free > 0 then
					local add = math.min(free, amount)
					queueAction(s, { kind = "fill", stockList = warehouse.stockList, stockId = stockId, amount = add, cargo = cargoName })
					used[key] = used[key] + add
					amount = amount-add
				end
			end
		end
	end
	return amount
end

local function planPins(warehouses, items)
	local plans = {}
	local planned = {}
	local uncovered = 0
	local sorted = {}
	for __, item in ipairs(items) do
		sorted[#sorted + 1] = item
	end
	table.sort(sorted, function(a, b) return a.amount > b.amount end)

	for __, item in ipairs(sorted) do
		local cargoTypeId = api.res.cargoTypeRep.find(item.cargo)
		local left = item.amount
		if cargoTypeId ~= nil and cargoTypeId >= 0 then
			for __, warehouse in ipairs(warehouses) do
				local stocks = getStocks(warehouse.stockList)
				for i = 1, #stocks do
					local key = warehouse.stockList .. ":" .. (i-1)
					if left > 0 and not planned[key] and isFreeForPin(stocks[i], warehouse.stockList, i-1, cargoTypeId) then
						planned[key] = true
						plans[warehouse.construction] = plans[warehouse.construction] or {}
						table.insert(plans[warehouse.construction], { tag = stocks[i].tag, cargo = item.cargo })
						left = left-stocks[i].capacity
					end
				end
			end
		end
		if left > 0 then
			uncovered = uncovered + left
		end
	end
	return plans, uncovered
end

local function queuePins(s, plans)
	for constructionEntity, tags in pairs(plans) do
		queueAction(s, { kind = "pin", construction = constructionEntity, tags = tags })
	end
end

local function getSpeed()
	local gameSpeed = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED)
	if gameSpeed == nil then
		return 0
	end
	return gameSpeed.speedup
end

local function pauseGame(s)
	local speed = getSpeed()
	if speed > 0 then
		s.resumeSpeed = speed
		queueAction(s, { kind = "speed", value = 0 })
	end
end

local function resumeGame(s)
	if s.resumeSpeed ~= nil and getSpeed() == 0 then
		queueAction(s, { kind = "speed", value = s.resumeSpeed })
	end
	s.resumeSpeed = nil
end

local function addPending(s, cargoTypeId, amount)
	local cargoName = api.res.cargoTypeRep.getName(cargoTypeId)
	for __, item in ipairs(s.items) do
		if item.cargo == cargoName then
			item.amount = item.amount + amount
			return
		end
	end
	s.items[#s.items + 1] = { cargo = cargoName, amount = amount }
end

local function storePending(s, warehouses)
	local used = {}
	local remaining = {}
	for __, item in ipairs(s.items) do
		local cargoTypeId = api.res.cargoTypeRep.find(item.cargo)
		local left = item.amount
		if cargoTypeId ~= nil and cargoTypeId >= 0 then
			left = placeCargo(s, warehouses, used, cargoTypeId, item.amount)
		end
		if left > 0 then
			remaining[#remaining + 1] = { cargo = item.cargo, amount = left }
		end
	end
	s.items = remaining
end

local function askUser(s)
	s.incident = (s.incident or 0) + 1
	s.mode = "ask"
	if s.resumeSpeed == nil then
		pauseGame(s)
	end
end

local function onPostBuild(state, resultEntities)
	local warehouses = getWarehouses(toSet(resultEntities))
	local s = state:get() or {}
	s.items = s.items or {}
	local lostAny = false

	if snapshot ~= nil then
		local after = countCargo(warehouses)
		for cargoTypeId, before in pairs(snapshot) do
			local lost = before-(after[cargoTypeId] or 0)
			if lost > 0 then
				addPending(s, cargoTypeId, lost)
				lostAny = true
			end
		end
		snapshot = nil
	end

	if #s.items == 0 then
		return
	end

	if #warehouses == 0 then
		if lostAny then
			askUser(s)
			state:set(s)
		end
		return
	end

	storePending(s, warehouses)

	local uncovered = 0
	if #s.items > 0 then
		local plans, left = planPins(warehouses, s.items)
		uncovered = left
		queuePins(s, plans)
	end

	if #s.items == 0 then
		s.mode = nil
		resumeGame(s)
	elseif lostAny and uncovered > 0 then
		askUser(s)
	end

	state:set(s)
end

local function runPin(action)
	local construction = api.engine.getComponent(action.construction, api.type.ComponentType.CONSTRUCTION)
	if construction == nil then
		log.warning("LagerErsetzen: construction to pin no longer exists " .. tostring(action.construction))
		return
	end
	local params = construction.params
	params.tagToCargoType = params.tagToCargoType or {}
	for __, pin in ipairs(action.tags or {}) do
		params.tagToCargoType[pin.tag] = pin.cargo
	end
	local proposal = api.engine.util.proposal.createProposalReplaceConstruction(action.construction, params)
	if proposal == nil then
		log.warning("LagerErsetzen: could not pin stocks of construction " .. tostring(action.construction))
		return
	end
	api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(proposal, nil, false, true))
end

local function runAction(action)
	if action.kind == "fill" then
		api.cmd.sendCommand(api.cmd.debug.makeStockSetCargoAmountCmd(action.stockList, action.stockId, action.amount, action.cargo))
	elseif action.kind == "speed" then
		api.cmd.sendCommand(api.cmd.makeGameSetSpeedCmd(action.value))
	elseif action.kind == "pin" then
		runPin(action)
	end
end

local function update(_userParams, state, _dt)
	state:subscribeToEvent("onPreBuildProposal")
	state:subscribeToEvent("onPostBuildProposal")
	state:subscribeToEvent("LagerErsetzenDiscard")
	state:subscribeToEvent("LagerErsetzenWait")

	local s = state:get()
	if s ~= nil and s.actions ~= nil and #s.actions > 0 then
		local actions = s.actions
		s.actions = {}
		state:set(s)
		for __, action in ipairs(actions) do
			runAction(action)
		end
	end
end

local function handleEvent(_userParams, state, _src, id, name, param)
	if id == "apply_command" then
		if name == "onPreBuildProposal" then
			snapshot = nil
			local warehouses = getWarehouses(toSet(param[1].toRemove))
			if #warehouses > 0 then
				snapshot = countCargo(warehouses)
			end
		elseif name == "onPostBuildProposal" then
			onPostBuild(state, param[3])
		end
		return
	end

	if id ~= EVENT_ID then
		return
	end

	local s = state:get() or {}
	if name == "LagerErsetzenDiscard" then
		s.items = {}
		s.mode = nil
		resumeGame(s)
		state:set(s)
	elseif name == "LagerErsetzenWait" then
		if s.items ~= nil and #s.items > 0 then
			s.mode = "waiting"
			state:set(s)
		end
	end
end

function data()
	return {
		update = update,
		handleEvent = handleEvent,
	}
end
