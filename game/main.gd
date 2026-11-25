extends Node2D
const Rules = preload("res://model.gd")
const GameConfig = preload("res://config.gd")
var m: Rules
var config_notice := ""
var custom_config := false
var ui := Control.new()
var overlay := Control.new()
var font := ThemeDB.fallback_font
var time := 0.0
var refresh_time := 0.0
var running := false
var paused := false
var muted := false
var tab := "kitchen"
var batch_size := 3
var selection := 0
var labels: Dictionary = {}
var queue_key := ""
var queue_panel: Control
var dish_buttons: Array = []
var cook_buttons: Array = []
var forecast_labels: Array = []
var serving_buttons: Array = []
var station_labels: Array = []
var sound := AudioStreamPlayer.new()
var best := 0
var last_phase := "plan"
var demo := ""
var demo_clock := 0.0
var demo_step := -1
var room: Node3D
var view: SubViewport
var screen: TextureRect
var yaw := 0.0
var pitch := -8.0
var press_pos := Vector2.ZERO
var dragging := false
var hover_action := ""
var capture := ""
var capture_done := false
var active_window := ""
var window_status: Label
var plan_values: Array=[]
var view_status: Label
var room_elapsed:=0.0
var wait_labels: Dictionary={}
var held_dish: int=-1

const BG = Color("121e26")
const PANEL = Color("20343d")
const INK = Color("f6e8c9")
const MINT = Color("9bc6a4")
const GOLD = Color("efbb68")
const MUTED = Color("a8b6b1")

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var scenario := GameConfig.for_args(args)
	config_notice=scenario.notice; custom_config=scenario.custom
	if not scenario.data.is_empty():
		m=Rules.new(scenario.data)
	view=SubViewport.new(); view.size=Vector2i(720,450); view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.own_world_3d=true; add_child(view)
	room=load("res://room.gd").new(); view.add_child(room)
	screen=TextureRect.new(); screen.texture=view.get_texture(); screen.size=Vector2(1440,900)
	screen.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST; screen.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(screen)
	ui.mouse_filter=Control.MOUSE_FILTER_IGNORE; overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(ui); add_child(overlay); add_child(sound)
	if not custom_config and FileAccess.file_exists("user://best.json"):
		var record=JSON.parse_string(FileAccess.get_file_as_string("user://best.json"))
		if record is Dictionary: best=int(record.get("best",0))
	for arg in args:
		if arg.begins_with("--demo="): demo=arg.trim_prefix("--demo=")
		if arg.begins_with("--capture="): capture=arg.trim_prefix("--capture=")
	if m!=null and (not demo.is_empty() or (not capture.is_empty() and capture!="title")): start_game()
	else: show_title()

func box(parent: Node, pos: Vector2, size: Vector2, color: Color=PANEL) -> Panel:
	var p:=Panel.new(); p.position=pos; p.size=size
	var style:=StyleBoxFlat.new(); style.bg_color=color
	style.border_color=Color("426068"); style.set_border_width_all(2)
	p.add_theme_stylebox_override("panel",style); parent.add_child(p)
	return p

func text_at(parent: Node, s: String, pos: Vector2, width: float, size: int=20, color: Color=INK) -> Label:
	var l:=Label.new(); l.position=pos; l.size=Vector2(width,30)
	l.text=s; l.add_theme_font_size_override("font_size",size); l.add_theme_color_override("font_color",color)
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(l); return l

func button(parent: Node, s: String, pos: Vector2, size: Vector2, action: Callable, accent: bool=false) -> Button:
	var b:=Button.new(); b.text=s; b.position=pos; b.size=size
	b.add_theme_font_size_override("font_size",18)
	for state in ["normal","hover","pressed","disabled"]:
		var st:=StyleBoxFlat.new(); st.bg_color=(Color("a7cbaa") if accent else Color("304951"))
		if state=="hover": st.bg_color=Color("507068") if not accent else Color("c6dfba")
		if state=="pressed": st.bg_color=Color("739c85")
		if state=="disabled": st.bg_color=Color("26383d")
		st.set_border_width_all(2); st.border_color=Color("58726c")
		b.add_theme_stylebox_override(state,st)
	b.add_theme_color_override("font_color",BG if accent else INK)
	b.add_theme_color_override("font_hover_color",BG if accent else INK)
	b.add_theme_color_override("font_disabled_color",Color("718381"))
	b.pressed.connect(action); parent.add_child(b); return b

