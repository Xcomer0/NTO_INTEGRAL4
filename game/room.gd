extends Node3D
## A single first-person room. All art is original geometry and pixel textures.
var camera: Camera3D
var people: Array=[]
var spots: Dictionary={}
var mats: Dictionary={}
var clock_hand: Node3D
var steam: Array=[]
var t:=0.0
var active_guests:=0
var held_food: MeshInstance3D
var guest_bodies: Array=[]
var dish_visuals: Array=[]

func material(color: String, pattern: String="") -> StandardMaterial3D:
	var key:=color+pattern
	if mats.has(key): return mats[key]
	var m:=StandardMaterial3D.new(); m.albedo_color=Color(color); m.roughness=0.88
	m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if not pattern.is_empty():
		var img:=Image.create(32,32,false,Image.FORMAT_RGBA8)
		var rng:=RandomNumberGenerator.new(); rng.seed=107
		for y in range(32):
			for x in range(32):
				var c:=Color(color)
				if pattern=="tile":
					if x%16==0 or y%16==0: c=c.darkened(0.2)
					elif (x/16+y/16)%2==0: c=c.lightened(0.09)
				elif pattern=="wood":
					if (y+int(x/7))%7==0: c=c.darkened(0.18)
					elif rng.randf()<0.08: c=c.lightened(0.13)
				elif pattern=="wall":
					if y%8==0 or (x+(8 if y/8%2==0 else 0))%16==0: c=c.darkened(0.1)
				elif rng.randf()<0.2: c=c.darkened(0.1)
				img.set_pixel(x,y,c)
		m.albedo_texture=ImageTexture.create_from_image(img); m.albedo_color=Color.WHITE
	mats[key]=m; return m

func block(parent: Node3D, pos: Vector3, size: Vector3, color: String, pattern: String="") -> MeshInstance3D:
	var mesh:=MeshInstance3D.new(); var shape:=BoxMesh.new(); shape.size=size
	mesh.mesh=shape; mesh.material_override=material(color,pattern); mesh.position=pos; parent.add_child(mesh)
	return mesh

func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, color: String) -> MeshInstance3D:
	var obj:=MeshInstance3D.new(); var mesh:=CylinderMesh.new()
	mesh.top_radius=radius; mesh.bottom_radius=radius; mesh.height=height; mesh.radial_segments=12
	obj.mesh=mesh; obj.material_override=material(color); obj.position=pos; parent.add_child(obj); return obj

func lettering(parent: Node3D, s: String, pos: Vector3, size: int=30, color: String="f7e6bb") -> Label3D:
	var label:=Label3D.new(); label.text=s; label.position=pos; label.font_size=size
	label.pixel_size=0.003; label.modulate=Color(color); label.outline_size=4; label.outline_modulate=Color("253a35")
	label.no_depth_test=false; parent.add_child(label); return label

func spot(action: String, title: String, pos: Vector3, size: Vector3) -> void:
	var body:=StaticBody3D.new(); body.position=pos
	body.set_meta("action",action); body.set_meta("title",title)
	var c:=CollisionShape3D.new(); var sh:=BoxShape3D.new(); sh.size=size; c.shape=sh
	body.add_child(c); add_child(body); spots[action]=body

