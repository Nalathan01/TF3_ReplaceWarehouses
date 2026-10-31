local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl"
local warehouse_eow = ug_require "::/gui/entity_window/warehouse/warehouse_eow.script.tl"

local TYPES = { "universal", "goods", "bulk", "liquid", "flatbed" }

local function getConstructionEntity(warehouseEntity)
	local warehouse = api.engine.getComponent(warehouseEntity, api.type.ComponentType.WAREHOUSE)
	if warehouse == nil then
		return nil
	end
	local ok, entity = pcall(function()
		return api.engine.system.streetConnectorSystem.getConstructionEntityForSubconstruction(warehouse.stockList)
	end)
	if ok and entity ~= nil and entity >= 0 then
		return entity
	end
	return warehouse.construction
end

local function getModuleName(entry)
	if type(entry) == "string" then
		return entry
	end
	if type(entry) == "table" then
		for __, value in pairs(entry) do
			if type(value) == "string" and string.match(value, "%.module$") then
				return value
			end
		end
	end
	return nil
end

local function getModuleType(entry)
	local name = getModuleName(entry)
	if name == nil then
		return nil
	end
	return string.match(name, "wh_(%a+)%.module$")
end

local function findModule(moduleType)
	for id, name in pairs(api.res.moduleRep.getAll()) do
		if string.match(name, "wh_" .. moduleType .. "%.module$") then
			return name, id
		end
	end
	return nil, nil
end

local function describeEntry(entry)
	if type(entry) ~= "table" then
		return tostring(entry)
	end
	local parts = {}
	for key, value in pairs(entry) do
		local text = type(value)
		if type(value) == "string" or type(value) == "number" then
			text = tostring(value)
		end
		parts[#parts + 1] = tostring(key) .. "=" .. text
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

local function makeEntry(old, newName, newId)
	if type(old) ~= "table" then
		return newName
	end
	local entry = {}
	for key, value in pairs(old) do
		if type(value) == "string" and string.match(value, "%.module$") then
			entry[key] = newName
		else
			entry[key] = value
		end
	end
	if entry.metadata ~= nil then
		local desc = api.res.moduleRep.get(newId)
		if desc ~= nil and desc.metadata ~= nil then
			entry.metadata = desc.metadata
		end
	end
	return entry
end

local function getCurrentYear()
	local gameTime = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)
	return api.engine.util.getCalendarDate(gameTime.gameTime).year
end

local function getPrice(moduleType)
	local ok, price = pcall(function()
		local year = getCurrentYear()
		local best = nil
		for id, name in pairs(api.res.constructionRep.getAll()) do
			if string.match(name, "warehouse_era_%a_" .. moduleType) then
				local desc = api.res.constructionRep.get(id)
				local yearFrom = desc.availability.yearFrom or 0
				local yearTo = desc.availability.yearTo or 0
				if (yearFrom == 0 or yearFrom <= year) and (yearTo == 0 or year < yearTo) then
					best = desc.description.attributes.cost[1]
				end
			end
		end
		return best
	end)
	if ok and price ~= nil and price > 0 then
		return math.floor(price)
	end
	local __, moduleId = findModule(moduleType)
	if moduleId ~= nil then
		local desc = api.res.moduleRep.get(moduleId)
		if desc ~= nil and desc.metadata ~= nil and desc.metadata.price ~= nil then
			return desc.metadata.price
		end
	end
	return 0
end

local function getBalance()
	local ok, balance = pcall(function()
		return api.engine.util.finance.getPlayersBalance(api.engine.util.getPlayer())
	end)
	if ok then
		return balance
	end
	return nil
end

local function bookCost(price)
	if price <= 0 then
		return
	end
	local entry = api.type.JournalEntry.new()
	entry.amount = -price
	entry.time = -1
	entry.category.type = api.type.JournalEntry.Type.CONSTRUCTION
	entry.category.construction = api.type.JournalEntry.Construction.WAREHOUSE
	api.cmd.sendCommand(api.cmd.makeJournalBookAssetCmd(api.engine.util.getPlayer(), entry, api.type.Vec3f.new(0, 0, 0)))
end

