function data()
	return {
		type = "react-plugin ::WarehouseEowExtensionPoint",
		data = {
			filePath = "nalathan_lager_ersetzen::/lager_ersetzen/lager_ersetzen_eow.script@LagerErsetzenCard",
			condition = "::/gui/entity_window/warehouse/warehouse_eow.script@isModifiable",
			order = 25,
		}
	}
end
