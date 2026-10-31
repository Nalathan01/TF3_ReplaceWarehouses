local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl"
local game_react_globals = ug_require "::/gui/main/game_react_globals.tl"
local game_bar_widgets = ug_require "::/gui/game_bar/game_bar_widgets.tl"

local SCRIPT_NAMES = { "nalathan_lager_ersetzen::/lager_ersetzen/lager_ersetzen.gs", "::/lager_ersetzen/lager_ersetzen.gs" }

local function sendEvent(name, param)
	api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "LagerErsetzen", name, param or {}))
end

local function readScriptState()
	for __, scriptName in ipairs(SCRIPT_NAMES) do
		local ok, result = pcall(function()
			local entity = api.engine.system.gameScriptSystem.getEntityForGameScript(scriptName)
			local gameScript = api.engine.getComponent(entity, api.type.ComponentType.GAME_SCRIPT)
			return gameScript.state
		end)
		if ok and type(result) == "table" then
			return result
		end
	end
	return {}
end

local function getCargoDisplayName(cargoName)
	local ok, name = pcall(function()
		local cargoTypeId = api.res.cargoTypeRep.find(cargoName)
		return api.res.cargoTypeRep.get(cargoTypeId).name
	end)
	if ok and name ~= nil then
		return name
	end
	return cargoName
end

local CLASS_ORDER = { "GOODS", "BULK", "LIQUID", "FLATBED" }
local MODULE_CAPACITY = 500

local function getCargoClass(cargoName)
	local ok, class = pcall(function()
		local cargoType = api.res.cargoTypeRep.get(api.res.cargoTypeRep.find(cargoName))
		for __, cargoClass in ipairs(cargoType.cargoClasses or {}) do
			if cargoClass ~= "UNIVERSAL" then
				return cargoClass
			end
		end
		return nil
	end)
	if ok then
		return class
	end
	return nil
end