func clear(node: Node) -> void:
	for c in node.get_children(): node.remove_child(c); c.queue_free()

func show_title() -> void:
	running=false; paused=false; clear(ui); clear(overlay); yaw=0; pitch=-8; active_window=""
	var shade:=ColorRect.new(); shade.color=Color(.035,.07,.065,.86); shade.position=Vector2(0,0); shade.size=Vector2(680,900); shade.mouse_filter=Control.MOUSE_FILTER_IGNORE; ui.add_child(shade)
	text_at(ui,"ИНТЕГРАЛ  /  УЮТНЫЕ ИСТОРИИ",Vector2(58,90),590,19,MINT)
	text_at(ui,"БОЛЬШАЯ\nПЕРЕМЕНА",Vector2(52,178),640,65)
	text_at(ui,"Столовая глазами того, кто заботится",Vector2(58,365),580,23,GOLD)
	text_at(ui,"Планируйте меню, готовьте обеды и помогайте\nученикам успеть к звонку. Каждое решение\nотзывается на следующей перемене.",Vector2(58,421),570,22,INK)
	var start_button=button(ui,"Начать смену",Vector2(58,567),Vector2(500,66),start_game,true)
	start_button.disabled=m==null
	button(ui,"Как играть",Vector2(58,649),Vector2(500,58),show_help)
	text_at(ui,"От первого лица · Управление мышью\nОколо 12–15 минут · 12+",Vector2(58,757),570,19,MUTED)
	if best>0: text_at(ui,"Лучший результат  %d / 100"%best,Vector2(58,710),560,20,GOLD)
	if not config_notice.is_empty(): text_at(ui,config_notice,Vector2(58,826),565,16,GOLD)

func start_game() -> void:
	if m==null: return
	m.reset(); running=true; paused=false; last_phase="plan"; tab="kitchen"; batch_size=3; selection=0
	held_dish=-1
	if room: room.set_held_dish(-1)
	clear(overlay); build_ui(); refresh()

func build_ui() -> void:
	clear(ui); labels.clear(); queue_key=""; active_window=""
	var top=box(ui,Vector2(28,24),Vector2(400,95),Color(.07,.14,.13,.9))
	labels.phase=text_at(top,"",Vector2(16,11),370,18,MINT)
	labels.timer=text_at(top,"",Vector2(16,40),370,28)
	var money=box(ui,Vector2(1125,24),Vector2(285,95),Color(.07,.14,.13,.9))
	labels.money=text_at(money,"",Vector2(16,12),255,23,GOLD)
	labels.served=text_at(money,"",Vector2(16,48),255,18,INK)
	money.tooltip_text="В конце смены к оплате 300 ₽: зарплата 220 ₽ и коммунальные 80 ₽."
	button(ui,"Звук",Vector2(1186,134),Vector2(98,45),func(): muted=not muted; m.message="Звук выключен." if muted else "Звук включён.")
	button(ui,"?",Vector2(1296,134),Vector2(50,45),show_help)
	button(ui,"II",Vector2(1358,134),Vector2(50,45),show_pause)
	var context=box(ui,Vector2(275,679),Vector2(890,48),Color(.06,.12,.11,.86))
	labels.context=text_at(context,"Нажмите на предмет, чтобы взаимодействовать",Vector2(16,10),860,19,INK)
	var dock=box(ui,Vector2(290,751),Vector2(865,68),Color(.07,.14,.13,.92))
	var names=["Меню","Кухня","Раздача","Склад","Журнал"]
	var actions=[show_plan,show_kitchen,show_serving,show_stock,show_report]
	for i in range(5): button(dock,names[i],Vector2(8+i*171,8),Vector2(165,51),actions[i])
	button(ui,"‹ Обзор",Vector2(28,753),Vector2(155,52),func(): yaw=clampf(yaw+22,-65,65))
	button(ui,"Обзор ›",Vector2(1256,753),Vector2(155,52),func(): yaw=clampf(yaw-22,-65,65))
	var hint=box(ui,Vector2(28,831),Vector2(1383,51),Color(.07,.14,.13,.94))
	labels.message=text_at(hint,"",Vector2(13,11),1355,17)
	labels.open=button(ui,"Позвать на перемену",Vector2(555,130),Vector2(330,49),ring_bell,true)

