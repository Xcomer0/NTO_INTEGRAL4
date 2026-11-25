extends SceneTree
const Rules = preload("res://model.gd")
var game
var checks: Array=[]
var failed: Array=[]

func check(ok: bool, name: String) -> void:
	checks.append({"test":name,"pass":ok})
	if not ok: failed.append(name)

func find_button(root_node: Node, text: String) -> Button:
	if root_node is Button and root_node.text==text: return root_node
	for c in root_node.get_children():
		var found=find_button(c,text)
		if found: return found
	return null

func has_label(root_node: Node, fragment: String) -> bool:
	if root_node is Label and fragment in root_node.text: return true
	for child in root_node.get_children():
		if has_label(child,fragment): return true
	return false

func snap(name: String) -> void:
	await process_frame
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://../tests/screenshots/"+name+".png")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../tests/screenshots"))
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	await process_frame; await process_frame
	await snap("title")
	var start=find_button(game.ui,"Начать смену")
	check(start!=null,"Start is a mouse button")
	start.pressed.emit(); await process_frame
	check(game.running and game.m.phase=="plan","Start button enters shift")
	check(game.room.camera.projection==Camera3D.PROJECTION_PERSPECTIVE,"Camera is first-person perspective")
	check(game.room.camera.position.y>1.5,"Camera is at human eye height")
	await snap("first_person")
	for pair in [["plan","plan"],["cook","cook"],["serve","serve"],["stock",""],["report",""]]:
		game.close_modal()
		var target: Vector3=game.room.spots[pair[0]].global_position
		game.room.camera.look_at(target)
		game.yaw=game.room.camera.rotation_degrees.y; game.pitch=game.room.camera.rotation_degrees.x
		await physics_frame
		var hit: Dictionary=game.ray_at(Vector2(720,450))
		print("RAY ",pair[0]," got ",str(hit.collider.get_meta("action","")) if not hit.is_empty() else "empty"," yaw=",game.yaw," pitch=",game.pitch)
		check(not hit.is_empty() and str(hit.collider.get_meta("action",""))==pair[0],"World ray identifies "+pair[0])
		var down:=InputEventMouseButton.new(); down.position=Vector2(720,450); down.button_index=MOUSE_BUTTON_LEFT; down.pressed=true
		game._unhandled_input(down)
		var up:=InputEventMouseButton.new(); up.position=Vector2(720,450); up.button_index=MOUSE_BUTTON_LEFT; up.pressed=false
		game._unhandled_input(up)
		check(not game.overlay.get_children().is_empty(),"Mouse click opens "+pair[0])
		game.m.reset()
	game.close_modal(); game.yaw=0; game.pitch=-8
	game.show_kitchen()
	check(not game.paused,"Kitchen window does not stop time")
	var cook=find_button(game.overlay,"Готовить · 14 с")
	cook.pressed.emit(); game.m.tick(15); game.refresh()
	check(game.m.portions(0)==3,"Cooking button produces chosen batch")
	await snap("kitchen")
	game.show_plan(); check(game.paused,"Menu pauses for planning")
	var price_before: int=game.m.prices[0]
	find_button(game.overlay,"−5").pressed.emit()
	check(game.m.prices[0]==price_before-5,"Menu price button changes model")
	await snap("plan")
	find_button(game.overlay,"Позвать на перемену").pressed.emit()
	game.m.tick(6); game.refresh(); game.show_serving()
	check(not game.paused,"Serving window does not stop time")
	await snap("serving")
	var serving_button=find_button(game.overlay,"♥ 40")
	check(serving_button!=null and not serving_button.disabled,"Affordable ready dish can be served with mouse")
	if serving_button: serving_button.pressed.emit()
	check(game.m.served==1,"Serving button makes exactly one sale")
	game.close_modal(); game.m.tick(25); game.room.update_guests(game.m.customers)
	check(not game.m.customers.is_empty(),"Next guest arrives in same room")
	if not game.m.customers.is_empty():
		game.action("dish0")
		check(game.held_dish==0 and game.room.held_food.visible,"3D dish puts food on first-person tray")
		var guest_pos: Vector3=game.room.guest_bodies[0].global_position
		game.room.camera.look_at(guest_pos); game.yaw=game.room.camera.rotation_degrees.y; game.pitch=game.room.camera.rotation_degrees.x
		await physics_frame
		var guest_hit: Dictionary=game.ray_at(Vector2(720,450))
		check(not guest_hit.is_empty() and str(guest_hit.collider.get_meta("action",""))=="guest0","Ray selects pupil through counter")
		await snap("tray_and_guest")
		game.action("guest0")
		check(game.m.served==2 and game.held_dish==-1,"Direct first-person serving consumes tray once")
		await snap("direct_serving")
	game.close_modal(); game.m.tick(181); game.m.open_wave(); game.m.tick(201)
	game.last_phase=game.m.phase; game.show_transition()
	await snap("event")
	game.close_modal(); game.m.reserve(); game.m.open_wave(); game.m.tick(221)
	game.show_report(); await snap("final_report")
	check(find_button(game.overlay,"Ещё одна смена")!=null,"Final report has mouse restart")
	find_button(game.overlay,"Ещё одна смена").pressed.emit()
	check(game.m.cash==1000 and game.m.wave==0,"Final restart resets shift")
	var expanded: Dictionary=game.m.data.duplicate(true)
	expanded.waves[0].orders.append([3,0,99])
	game.m=Rules.new(expanded)
	game.start_game()
	check(game.labels.served.text.ends_with("/ 25"),"HUD uses the total from the selected scenario")
	game.show_report()
	check(has_label(game.overlay,"Обслужено 0 из 25"),"Report uses the total from the selected scenario")
	var f=FileAccess.open("res://../tests/ui-results.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"passed":checks.size()-failed.size(),"failed":failed},"  "))
	print("UI TESTS ",checks.size()-failed.size(),"/",checks.size()," failures: ",failed)
	quit(0 if failed.is_empty() else 1)
