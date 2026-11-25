extends SceneTree
const Rules = preload("res://model.gd")
const GameConfig = preload("res://config.gd")
var failures: Array=[]
var checks: Array=[]

func check(condition: bool, title: String) -> void:
	checks.append({"test":title,"pass":condition})
	if not condition: failures.append(title)

func _initialize() -> void:
	var loaded := GameConfig.read(GameConfig.DEFAULT_PATH)
	if not loaded.error.is_empty():
		push_error(loaded.error)
		quit(1)
		return
	var m=Rules.new(loaded.data)
	check(m.stock.size()==6 and m.prices.size()==4,"Six ingredients and four dishes")
	var initial=m.stock.duplicate()
	m.stock[1]=0
	check(not m.cook(0,3) and m.stock[0]==initial[0],"Missing ingredient rejects entire transaction")
	m.reset(); m.cook(0,3)
	check(m.stock[0]==9 and m.stock[1]==9,"Recipe reserves exact ingredients")
	check(not m.cook(1,2),"Hot station serializes cooking")
	check(m.cook(3,2),"Oven runs in parallel")
	m.tick(25)
	check(m.portions(0)==3 and m.portions(3)==2,"Cook timers produce exact portions")
	m.open_wave(); m.tick(6)
	var id: int=m.customers[0].id
	var money: int=m.cash
	check(m.serve(id,0) and m.cash==money+45 and m.portions(0)==2,"Sale consumes one portion and grants one price")
	check(not m.serve(id,0) and m.cash==money+45,"Repeated callback cannot duplicate sale")
	m.reset(); m.cash=1
	check(not m.buy(1,true) and m.cash==1,"Insufficient cash rejects supply")
	m.reset(); m.buy(0,false)
	check(m.stock[0]==12 and m.pending.size()==1,"Planned purchase stays in transit")
	m.open_wave()
	check(m.stock[0]==17 and m.pending.is_empty(),"Planned delivery at bell")
	m.reset(); var before=m.forecast()
	m.change_price(0,10); m.change_price(3,10)
	check(m.forecast()!=before,"Prices change affordable demand")
	m.open_wave(); var price: int=m.prices[0]
	check(not m.change_price(0,-5) and m.prices[0]==price,"Service locks prices")
	m.reset(); m.cook(0,2); m.tick(20); m.open_wave(); m.tick(181)
	check(m.waste==44 and m.portions(0)==0,"Unsold food written off once")
	check(m.wave==1 and m.phase=="plan","Wave returns to planning")
	check(m.invest("warmer") and not m.invest("bulk"),"Exclusive equipment choice")
	m.cook(3,2); m.tick(20); m.open_wave(); m.tick(201)
	check(m.portions(3)==2 and m.wave==2,"Warmer preserves food through one transition")
	check(m.reserve() and not m.reserve(),"School reserve is available once")
	check(m.data.waves[2].orders.size()==10 and m.data.waves[2].orders[0][2]==40,"Event changes group and budgets")
	m.open_wave(); m.tick(221)
	check(m.phase=="end" and m.served+m.missed==24,"Complete shift accounts for all 24 visitors")
	check(m.cash+m.assets()-1000-m.initial_assets==m.profit(),"Cash plus assets reconciles profit including grants")
	check(m.rating()>=0 and m.rating()<=100,"Rating bounded for failed shift")
	m.reset()
	check(m.wave==0 and m.waste==0 and m.cash==1000 and m.upgrade=="" and m.prices[0]==45,"Restart restores all run state")
	# Full deterministic strategy playthrough with decisions at each wave.
	var elapsed:=0.0
	while m.phase!="end" and elapsed<1200:
		if m.phase=="plan":
			if m.wave==1: m.invest("warmer")
			if m.wave==2:
				m.reserve()
				for i in range(4):
					while m.prices[i]>int(m.data.dishes[i].min): m.change_price(i,-5)
			m.open_wave()
		for c in m.customers.duplicate():
			var d: int=m.preferred(c,true)
			if d>=0: m.serve(int(c.id),d)
		for c in m.customers:
			var i: int=m.preferred(c)
			if i>=0 and m.portions(i)==0 and m.stations[int(m.data.dishes[i].station)].is_empty(): m.cook(i,1)
		m.tick(1); elapsed+=1
	check(m.phase=="end" and elapsed>=600,"Full service lasts at least 600 active seconds")
	check(m.served>=20,"Adaptive strategy serves at least 20 of 24")
	check(m.profit()>0,"Demand-driven strategy can end with positive profit")
	check(m.cash+m.assets()-1000-m.initial_assets==m.profit(),"Full run economy reconciles without double writeoff")
	check_scenarios(loaded.data)
	var result={"engine":Engine.get_version_info().string,"checks":checks,"passed":checks.size()-failures.size(),"failed":failures,"playthrough":{"seconds":elapsed,"served":m.served,"missed":m.missed,"profit":m.profit(),"rating":m.rating()}}
	var f=FileAccess.open("res://../tests/results.json",FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result,"  "))
	quit(0 if failures.is_empty() else 1)

