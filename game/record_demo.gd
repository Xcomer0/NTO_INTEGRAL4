extends SceneTree
## Offline movie-writer demonstration. The original UI and original model rules run at 1x.
## This is automation evidence, not a human playtest. Excluded from release export.
var game
var elapsed:=0.0
var phase_start:=0.0
var plan_stage:=-1
var seen_wave:=-1
var end_at:=-1.0
var pending_serve_id:=-1
var pending_serve_at:=0.0
var close_at:=-1.0
var caption: Label
var events: Array=[]
var done:=false

func _initialize() -> void:
	game=load("res://main.tscn").instantiate()
	root.add_child.call_deferred(game)
	setup_banner.call_deferred()

func setup_banner() -> void:
	var layer:=CanvasLayer.new(); layer.layer=100; root.add_child(layer)
	var backdrop:=ColorRect.new(); backdrop.position=Vector2(445,18); backdrop.size=Vector2(660,79)
	backdrop.color=Color(.035,.075,.07,.94); backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE; layer.add_child(backdrop)
	caption=Label.new(); caption.position=Vector2(460,25); caption.size=Vector2(635,70)
	caption.add_theme_font_size_override("font_size",18); caption.add_theme_color_override("font_color",Color("f6e8c9"))
	caption.text="Автоматизированная демонстрация · 1×\nОригинальные правила и интерфейс игры"
	caption.mouse_filter=Control.MOUSE_FILTER_IGNORE; layer.add_child(caption)
	log_event("title")

func log_event(name: String) -> void:
	events.append({"event":name,"second":snappedf(elapsed,.1)})
	print("RECORD ",name," @ ",snappedf(elapsed,.1))

func _process(delta: float) -> bool:
	if not is_instance_valid(game) or not game.is_node_ready(): return false
	elapsed+=delta
	if seen_wave<0:
		if elapsed>=4 and plan_stage<0:
			game.start_game(); plan_stage=0; log_event("start")
		if elapsed>=5 and plan_stage==0:
			game.show_help(); plan_stage=1; log_event("help")
		if elapsed>=11 and plan_stage==1:
			game.show_plan(); plan_stage=2; log_event("first_plan")
		if elapsed>=17 and plan_stage==2:
			game.m.buy(1,false); game.show_stock(); plan_stage=3; log_event("purchase")
		if elapsed>=23 and plan_stage==3:
			game.batch_size=1; game.show_kitchen(); game.m.cook(0,1); game.m.cook(3,1); plan_stage=4; log_event("parallel_cooking")
		if elapsed>=27 and plan_stage==4:
			game.close_modal(); game.m.open_wave(); seen_wave=0; plan_stage=-1; log_event("wave_1")
		return false
	var m=game.m
	if m.phase=="end":
		if end_at<0: end_at=elapsed; log_event("final_report")
		if elapsed-end_at>12 and not done:
			done=true
			var f=FileAccess.open("res://../tests/recording_events.json",FileAccess.WRITE)
			if f: f.store_string(JSON.stringify({"events":events,"duration":elapsed,"served":m.served,"profit":m.profit(),"rating":m.rating(),"automation":true,"speed":1.0},"  "))
			quit()
		return false
	if m.phase=="plan":
		if m.wave!=seen_wave:
			seen_wave=m.wave; phase_start=elapsed; plan_stage=0; pending_serve_id=-1
			log_event("transition_"+str(m.wave))
		var t:=elapsed-phase_start
		if m.wave==1:
			if t>5 and plan_stage==0: game.show_report(); plan_stage=1; log_event("wave_1_report")
			if t>10 and plan_stage==1: m.invest("warmer"); game.show_report(); plan_stage=2; log_event("upgrade")
			if t>15 and plan_stage==2: game.show_plan(); plan_stage=3; log_event("second_plan")
			if t>22 and plan_stage==3: game.close_modal(); m.open_wave(); plan_stage=-1; log_event("wave_2")
		else:
			if t>6 and plan_stage==0: game.show_plan(); plan_stage=1; log_event("event_plan_before")
			if t>10 and plan_stage==1:
				for i in range(4):
					while m.prices[i]>int(m.data.dishes[i].min): m.change_price(i,-5)
				game.refresh(); plan_stage=2; log_event("event_price_change")
			if t>16 and plan_stage==2: m.reserve(); game.show_stock(); plan_stage=3; log_event("reserve")
			if t>24 and plan_stage==3: game.close_modal(); m.open_wave(); plan_stage=-1; log_event("wave_3")
		return false
	if close_at>=0 and elapsed>=close_at:
		game.close_modal(); close_at=-1
	if pending_serve_id>=0:
		if elapsed>=pending_serve_at:
			var index:=-1
			for i in range(m.customers.size()):
				if int(m.customers[i].id)==pending_serve_id: index=i; break
			if index>=0:
				game.action("guest"+str(index)); log_event("serve_"+str(pending_serve_id))
			pending_serve_id=-1
		return false
	# Respond to visible guests. Cooking is never accelerated and resources are never injected.
	for c in m.customers:
		var d: int=m.preferred(c,true)
		if d>=0:
			game.close_modal(); close_at=-1; game.action("dish"+str(d))
			pending_serve_id=int(c.id); pending_serve_at=elapsed+2.0
			game.yaw=0; game.pitch=-8
			log_event("tray_"+str(c.id)); return false
	for c in m.customers:
		var d: int=m.preferred(c)
		if d>=0 and m.portions(d)==0 and m.stations[int(m.data.dishes[d].station)].is_empty():
			game.show_kitchen(); game.batch_size=1
			if m.cook(d,1):
				game.refresh(); close_at=elapsed+4; log_event("cook_"+str(d))
			return false
	# A short visual glance around the same workplace, with no location changes.
	if game.overlay.get_child_count()==0:
		game.yaw=sin(elapsed*.12)*12
	return false