func _ready() -> void:
	var env:=WorldEnvironment.new(); var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR; settings.background_color=Color("bdd7c5")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; settings.ambient_light_color=Color("f3ead5"); settings.ambient_light_energy=0.52
	settings.tonemap_mode=Environment.TONE_MAPPER_FILMIC; env.environment=settings; add_child(env)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-42,-35,0); sun.light_color=Color("fff0d5"); sun.light_energy=0.65; add_child(sun)
	camera=Camera3D.new(); camera.position=Vector3(0,1.68,2.25); camera.fov=66; camera.near=0.04; camera.current=true
	camera.rotation_degrees.x=-8; add_child(camera)
	# First-person sleeves and hands stay attached to the viewpoint.
	for side in [-1,1]:
		var sleeve=block(camera,Vector3(side*0.39,-0.52,-0.65),Vector3(0.18,0.18,0.52),"638c76")
		sleeve.rotation_degrees=Vector3(-18,side*-18,0)
		block(camera,Vector3(side*0.27,-0.43,-0.95),Vector3(0.13,0.1,0.16),"dcb28b")
	var tray=block(camera,Vector3(0,-0.44,-1.04),Vector3(0.57,0.025,0.36),"8ba49b")
	tray.rotation_degrees.x=8
	held_food=block(camera,Vector3(0,-.39,-1.05),Vector3(.32,.055,.23),"dfbd78"); held_food.visible=false
	# Architecture and warm flooring.
	block(self,Vector3(0,-0.09,-2.7),Vector3(9,0.18,12),"879d88","tile")
	block(self,Vector3(0,1.75,-8.1),Vector3(9,3.5,0.2),"e7d5ad","wall")
	block(self,Vector3(-4.5,1.75,-2.5),Vector3(0.2,3.5,11.4),"e6d6b7","wall")
	block(self,Vector3(4.5,1.75,-2.5),Vector3(0.2,3.5,11.4),"d9ceac","wall")
	block(self,Vector3(0,3.5,-2.7),Vector3(9,0.1,12),"f2dfba")
	for x in [-4.38,4.38]: block(self,Vector3(x,0.52,-2.5),Vector3(0.04,1.02,11.2),"5f897c","tile")
	block(self,Vector3(0,0.52,-7.96),Vector3(9,1.02,0.04),"5f897c","tile")
	# Large rear windows with a pixel landscape.
	for x in [-2.8,0.0,2.8]:
		block(self,Vector3(x,2.12,-7.9),Vector3(2.1,1.65,0.13),"76988a")
		block(self,Vector3(x,2.12,-7.8),Vector3(1.9,1.45,0.03),"bad9cd")
		block(self,Vector3(x,2.32,-7.75),Vector3(1.8,0.52,0.02),"d0e5d5")
		block(self,Vector3(x,1.57,-7.72),Vector3(1.8,0.27,0.02),"8eb79a")
		for j in range(5): block(self,Vector3(x-.8+j*.38,1.75+(j%2)*.15,-7.7),Vector3(.35,.5,.03),"9ac1a1")
		block(self,Vector3(x,2.12,-7.67),Vector3(0.045,1.48,0.03),"678e7b")
		block(self,Vector3(x,2.05,-7.65),Vector3(1.92,0.045,0.03),"678e7b")
		block(self,Vector3(x,1.3,-7.65),Vector3(2.2,0.07,.35),"b78d60","wood")
		block(self,Vector3(x+.42,2.5,-7.7),Vector3(.55,.13,.02),"f3e8c7")
	# Furniture in the dining room.
	for z in [-3.7,-6.0]:
		for x in [-2.5,2.5]:
			block(self,Vector3(x,.78,z),Vector3(1.8,.12,1.15),"c49967","wood")
			for dx in [-.67,.67]:
				for dz in [-.4,.4]: block(self,Vector3(x+dx,.38,z+dz),Vector3(.08,.75,.08),"637c69")
			for dz in [-.9,.9]:
				block(self,Vector3(x,.43,z+dz),Vector3(1.55,.1,.4),"b8895b","wood")
				for dx in [-.6,.6]: block(self,Vector3(x+dx,.2,z+dz),Vector3(.07,.4,.07),"4c7668")
			cylinder(self,Vector3(x,.87,z),.12,.05,"ece0bd")
	# School wall signs, clock and planters.
	block(self,Vector3(-.1,2.9,-7.72),Vector3(2.2,.32,.04),"3d6859")
	lettering(self,"ХОРОШЕГО ДНЯ",Vector3(-.1,2.9,-7.67),34)
	for x in [-4,4]: plant(Vector3(x,0,-7))
	# Pendant lamps with warm pools of light.
	for x in [-2.7,0,2.7]:
		cylinder(self,Vector3(x,3.15,-2.6),.018,.7,"506857")
		cylinder(self,Vector3(x,2.8,-2.6),.34,.16,"bd824c")
		cylinder(self,Vector3(x,2.71,-2.6),.25,.025,"f8d98e")
		var light:=OmniLight3D.new(); light.position=Vector3(x,2.55,-2.6); light.light_color=Color("ffdc99"); light.light_energy=.25; light.omni_range=4; add_child(light)
	# One continuous service counter creates the player's workplace.
	block(self,Vector3(0,.47,.3),Vector3(6.6,.94,.95),"557c6a","wood")
	block(self,Vector3(0,.98,.25),Vector3(6.9,.1,1.2),"c39b6a","wood")
	block(self,Vector3(0,1.045,.25),Vector3(6.8,.025,1.14),"e4d2a6","tile")
	for x in [-2.6,-1.3,0,1.3,2.6]:
		block(self,Vector3(x,.48,.8),Vector3(1.22,.72,.02),"688c78","wood")
		block(self,Vector3(x+.4,.7,.825),Vector3(.12,.025,.025),"d7bd84")
	# Four appetizing serving dishes and a glass guard.
	for i in range(4):
		var x: float=-.55+i*.39
		block(self,Vector3(x,1.095,-.03),Vector3(.33,.06,.39),"a6bab0")
		var visuals: Array=[block(self,Vector3(x,1.13,-.03),Vector3(.27,.045,.32),["e1ba72","be7844","ebc17b","b87c43"][i])]
		for j in range(5): visuals.append(block(self,Vector3(x-.1+(j%3)*.07,1.16,-.13+(j/3)*.12),Vector3(.055,.022,.055),"f0d99b" if i!=1 else "90a86c"))
		dish_visuals.append(visuals)
		spot("dish%d"%i,"%s · взять на поднос"%["Каша","Суп","Паста","Булочка"][i],Vector3(x,1.16,-.03),Vector3(.35,.16,.42))
	for x in [-.87,1.05]: block(self,Vector3(x,1.34,-.38),Vector3(.025,.56,.025),"638b7b")
	block(self,Vector3(.09,1.6,-.38),Vector3(1.95,.035,.04),"608675")
	spot("serve","РАЗДАЧА",Vector3(.1,1.78,-.38),Vector3(1.9,.16,.12))
	lettering(self,"РАЗДАЧА",Vector3(.1,1.78,-.36),28)
	# Left stove, with two stock pots and the actual timer label.
	block(self,Vector3(-2.5,1.15,-.05),Vector3(.98,.18,.8),"566a63")
	for x in [-2.75,-2.27]:
		cylinder(self,Vector3(x,1.29,-.03),.18,.22,"9daea2")
		cylinder(self,Vector3(x,1.41,-.03),.16,.025,"d5c6a0")
		block(self,Vector3(x-.23,1.33,-.03),Vector3(.1,.04,.07),"5b7065")
		for j in range(3): steam.append(block(self,Vector3(x-.09+j*.08,1.5+j*.08,-.04),Vector3(.035,.08,.035),"e9e1c8"))
	spot("cook","ПЛИТА И ПЕЧЬ",Vector3(-2.5,1.3,-.05),Vector3(1.1,.7,.95))
	lettering(self,"ПЛИТА",Vector3(-2.5,1.72,-.05),30)
	# Right oven with visible bread, clickable door.
	block(self,Vector3(2.6,1.34,-.05),Vector3(1.0,.57,.72),"d2cbb1")
	block(self,Vector3(2.6,1.29,.32),Vector3(.77,.3,.025),"344e46")
	for x in [2.38,2.59,2.8]: block(self,Vector3(x,1.25,.345),Vector3(.17,.075,.025),"d5a366")
	block(self,Vector3(2.6,1.47,.36),Vector3(.65,.025,.05),"607e6b")
	for x in [2.3,2.8]: cylinder(self,Vector3(x,1.6,.25),.045,.025,"aa7a4d")
	spot("cook","ПЕЧЬ И ПЛИТА",Vector3(2.6,1.35,.0),Vector3(1.05,.65,.9))
	lettering(self,"ПЕЧЬ",Vector3(2.6,1.9,-.05),30)
	# Small register: plan and prices live here, not in a permanent dashboard.
	block(self,Vector3(-1.44,1.14,.34),Vector3(.55,.16,.44),"466e60")
	var monitor=block(self,Vector3(-1.44,1.42,.22),Vector3(.52,.42,.07),"355b50"); monitor.rotation_degrees.x=-12
	block(self,Vector3(-1.44,1.43,.27),Vector3(.43,.3,.02),"9cbf9c")
	lettering(self,"МЕНЮ",Vector3(-1.44,1.43,.3),23,"213f33")
	spot("plan","ТЕРМИНАЛ МЕНЮ",Vector3(-1.44,1.36,.25),Vector3(.65,.65,.6))
	# Paper journal at the near edge of the workbench.
	var journal=block(self,Vector3(1.55,1.1,.5),Vector3(.58,.035,.43),"f1dcb0"); journal.rotation.y=-.13
	for j in range(4): block(self,Vector3(1.55,1.122,.37+j*.065),Vector3(.4,.003,.008),"ab9674")
	spot("report","ЖУРНАЛ СМЕНЫ",Vector3(1.55,1.15,.5),Vector3(.7,.3,.6))
	lettering(self,"ЖУРНАЛ",Vector3(1.55,1.38,.4),25)
	# Open shelves belong to the same room, no location transitions.
	for y in [.4,1.0,1.6]:
		block(self,Vector3(3.7,y,-2.5),Vector3(1.2,.06,.65),"b78e59","wood")
		for j in range(4):
			block(self,Vector3(3.25+j*.29,y+.16,-2.5),Vector3(.21,.28,.25),"e3cca0")
			block(self,Vector3(3.25+j*.29,y+.17,-2.35),Vector3(.13,.1,.01),["a9784e","7c9a76","bb8f56","7a9a96"][j])
	for x in [3.1,4.3]: block(self,Vector3(x,1.05,-2.5),Vector3(.07,2.1,.7),"537f6c")
	spot("stock","СКЛАД И ПОСТАВКИ",Vector3(3.7,2.05,-2.5),Vector3(1.3,.9,.8))
	lettering(self,"СКЛАД",Vector3(3.7,2.35,-2.3),34)
	# Bell is an in-world start control.
	cylinder(self,Vector3(-.87,1.13,.64),.1,.12,"d4aa59")
	spot("bell","ПОЗВАТЬ НА ПЕРЕМЕНУ",Vector3(-.87,1.24,.64),Vector3(.25,.25,.25))
	# Billboard pupils are original 16×32 pixel sprites.
	for i in range(5):
		var sprite:=Sprite3D.new(); sprite.texture=pupil_texture(i); sprite.pixel_size=.045
		sprite.billboard=BaseMaterial3D.BILLBOARD_ENABLED; sprite.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.position=Vector3(-.15+i*.62,.86,-1.9-i*.45); sprite.shaded=true; add_child(sprite); people.append(sprite)
		spot("guest%d"%i,"Ученик · выдать поднос",sprite.position+Vector3(0,.35,0),Vector3(.55,1.05,.25))
		guest_bodies.append(spots["guest%d"%i])
		guest_bodies[i].collision_layer=0