func refresh() -> void:
	if not running: return
	labels.money.text="%d ₽ в кассе"%m.cash
	labels.served.text="Обслужено  %d / %d"%[m.served,m.total_guests()]
	labels.phase.text="%02d / %02d   %s"%[m.wave+1,m.data.waves.size(),m.data.waves[m.wave].name]
	var remain: int=maxi(0,int(ceil(float(m.data.waves[m.wave].duration)-m.clock)))
	labels.timer.text="%02d:%02d до звонка"%[remain/60,remain%60] if m.phase=="service" else "Планирование"
	labels.message.text=m.message
	labels.open.visible=m.phase=="plan"
	if not hover_action.is_empty(): labels.context.text="Нажмите: "+hover_action
	elif m.phase=="service" and not m.customers.is_empty(): labels.context.text="У раздачи ждут гости: %d. Нажмите на подносы."%m.customers.size()
	else: labels.context.text="Зажмите мышь для осмотра · Нажмите на предмет для действия"
	if active_window=="plan" and plan_values.size()==4:
		var prediction=m.forecast()
		for i in range(4): plan_values[i].text="%d ₽      %d гост.     %d порц."%[m.prices[i],prediction[i],m.portions(i)]
	if active_window=="cook" and is_instance_valid(window_status):
		window_status.text=""
		for j in range(2):
			window_status.text+=("Плита: " if j==0 else "Печь: ")+("свободна" if m.stations[j].is_empty() else "%s ×%d · осталось %d с"%[m.data.dishes[int(m.stations[j].dish)].name,m.stations[j].n,ceili(m.stations[j].left)])+"\n"
		window_status.text+=m.message
	if active_window=="serve" and is_instance_valid(queue_panel):
		var ids: Array=[]
		for c in m.customers: ids.append(c.id)
		var key:=str(ids)+str(m.batches)+str(m.prices)
		if key!=queue_key: queue_key=key; build_queue()
		for c in m.customers:
			if wait_labels.has(c.id) and is_instance_valid(wait_labels[c.id]): wait_labels[c.id].text="%s · до %d ₽ · %d с"%[c.name,c.budget,90-ceili(c.wait)]

func build_queue() -> void:
	clear(queue_panel)
	wait_labels.clear()
	text_at(queue_panel,"03  РАЗДАЧА",Vector2(18,12),420,20,GOLD)
	if m.customers.is_empty():
		text_at(queue_panel,"Подносы ждут гостей",Vector2(25,100),420,26)
		text_at(queue_panel,"Подготовьте блюда по прогнозу.\nПечь и плита работают одновременно.\n\nГотовые порции без мармита списываются\nпосле каждой перемены.",Vector2(25,151),420,19,MUTED)
	for j in range(mini(4,m.customers.size())):
		var c: Dictionary=m.customers[j]
		var y:=55+j*77
		wait_labels[c.id]=text_at(queue_panel,"%s · до %d ₽ · %d с" % [c.name,c.budget,90-ceili(c.wait)],Vector2(18,y),255,18)
		text_at(queue_panel,"%s / замена: %s" % [m.data.dishes[int(c.pref)].name,m.data.dishes[int(c.alt)].name],Vector2(18,y+29),274,15,MUTED)
		for z in range(2):
			var d: int=int(c.pref) if z==0 else int(c.alt)
			var b=button(queue_panel,"%s %d" % ["♥" if z==0 else "↔",m.prices[d]],Vector2(288+z*88,y+4),Vector2(80,49),func():
				if m.serve(int(c.id),d): beep(880)
				refresh(),z==0)
			b.tooltip_text="%s: готово %d порц. Цена %d ₽." % [m.data.dishes[d].name,m.portions(d),m.prices[d]]
			b.disabled=not m.eligible(c,d) or m.portions(d)==0

func modal(title: String, height: int=620) -> Panel:
	paused=true; active_window=""; clear(overlay)
	var dim:=ColorRect.new(); dim.color=Color(0.02,0.04,0.05,0.82); dim.size=Vector2(1440,900); overlay.add_child(dim)
	var p=box(overlay,Vector2(170,(900-height)/2.0),Vector2(1100,height),BG)
	text_at(p,title,Vector2(32,22),970,30,GOLD)
	button(p,"Закрыть",Vector2(920,20),Vector2(150,44),close_modal)
	return p

