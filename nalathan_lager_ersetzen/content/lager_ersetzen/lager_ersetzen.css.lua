local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
	local result = { }

	local a = ssu.makeAdder(result)

	a("R::NalathanLagerErsetzenPlugin", {
		gravity = { 0.5, 0.5 },
	})

	a("R::NalathanLagerErsetzenPlugin Button", {
		gravity = { 0, 0.5 },
		padding = { 1, 10, 1, 10 },
	})

	a("Window#nalathanLagerErsetzenWindow", {
		size = { 520, -1 },
		anchorPoint = { 0.5, 0.5 },
		gravity = { 0.5, 0.5 },
	})

	a("R::NalathanLagerErsetzenPanel TextView", {
		maxSize = { 488, -1 },
		textAutoWrap = true,
	})

	a("R::NalathanLagerErsetzenCard TextView", {
		maxSize = { 420, -1 },
		textAutoWrap = true,
	})

	a("Window#nalathanLagerErsetzenWindow Window::Content", {
		padding = { 12, 14, 16, 14 },
	})

	a("R::NalathanLagerErsetzenPanel BoxLayout", {
		innerSpacing = { 10, 10 },
	})

	a("R::NalathanLagerErsetzenPanel Button", {
		padding = { 6, 12, 6, 12 },
	})

	a("R::NalathanLagerErsetzenCard BoxLayout", {
		innerSpacing = { 8, 8 },
	})

	a("R::NalathanLagerErsetzenCard Button", {
		padding = { 4, 10, 4, 10 },
	})

	a("Window#nalathanLagerErsetzenInfo", {
		size = { 400, -1 },
		anchorPoint = { 0.5, 0.0 },
		gravity = { 0.5, 0.06 },
	})

	a("Window#nalathanLagerErsetzenInfo Window::Content", {
		padding = { 10, 12, 12, 12 },
	})

	a("R::NalathanLagerErsetzenInfoPanel BoxLayout", {
		innerSpacing = { 6, 6 },
	})

	a("R::NalathanLagerErsetzenInfoPanel TextView", {
		maxSize = { 372, -1 },
		textAutoWrap = true,
	})

	return result
end