func set_held_dish(dish: int) -> void:
	held_food.visible=dish>=0
	if dish>=0: held_food.material_override=material(["dfbd78","be7844","ebc17b","b87c43"][dish])

func update_dishes(counts: Array, prices: Array) -> void:
	for i in range(4):
		for mesh in dish_visuals[i]: mesh.visible=counts[i]>0
		spots["dish%d"%i].set_meta("title","%s · %d порц. · %d ₽"%[["Каша","Суп","Паста","Булочка"][i],counts[i],prices[i]])

func update_guests(customers: Array) -> void:
	for i in range(guest_bodies.size()):
		guest_bodies[i].collision_layer=1 if i<customers.size() else 0
		if i<customers.size():
			var c: Dictionary=customers[i]
			guest_bodies[i].set_meta("title","%s · %s / %s · до %d ₽"%[c.name,["Каша","Суп","Паста","Булочка"][int(c.pref)],["Каша","Суп","Паста","Булочка"][int(c.alt)],c.budget])

func plant(pos: Vector3) -> void:
	cylinder(self,pos+Vector3(0,.2,0),.24,.4,"b57d54")
	for dx in [-.19,0,.19]:
		block(self,pos+Vector3(dx,.78+absf(dx),0),Vector3(.15,.75,.12),"638c67")
		block(self,pos+Vector3(dx-.1,.89+absf(dx),0),Vector3(.27,.15,.12),"789e70")

