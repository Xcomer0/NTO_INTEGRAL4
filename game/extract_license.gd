extends SceneTree

func _initialize() -> void:
	var f = FileAccess.open("res://../deliverables/02_Игра/GODOT_LICENSE.txt", FileAccess.WRITE)
	if f:
		f.store_string(Engine.get_license_text())
		f.store_string("\n\nOfficial license information: https://godotengine.org/license/\n")
	var components = FileAccess.open("res://../deliverables/02_Игра/GODOT_THIRD_PARTY.json", FileAccess.WRITE)
	if components:
		components.store_string(JSON.stringify(Engine.get_license_info(), "  "))
	quit()