local function makeNeeds(items)
	local byClass = {}
	for __, item in ipairs(items) do
		if item.class ~= nil then
			local need = byClass[item.class] or { modules = 0, cargos = {} }
			need.modules = need.modules + math.ceil(item.amount / MODULE_CAPACITY)
			need.cargos[#need.cargos + 1] = item.name .. " " .. item.amount
			byClass[item.class] = need
		end
	end
	local needs = {}
	for __, class in ipairs(CLASS_ORDER) do
		if byClass[class] ~= nil then
			needs[#needs + 1] = { class = class, modules = byClass[class].modules, cargos = table.concat(byClass[class].cargos, ", ") }
		end
	end
	return needs
end

local function makeStatus()
	local s = readScriptState()
	local items = {}
	local total = 0
	for __, item in ipairs(s.items or {}) do
		items[#items + 1] = { name = getCargoDisplayName(item.cargo), amount = item.amount, class = getCargoClass(item.cargo) }
		total = total + item.amount
	end
	return {
		items = items,
		needs = makeNeeds(items),
		total = total,
		mode = s.mode,
		incident = s.incident or 0,
	}
end

local function openWarehouseMenu()
	api.gui.fireReactEvent("openWarehouses", {})
end

local function makeText(text, class)
	return builtin.TextView{
		meta = { class = class or "font-scale-body" },
		text = text,
	}
end

local LagerErsetzenWindow
local LagerErsetzenInfoWindow

local function openInfoWindow()
	local windowApi = game_react_globals.getDefaultWindowApi()
	if windowApi then
		windowApi.removeAllWindows(LagerErsetzenInfoWindow)
		windowApi.addSingletonWindow(LagerErsetzenInfoWindow, {})
	end
end

local function closeInfoWindow()
	local windowApi = game_react_globals.getDefaultWindowApi()
	if windowApi then
		windowApi.removeAllWindows(LagerErsetzenInfoWindow)
	end
end

local function makeNeedRows(needs)
	local rows = {}
	for __, need in ipairs(needs) do
		rows[#rows + 1] = makeText(string.format(_("LAGERERSETZEN_NEED_ROW"), need.modules, _("LAGERERSETZEN_TYPE_" .. need.class), need.cargos))
	end
	return rows
end

local LagerErsetzenPanel = react.RegisterRecipe("NalathanLagerErsetzenPanel", function()
	local status = engine_react_util.useStepStateTimer(makeStatus, 0.5)
	local current = status:old()

	local children = {}
	if #current.items == 0 then
		children[#children + 1] = makeText(_("LAGERERSETZEN_DONE"))
	else
		children[#children + 1] = makeText(_("LAGERERSETZEN_INTRO"))
		for __, item in ipairs(current.items) do
			children[#children + 1] = makeText(item.amount .. "  " .. item.name, "font-scale-body, cargo-row")
		end
		children[#children + 1] = makeText(_("LAGERERSETZEN_NEEDS"), "font-scale-headline")
		for __, row in ipairs(makeNeedRows(current.needs)) do
			children[#children + 1] = row
		end
		children[#children + 1] = makeText(_("LAGERERSETZEN_HINT"))
		children[#children + 1] = builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				builtin.Button{
					meta = { class = "secondary" },
					content = makeText(_("LAGERERSETZEN_DISCARD")),
					onClick = function()
						sendEvent("LagerErsetzenDiscard")
					end,
				},
				builtin.Button{
					meta = { class = "primary" },
					content = makeText(_("LAGERERSETZEN_WAIT")),
					onClick = function()
						sendEvent("LagerErsetzenWait")
						local windowApi = game_react_globals.getDefaultWindowApi()
						if windowApi then
							windowApi.removeAllWindows(LagerErsetzenWindow)
						end
						openInfoWindow()
						openWarehouseMenu()
					end,
				},
			},
		}
	end

	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = children,
	}
end)

LagerErsetzenWindow = react.RegisterWrapperRecipe("NalathanLagerErsetzenWindow", builtin.Window, function(_params)
	return builtin.Window{
		title = _("LAGERERSETZEN_TITLE"),
		closable = true,
		id = "nalathanLagerErsetzenWindow",
		onClose = function()
			sendEvent("LagerErsetzenWait")
			local windowApi = game_react_globals.getDefaultWindowApi()
			if windowApi then
				windowApi.removeAllWindows(LagerErsetzenWindow)
			end
		end,
		content = LagerErsetzenPanel({}),
	}
end)

local LagerErsetzenInfoPanel = react.RegisterRecipe("NalathanLagerErsetzenInfoPanel", function()
	local status = engine_react_util.useStepStateTimer(makeStatus, 0.5)
	local current = status:old()
	local children = { makeText(_("LAGERERSETZEN_INFO_INTRO")) }
	for __, row in ipairs(makeNeedRows(current.needs)) do
		children[#children + 1] = row
	end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = children,
	}
end)

LagerErsetzenInfoWindow = react.RegisterWrapperRecipe("NalathanLagerErsetzenInfoWindow", builtin.Window, function(_params)
	return builtin.Window{
		title = _("LAGERERSETZEN_INFO_TITLE"),
		closable = true,
		id = "nalathanLagerErsetzenInfo",
		onClose = closeInfoWindow,
		content = LagerErsetzenInfoPanel({}),
	}
end)

local function openWindow()
	local windowApi = game_react_globals.getDefaultWindowApi()
	if windowApi then
		windowApi.removeAllWindows(LagerErsetzenWindow)
		windowApi.addSingletonWindow(LagerErsetzenWindow, {})
	end
end

local function closeWindow()
	local windowApi = game_react_globals.getDefaultWindowApi()
	if windowApi then
		windowApi.removeAllWindows(LagerErsetzenWindow)
	end
end

local LagerErsetzenPlugin = react.RegisterPluginRecipe(game_bar_widgets.GameBarInfoDisplayExtension, "NalathanLagerErsetzenPlugin", function()
	local status = engine_react_util.useStepStateTimer(makeStatus, 0.5)
	local shownIncident = react.useRef(0)
	local windowOpen = react.useRef(false)
	local current = status:old()

	react.onStepTimer(function()
		local st = makeStatus()
		if st.mode == "ask" and shownIncident:get() ~= st.incident then
			shownIncident:set(st.incident)
			windowOpen:set(true)
			openWindow()
		elseif #st.items == 0 and windowOpen:get() then
			windowOpen:set(false)
			closeWindow()
			closeInfoWindow()
		end
	end, 0.5)

	if #current.items == 0 then
		return builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = {},
		}
	end

	local parts = {}
	for __, need in ipairs(current.needs) do
		parts[#parts + 1] = need.modules .. "x " .. _("LAGERERSETZEN_TYPE_" .. need.class)
	end
	local barNeeds = #parts > 0 and (": " .. table.concat(parts, ", ")) or ""

	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.Button{
				meta = { class = "primary", tooltip = _("LAGERERSETZEN_OPEN") },
				content = makeText(string.format(_("LAGERERSETZEN_BAR"), current.total) .. barNeeds),
				onClick = function()
					windowOpen:set(true)
					closeInfoWindow()
					openWindow()
				end,
			},
		},
	}
end)

function data()
	return {
		LagerErsetzenPlugin = LagerErsetzenPlugin,
	}
end