func close_modal() -> void:
	clear(overlay); paused=false; active_window=""; plan_values.clear(); queue_key=""; refresh()

func show_help() -> void:
	var p=modal("Как провести хорошую перемену",655)
	text_at(p,"1   Посмотрите спрос",Vector2(34,94),1000,24,MINT)
	text_at(p,"Нажмите на терминал или кнопку «Меню»: там цена, прогноз заказов и готовые порции.\nКнопки − / + меняют цену на 5 ₽. Дорогой обед может не поместиться в бюджет гостя.",Vector2(34,135),1030,21)
	text_at(p,"2   Приготовьте партии",Vector2(34,213),1000,24,MINT)
	text_at(p,"Выберите размер партии и нажмите «Готовить». Каша, суп и паста делят плиту; булочки\nпекутся параллельно. Молоко общее для каши и булочек. Наведите на кнопку для рецепта.",Vector2(34,254),1030,21)
	text_at(p,"3   Откройте перемену и помогите гостям",Vector2(34,332),1000,24,MINT)
	text_at(p,"В сцене нажмите на готовое блюдо, затем на ученика. При наведении виден его бюджет.\nВ окне «Раздача» можно выдать любимое ♥ или замену ↔. Гость ждёт до 90 секунд.",Vector2(34,373),1030,21)
	text_at(p,"4   Пересмотрите план",Vector2(34,451),1000,24,MINT)
	text_at(p,"В «Складе» плановая доставка прибывает при открытии перемены. Срочная приходит\nсразу с доплатой 40%. После первой волны доступно одно улучшение. Перед последней\nпеременой проверьте бюджеты. Итог учитывает сервис, довольство и прибыль.",Vector2(34,492),1030,21)
	text_at(p,"Терминал, склад и журнал ставят игру на паузу. Кухня и раздача работают вживую. 12+",Vector2(34,604),1000,17,MUTED)

func show_pause() -> void:
	var p=modal("Перерыв на чай",360)
	text_at(p,"Смена на паузе. Можно спокойно обдумать следующий шаг.",Vector2(34,110),1030,24)
	button(p,"Продолжить",Vector2(34,200),Vector2(290,64),close_modal,true)
	button(p,"Начать заново",Vector2(354,200),Vector2(290,64),confirm_restart)
	button(p,"Главное меню",Vector2(674,200),Vector2(290,64),func(): paused=false; show_title())

func confirm_restart() -> void:
	var p=modal("Начать смену заново",300)
	text_at(p,"Текущий план и результаты смены сбросятся. Лучший результат сохранится.",Vector2(34,105),1010,22)
	button(p,"Начать новую смену",Vector2(34,192),Vector2(350,60),start_game,true)

func show_stock() -> void:
	var p=modal("Склад и поставки",660)
	text_at(p,"Плановая: +5 ед. при звонке. Срочная: +5 ед. сразу, доплата 40%.",Vector2(34,83),1030,21,MUTED)
	for i in range(6):
		var y:=130+i*64
		var pending_n:=0
		for order in m.pending:
			if int(order.i)==i: pending_n+=int(order.n)
		text_at(p,"%s   %d ед.   (+%d в пути)" % [m.data.ingredients[i].name,m.stock[i],pending_n],Vector2(34,y+8),500,22)
		var cost: int=int(m.data.ingredients[i].cost)*5
		var b=button(p,"Заказать · %d ₽" % cost,Vector2(565,y),Vector2(225,47),func(): m.buy(i,false); show_stock())
		b.disabled=m.phase!="plan"
		button(p,"Срочно · %d ₽" % (cost+int(ceil(cost*0.4))),Vector2(805,y),Vector2(250,47),func(): m.buy(i,true); show_stock())
	text_at(p,"Срочных поставок: %d / 6. Касса: %d ₽. К закрытию ещё к оплате 300 ₽.\n%s" % [m.emergency_used,m.cash,m.message],Vector2(34,531),1030,19,GOLD)
	if m.is_last_wave() and m.phase=="plan" and not m.reserve_used:
		var names=[m.data.ingredients[0].name,m.data.ingredients[1].name]
		button(p,"Принять резерв школы: %s +5, %s +5"%names,Vector2(34,602),Vector2(1020,40),func(): m.reserve(); show_stock(),true)

