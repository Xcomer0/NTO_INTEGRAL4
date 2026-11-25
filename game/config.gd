extends RefCounted
## Reads and checks scenario data before the UI constructs the simulation.

const DEFAULT_PATH := "res://data.json"
const MAX_VALUE := 1_000_000

static func for_args(args: PackedStringArray) -> Dictionary:
	for arg in args:
		if not arg.begins_with("--config="):
			continue
		var path := arg.trim_prefix("--config=")
		var selected := read(path)
		if selected.error.is_empty():
			return {"data": selected.data, "custom": true, "notice": "Загружен сценарий %s." % path.get_file()}
		var fallback := read(DEFAULT_PATH)
		if fallback.error.is_empty():
			return {"data": fallback.data, "custom": false, "notice": "Внешний сценарий отклонён. %s Загружен стандартный сценарий." % selected.error}
		return {"data": {}, "custom": false, "notice": "Не удалось загрузить сценарий. %s" % fallback.error}
	var standard := read(DEFAULT_PATH)
	return {"data": standard.data, "custom": false, "notice": standard.error}

static func read(path: String) -> Dictionary:
	if path.is_empty():
		return {"data": {}, "error": "Укажите путь к JSON."}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"data": {}, "error": "Файл %s недоступен." % path.get_file()}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"data": {}, "error": "Ошибка JSON в строке %d." % parser.get_error_line()}
	var error := validate(parser.data)
	return {"data": parser.data if error.is_empty() else {}, "error": error}

static func validate(value: Variant) -> String:
	if not value is Dictionary:
		return "Сценарий должен содержать объект JSON."
	var ingredients: Variant = value.get("ingredients")
	var dishes: Variant = value.get("dishes")
	var waves: Variant = value.get("waves")
	if not ingredients is Array or ingredients.size() != 6:
		return "В ingredients должно быть 6 продуктов."
	if not dishes is Array or dishes.size() != 4:
		return "В dishes должно быть 4 блюда."
	if not waves is Array or waves.is_empty():
		return "В waves нужна хотя бы одна перемена."
	for i in range(ingredients.size()):
		var ingredient: Variant = ingredients[i]
		if not _named(ingredient) or not _whole(ingredient.get("stock")) or not _whole(ingredient.get("cost")):
			return "Проверьте name, stock и cost в ingredients[%d]." % i
	for i in range(dishes.size()):
		var error := _validate_dish(dishes[i], ingredients)
		if not error.is_empty():
			return "dishes[%d]. %s" % [i, error]
	for i in range(waves.size()):
		var wave: Variant = waves[i]
		if not _named(wave) or not _whole(wave.get("duration"), 35):
			return "Проверьте name и duration в waves[%d]." % i
		var orders: Variant = wave.get("orders")
		if not orders is Array or orders.is_empty():
			return "В waves[%d].orders нужен хотя бы один заказ." % i
		for j in range(orders.size()):
			var order: Variant = orders[j]
			if not order is Array or order.size() != 3:
				return "В waves[%d].orders[%d] нужны два индекса блюда и бюджет." % [i, j]
			if not _whole(order[0], 0, dishes.size()-1) or not _whole(order[1], 0, dishes.size()-1) or not _whole(order[2]):
				return "Недопустимое блюдо или бюджет в waves[%d].orders[%d]." % [i, j]
	return ""

static func _validate_dish(dish: Variant, ingredients: Array) -> String:
	if not _named(dish):
		return "Укажите name."
	var recipe: Variant = dish.get("recipe")
	if not recipe is Array or recipe.size() != 2:
		return "В recipe нужны два индекса продуктов."
	if not _whole(recipe[0], 0, ingredients.size()-1) or not _whole(recipe[1], 0, ingredients.size()-1) or recipe[0] == recipe[1]:
		return "В recipe нужны два разных допустимых индекса."
	for field in ["min", "price", "max", "cost"]:
		if not _whole(dish.get(field)):
			return "В %s нужно целое неотрицательное число." % field
	if dish.min > dish.price or dish.price > dish.max:
		return "Требуется min ≤ price ≤ max."
	if dish.cost != ingredients[int(recipe[0])].cost + ingredients[int(recipe[1])].cost:
		return "В cost нужна сумма стоимости продуктов рецепта."
	if not _whole(dish.get("time"), 1) or not _whole(dish.get("station"), 0, 1):
		return "Проверьте time и station."
	return ""

static func _named(record: Variant) -> bool:
	if not record is Dictionary:
		return false
	var name: Variant = record.get("name")
	return name is String and not name.strip_edges().is_empty()

static func _whole(value: Variant, minimum: int = 0, maximum: int = MAX_VALUE) -> bool:
	if not (value is int or value is float):
		return false
	return is_finite(value) and value == floor(value) and value >= minimum and value <= maximum