func pupil_texture(variant: int) -> ImageTexture:
	var img:=Image.create(16,32,false,Image.FORMAT_RGBA8); img.fill(Color.TRANSPARENT)
	var shirt: String=["ba7755","7d9f83","b99b58","9291a6","718ea3"][variant]
	var shapes: Array=[ [4,25,3,7,"344e52"],[10,25,3,7,"344e52"],[3,13,11,13,shirt],[1,14,3,11,shirt],[13,14,3,11,shirt],[5,5,8,9,"e4b58c"],[4,3,10,4,"67513e"],[5,7,1,3,"67513e"],[7,8,1,1,"304841"],[11,8,1,1,"304841"],[8,12,3,1,"bc8767"],[4,19,10,2,"e8d5b0"] ]
	for s in shapes:
		for y in range(int(s[1]),int(s[1]+s[3])):
			for x in range(int(s[0]),int(s[0]+s[2])): img.set_pixel(x,y,Color(s[4]))
	return ImageTexture.create_from_image(img)

func update_room(count: int, hot: bool, delta: float) -> void:
	t+=delta
	for i in range(people.size()):
		people[i].visible=i<count
		people[i].position.y=.86+sin(t*1.7+i)*.014
	for i in range(steam.size()):
		steam[i].visible=hot
		steam[i].position.y=1.5+fmod(t*.22+i*.09,.45)