func show_report() -> void:
	var p=modal("Итоги смены" if m.phase=="end" else "Журнал смены и оборудование",730)
	text_at(p,"Обслужено %d из %d   /   Пропущено %d   /   Довольство %d%%" % [m.served,m.total_guests(),m.missed,int(m.happiness/m.served) if m.served>0 else 0],Vector2(34,89),1030,24,MINT)
	text_at(p,"Выручка                         %d ₽\nПродукты проданных порций   −%d ₽\nСписания                         −%d ₽\nСрочные доплаты                −%d ₽\nОборудование                    −%d ₽\nЗарплата и коммунальные     −%d ₽" % [m.revenue,m.cogs,m.waste,m.premiums,m.investment,m.fixed],Vector2(34,150),610,23)
	text_at(p,"ПРИБЫЛЬ\n%d ₽" % m.profit(),Vector2(730,155),300,40,GOLD)
	text_at(p,"Счёт 300 ₽ оплачивается при закрытии.",Vector2(34,348),690,17,MUTED)
	text_at(p,"Касса: %d ₽\nЗапасы и остатки: %d ₽\nЗакупки: %d ₽\nВклад школы: %d ₽" % [m.cash,m.assets(),m.purchases,m.initial_assets],Vector2(730,275),320,20,MUTED)
	text_at(p,"Вывод для следующего плана",Vector2(34,385),1000,23,MINT)
	text_at(p,("Проверьте доступность меню: понижение цены открывает блюдо гостям с малым бюджетом." if m.missed>0 else "Все пришедшие гости обслужены. Сохраните этот план и следите за остатками.")+"\n"+("Готовьте меньшие партии: непроданные порции списываются по себестоимости." if m.waste>0 else "Продукты использованы бережно. Печь может работать одновременно с плитой."),Vector2(34,425),1030,21)
	if m.phase=="end":
		text_at(p,"Результат   %d / 100     Лучший   %d / 100" % [m.rating(),best],Vector2(34,524),1030,32,GOLD)
		text_at(p,"Нина: Забота начинается с плана. Спасибо за эту смену!",Vector2(34,580),1030,22)
		button(p,"Ещё одна смена",Vector2(34,641),Vector2(490,58),start_game,true)
		button(p,"В главное меню",Vector2(554,641),Vector2(490,58),func(): paused=false; show_title())
	else:
		text_at(p,"Одно улучшение после первой перемены. Выбор действует до конца смены.",Vector2(34,525),1030,20,MUTED)
		var b=button(p,"Мармит · 120 ₽\nПорции переживут ещё одну перемену",Vector2(34,578),Vector2(490,83),func(): m.invest("warmer"); show_report(),true)
		b.disabled=m.wave<1 or not m.upgrade.is_empty() or m.phase!="plan"
		b=button(p,"Большая посуда · 100 ₽\nПартии до 8; свыше 5 готовятся дольше",Vector2(554,578),Vector2(490,83),func(): m.invest("bulk"); show_report())
		b.disabled=m.wave<1 or not m.upgrade.is_empty() or m.phase!="plan"
		text_at(p,"%s" % m.message,Vector2(34,679),1030,17,GOLD)

func beep(freq: float) -> void:
	if muted: return
	var wav:=AudioStreamWAV.new(); wav.format=AudioStreamWAV.FORMAT_16_BITS; wav.mix_rate=22050
	var bytes:=PackedByteArray(); bytes.resize(4400)
	for i in range(2200):
		var value:=int(sin(float(i)*TAU*freq/22050.0)*2500.0*(1.0-float(i)/2200.0))
		bytes.encode_s16(i*2,value)
	wav.data=bytes; sound.stream=wav; sound.play()