func check_scenarios(standard: Dictionary) -> void:
	var boundary := standard.duplicate(true)
	boundary.ingredients[1].stock=0
	check(GameConfig.validate(boundary).is_empty(),"Zero starting milk is a valid scenario")
	var m := Rules.new(boundary)
	var before := m.stock.duplicate()
	check(not m.cook(0,3) and m.stock==before and m.cash==1000 and m.stations[0].is_empty(),"Boundary scenario rejects a batch without partial writes")
	check(m.buy(1,false) and m.open_wave() and m.cook(0,3),"Boundary scenario recovers after planned delivery")
	m.tick(14)
	check(m.portions(0)==3 and m.stock[1]==2,"Ordered milk produces the intended three portions")
	var expanded := standard.duplicate(true)
	expanded.waves[0].orders.append([3,0,99])
	check(GameConfig.validate(expanded).is_empty(),"An added order needs no other configuration changes")
	m=Rules.new(expanded)
	check(m.total_guests()==25 and m.forecast()==[2,1,2,3],"Additional order increases shift total and bun forecast")
	m.cook(3,1)
	m.tick(16)
	m.open_wave()
	for second in range(150):
		m.tick(1)
	var last: Dictionary=m.customers.back() if not m.customers.is_empty() else {}
	check(last.get("id")==8 and last.get("budget")==99 and m.serve(last.id,3) and m.cash==1040 and m.served==1,"The new guest arrives and buys the configured favorite")
	m.tick(30)
	for next_wave in range(2):
		if m.open_wave(): m.tick(float(m.data.waves[m.wave].duration))
	check(m.phase=="end" and m.served+m.missed==25 and m.history.size()==3,"Expanded shift accounts for all 25 visitors")
	m.reset()
	m.served=24; m.happiness=2400.0
	check(m.rating()==74,"Rating uses 24 of 25 for the service component")
	var invalid := standard.duplicate(true)
	invalid.waves[0].orders.append([4,0,99])
	check(not GameConfig.validate(invalid).is_empty(),"Out-of-range dish reference is rejected")
	var fallback := GameConfig.for_args(PackedStringArray(["--config=res://__absent_programming_scenario__.json"]))
	check(not fallback.custom and fallback.data==standard and not fallback.notice.is_empty(),"An unavailable external scenario falls back to the validated standard data")
	var single := standard.duplicate(true)
	single.waves=[{"name":"Тестовая перемена","duration":35,"orders":[[0,3,55]]}]
	m=Rules.new(single)
	m.open_wave(); m.tick(5)
	check(m.customers.size()==1 and m.total_guests()==1,"One-order wave schedules the first visitor without division by zero")
	m.tick(30)
	check(m.phase=="end" and m.missed==1,"One-wave shift closes after its configured last wave")