local function rebuild(constructionEntity, slotId, newType)
	local construction = api.engine.getComponent(constructionEntity, api.type.ComponentType.CONSTRUCTION)
	if construction == nil or construction.params.modules == nil then
		return false
	end
	local newName, newId = findModule(newType)
	if newName == nil then
		log.warning("LagerErsetzen: module not found for type " .. newType)
		return false
	end
	local params = construction.params
	local old = params.modules[slotId]
	params.modules[slotId] = makeEntry(old, newName, newId)
	if params.tagToCargoType ~= nil then
		params.tagToCargoType[slotId] = nil
	end
	local proposal = api.engine.util.proposal.createProposalReplaceConstruction(constructionEntity, params)
	if proposal == nil then
		log.warning("LagerErsetzen: replace proposal failed, module entry " .. describeEntry(old))
		return false
	end
	api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(proposal, nil, false, true), function(__result, success)
		if not success then
			log.warning("LagerErsetzen: rebuild rejected, module entry " .. describeEntry(old))
		end
	end)
	bookCost(getPrice(newType))
	return true
end

local function readModules(warehouseEntity)
	local constructionEntity = getConstructionEntity(warehouseEntity)
	local result = { construction = constructionEntity, modules = {} }
	if constructionEntity == nil then
		return result
	end
	local construction = api.engine.getComponent(constructionEntity, api.type.ComponentType.CONSTRUCTION)
	if construction == nil or construction.params.modules == nil then
		return result
	end
	for slotId, entry in pairs(construction.params.modules) do
		local moduleType = getModuleType(entry)
		if moduleType ~= nil then
			result.modules[#result.modules + 1] = { slotId = slotId, moduleType = moduleType }
		end
	end
	table.sort(result.modules, function(a, b) return a.slotId < b.slotId end)
	return result
end

local function makeText(text, class)
	return builtin.TextView{
		meta = { class = class or "font-scale-body" },
		text = text,
	}
end

local ModuleRow = react.RegisterRecipe("NalathanLagerErsetzenModuleRow", function(params)
	local selected = react.useState(params.moduleType)
	local failed = react.useState(false)

	local items = {}
	for __, moduleType in ipairs(TYPES) do
		items[#items + 1] = builtin.ComboBoxItem{
			value = moduleType,
			content = makeText(_("LAGERERSETZEN_TYPE_" .. string.upper(moduleType))),
		}
	end

	local changed = selected:old() ~= params.moduleType
	local price = changed and getPrice(selected:old()) or 0
	local balance = getBalance()
	local affordable = balance == nil or price <= balance
	local buttonText = _("LAGERERSETZEN_REBUILD")
	if changed and price > 0 then
		buttonText = string.format(_("LAGERERSETZEN_REBUILD_PRICE"), api.util.formatMoney(price))
	end

	local children = {
		makeText(string.format(_("LAGERERSETZEN_MODULE"), params.index, _("LAGERERSETZEN_TYPE_" .. string.upper(params.moduleType)))),
		builtin.ComboBox{
			value = selected:old(),
			items = items,
			onValueChange = function(value)
				selected:set(value)
				failed:set(false)
			end,
		},
		builtin.Button{
			meta = { class = "primary", enabled = changed and affordable, tooltip = affordable and "" or _("LAGERERSETZEN_NO_MONEY") },
			content = makeText(buttonText),
			onClick = function()
				if changed and affordable then
					failed:set(not rebuild(params.construction, params.slotId, selected:old()))
				end
			end,
		},
	}
	if failed:old() then
		children[#children + 1] = makeText(_("LAGERERSETZEN_REBUILD_FAILED"))
	end

	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = children,
	}
end)

local LagerErsetzenCard = react.RegisterPluginRecipe(warehouse_eow.WarehouseEowExtensionPoint, "NalathanLagerErsetzenCard", function(params)
	local status = engine_react_util.useStepStateTimer(function()
		return readModules(params.entityId)
	end, 0.5)
	local current = status:old()

	if current.construction == nil or #current.modules == 0 then
		return builtin.BoxLayout{ children = {} }
	end

	local children = {
		makeText(_("LAGERERSETZEN_CARD_TITLE"), "font-scale-headline"),
		makeText(_("LAGERERSETZEN_CARD_HINT")),
	}
	for index, module in ipairs(current.modules) do
		children[#children + 1] = ModuleRow({
			index = index,
			slotId = module.slotId,
			moduleType = module.moduleType,
			construction = current.construction,
		})
	end

	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = children,
	}
end)

function data()
	return {
		LagerErsetzenCard = LagerErsetzenCard,
	}
end