func _process(delta: float) -> void:
	if m==null: return
	time+=delta; room_elapsed+=delta
	if room:
		room.camera.rotation_degrees=Vector3(pitch,yaw,0)
		room.update_room(m.customers.size() if running else 3,not m.stations[0].is_empty(),delta)
		room.update_guests(m.customers if running else [])
		room.update_dishes([m.portions(0),m.portions(1),m.portions(2),m.portions(3)] if running else [3,3,3,3],m.prices)
	if not capture.is_empty() and time>2 and not capture_done:
		capture_done=true
		capture_frame.call_deferred()

	if running and not paused:
		m.tick(delta)
		if held_dish>=0 and m.portions(held_dish)==0:
			held_dish=-1; room.set_held_dish(-1)
		if m.phase!=last_phase:
			last_phase=m.phase; beep(523)
			if m.phase=="end":
				best=maxi(best,m.rating())
				if not custom_config:
					var f=FileAccess.open("user://best.json",FileAccess.WRITE)
					if f: f.store_string(JSON.stringify({"best":best}))
				show_report()
			elif m.phase=="plan": show_transition()
	if not demo.is_empty(): run_demo(delta)
	refresh_time+=delta
	if refresh_time>0.35: refresh_time=0; refresh()
	queue_redraw()

func show_transition() -> void:
	var p=modal("Внеплановая группа" if m.is_last_wave() else "Перемена завершена",430)
	text_at(p,m.message,Vector2(34,106),1030,25)
	text_at(p,"Проверьте спрос и цены. Молоко нужно и каше, и булочкам.\nОтчёт объясняет потери, склад показывает доступные ресурсы.",Vector2(34,225),1030,22,MUTED)
	button(p,"Пересмотреть план",Vector2(34,335),Vector2(1020,60),close_modal,true)

func _draw() -> void:
	pass

func run_demo(delta: float) -> void:
	# Explicitly labelled automated recordings; no alternative game rules are used.
	demo_clock+=delta
	if paused and m.phase!="end": close_modal()
	if m.phase=="plan":
		if m.is_last_wave():
			m.reserve()
			for i in range(4): m.change_price(i,-5)
		if m.wave==1 and m.upgrade.is_empty(): m.invest("warmer")
		if demo_clock>3: m.open_wave()
	if m.phase=="service":
		for c in m.customers.duplicate():
			var d: int=m.preferred(c,true)
			if d>=0: m.serve(int(c.id),d)
		var prediction=m.forecast()
		for i in [0,3,1,2]:
			if m.portions(i)<2 and prediction[i]>0 and m.stations[int(m.data.dishes[i].station)].is_empty():
				for ing in m.data.dishes[i].recipe:
					if m.stock[int(ing)]<2: m.buy(int(ing),true)
				m.cook(i,2)
	if demo_clock>50 and demo=="core": get_tree().quit()
	if demo_clock>70 and demo=="game": get_tree().quit()
	if demo_clock>620 and demo=="user": get_tree().quit()

func capture_frame() -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../tests/screenshots"))
	var result=get_viewport().get_texture().get_image().save_png("res://../tests/screenshots/"+capture+".png")
	print("SCREENSHOT ",capture," ",result)
	get_tree().quit()

func show_plan() -> void:
	var p=modal("Терминал меню",640); active_window="plan"; plan_values.clear()
	text_at(p,"Цена открывает или закрывает блюдо гостям с разным бюджетом.",Vector2(34,88),1030,22,MUTED)
	text_at(p,"БЛЮДО                         ЦЕНА / СПРОС / ГОТОВО",Vector2(34,140),1010,20,MINT)
	for i in range(4):
		var y:=190+i*72
		text_at(p,m.data.dishes[i].name,Vector2(34,y+8),310,24)
		var lower:=button(p,"−5",Vector2(351,y),Vector2(60,51),func(): m.change_price(i,-5); refresh())
		lower.disabled=m.phase!="plan"
		plan_values.append(text_at(p,"",Vector2(440,y+12),420,23,GOLD))
		var raise:=button(p,"+5",Vector2(935,y),Vector2(100,51),func(): m.change_price(i,5); refresh())
		raise.disabled=m.phase!="plan"
	text_at(p,"Спрос пересчитывается по текущим ценам и бюджетам ожидаемых гостей.\nЦены фиксируются на время перемены. Готовое без мармита списывается после звонка.",Vector2(34,496),1030,21,MUTED)
	button(p,"К кухне",Vector2(34,576),Vector2(490,44),show_kitchen,true)
	var bell:=button(p,"Позвать на перемену",Vector2(550,576),Vector2(490,44),func(): close_modal(); ring_bell())
	bell.disabled=m.phase!="plan"
	refresh()

func show_kitchen() -> void:
	var p=modal("Кухня перед вами",690); active_window="cook"; paused=false
	text_at(p,"Одна плита и отдельная печь. Они работают параллельно.",Vector2(34,90),1030,23,MUTED)
	button(p,"−",Vector2(34,137),Vector2(60,43),func(): batch_size=maxi(1,batch_size-1); show_kitchen())
	text_at(p,"Партия  ×%d"%batch_size,Vector2(120,141),245,24,GOLD)
	button(p,"+",Vector2(340,137),Vector2(60,43),func(): batch_size=mini(8 if m.upgrade=="bulk" else 5,batch_size+1); show_kitchen())
	for i in range(4):
		var y:=210+i*76
		var d=m.data.dishes[i]
		text_at(p,d.name,Vector2(34,y),300,24)
		text_at(p,"%s + %s · %d ₽/порц."%[m.data.ingredients[int(d.recipe[0])].name,m.data.ingredients[int(d.recipe[1])].name,d.cost],Vector2(34,y+32),660,18,MUTED)
		button(p,"Готовить · %d с"%d.time,Vector2(755,y),Vector2(285,54),func(): m.cook(i,batch_size); refresh(),true)
	window_status=text_at(p,"",Vector2(34,534),1010,20,GOLD)
	text_at(p,"Готовка продолжается при открытом окне. Для паузы нажмите «Отдохнуть».",Vector2(34,647),1030,17,MUTED)
	button(p,"Отдохнуть",Vector2(730,20),Vector2(170,44),show_pause)
	refresh()

func show_serving() -> void:
	var p=modal("Раздача обедов",620); active_window="serve"; paused=false; queue_key=""
	button(p,"Отдохнуть",Vector2(730,20),Vector2(170,44),show_pause)
	text_at(p,"У каждого гостя есть любимое блюдо, подходящая замена и бюджет.",Vector2(34,85),1030,22,MUTED)
	queue_panel=box(p,Vector2(295,145),Vector2(482,370))
	text_at(p,"Кнопка ♥ — любимое блюдо. ↔ — замена. Наведите курсор на кнопку для названия.\nЕсли порции закончились, вернитесь к плите. Ученик может подождать 90 секунд.",Vector2(34,540),1020,19,MUTED)
	build_queue()

func action(name: String) -> void:
	if name.begins_with("dish"):
		var dish:=int(name.trim_prefix("dish"))
		if m.portions(dish)>0:
			held_dish=dish; room.set_held_dish(dish)
			m.message="На подносе: %s. Нажмите на ученика, чтобы выдать. Его бюджет виден при наведении."%m.data.dishes[dish].name
		else: m.message="%s пока нет на раздаче. Нажмите на плиту или печь и приготовьте партию."%m.data.dishes[dish].name
		refresh(); return
	if name.begins_with("guest"):
		var index:=int(name.trim_prefix("guest"))
		if index<m.customers.size():
			if held_dish<0: m.message="Сначала возьмите готовое блюдо: нажмите на один из четырёх лотков на стойке."
			elif m.serve(int(m.customers[index].id),held_dish):
				beep(880); held_dish=-1; room.set_held_dish(-1)
		refresh(); return
	match name:
		"plan": show_plan()
		"cook": show_kitchen()
		"serve": show_serving()
		"stock": show_stock()
		"report": show_report()
		"bell": ring_bell()

func ring_bell() -> void:
	if m.open_wave(): beep(660)
	refresh()

func ray_at(pos: Vector2) -> Dictionary:
	var coords:=pos*Vector2(.5,.5)
	var origin: Vector3=room.camera.project_ray_origin(coords)
	var target: Vector3=origin+room.camera.project_ray_normal(coords)*25
	var query:=PhysicsRayQueryParameters3D.create(origin,target)
	return room.get_world_3d().direct_space_state.intersect_ray(query)

func _unhandled_input(event: InputEvent) -> void:
	if not running or not overlay.get_children().is_empty(): return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed: press_pos=event.position; dragging=true
		else:
			dragging=false
			if event.position.distance_to(press_pos)<9:
				var result=ray_at(event.position)
				if not result.is_empty(): action(str(result.collider.get_meta("action","")))
	if event is InputEventMouseMotion:
		if dragging:
			yaw=clampf(yaw-event.relative.x*.15,-65,65)
			pitch=clampf(pitch-event.relative.y*.12,-32,16)
		else:
			var result=ray_at(event.position)
			hover_action=str(result.collider.get_meta("title","")) if not result.is_empty() else ""
