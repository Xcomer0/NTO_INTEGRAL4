extends RefCounted
## Pure deterministic rules. UI, QA and recorded demonstrations use this model.
var data: Dictionary
var stock: Array = []
var prices: Array = []
var stations: Array = []
var batches: Array = []
var pending: Array = []
var customers: Array = []
var cash := 1000
var revenue := 0
var purchases := 0
var cogs := 0
var waste := 0
var premiums := 0
var investment := 0
var fixed := 300
var served := 0
var missed := 0
var happiness := 0.0
var wave := 0
var phase := "plan"
var clock := 0.0
var total_time := 0.0
var next_customer := 0
var serial := 0
var upgrade := ""
var emergency_used := 0
var reserve_used := false
var message := "Нина: Начнём с каши и булочек. Молоко нужно обоим блюдам."
var history: Array = []
var initial_assets := 0
var _guest_total := 0

func _init(scenario: Dictionary) -> void:
	data = scenario.duplicate(true)
	for shift_wave in data.waves:
		_guest_total += shift_wave.orders.size()
	reset()

func total_guests() -> int:
	return _guest_total

func is_last_wave() -> bool:
	return wave == data.waves.size()-1

func reset() -> void:
	stock.clear(); prices.clear(); stations = [{},{}]; batches.clear(); pending.clear(); customers.clear()
	cash=1000; revenue=0; purchases=0; cogs=0; waste=0; premiums=0; investment=0
	served=0; missed=0; happiness=0.0; wave=0; phase="plan"; clock=0.0; total_time=0.0; next_customer=0; serial=0
	upgrade=""; emergency_used=0; reserve_used=false; history.clear(); initial_assets=0
	for ing in data.ingredients:
		stock.append(int(ing.stock)); initial_assets += int(ing.stock)*int(ing.cost)
	for dish in data.dishes: prices.append(int(dish.price))
	message="Нина: Начнём с каши и булочек. Молоко нужно обоим блюдам."

func say(s: String) -> bool:
	message=s
	return false

func buy(i: int, urgent: bool) -> bool:
	if phase=="end": return false
	if i<0 or i>=stock.size(): return say("Такого продукта нет на складе.")
	if urgent and emergency_used>=6: return say("Лимит срочной доставки: 6 упаковок за смену. Плановая доступна между переменами.")
	if not urgent and phase!="plan": return say("Плановый заказ оформляется между переменами.")
	var cost: int = int(data.ingredients[i].cost)*5
	var extra: int = int(ceil(cost*0.4)) if urgent else 0
	if cash<cost+extra: return say("Нужно %d ₽, в кассе %d ₽. Сохраните деньги или используйте резерв." % [cost+extra,cash])
	cash-=cost+extra; purchases+=cost; premiums+=extra
	if urgent:
		stock[i]+=5; emergency_used+=1
		message="Срочная поставка: +5 %s. Доплата %d ₽." % [data.ingredients[i].name,extra]
	else:
		pending.append({"i":i,"n":5})
		message="Заказано +5 %s за %d ₽. Привезут при открытии перемены." % [data.ingredients[i].name,cost]
	return true

func change_price(i: int, amount: int) -> bool:
	if phase!="plan": return say("Цены фиксируются до звонка. Изменить можно в планировании.")
	if i<0 or i>=prices.size(): return say("Такого блюда нет в меню.")
	prices[i]=clampi(prices[i]+amount,int(data.dishes[i].min),int(data.dishes[i].max))
	message="%s: %d ₽. Прогноз пересчитан по бюджетам гостей." % [data.dishes[i].name,prices[i]]
	return true

func cook(i: int, n: int) -> bool:
	if phase=="end": return false
	if i<0 or i>=prices.size(): return say("Такого блюда нет в меню.")
	var d: Dictionary=data.dishes[i]
	var cap: int=8 if upgrade=="bulk" else 5
	if n<1 or n>cap: return say("Размер партии: от 1 до %d порций." % cap)
	if not stations[int(d.station)].is_empty(): return say("Эта станция занята. Печь работает параллельно с горячей кухней.")
	for k in d.recipe:
		if stock[int(k)]<n: return say("Не хватает %s: нужно %d, на складе %d." % [data.ingredients[int(k)].name,n,stock[int(k)]])
	for k in d.recipe: stock[int(k)]-=n
	var duration: float=float(d.time)*(1.2 if n>5 else 1.0)
	stations[int(d.station)]={"dish":i,"n":n,"left":duration,"duration":duration}
	message="%s: готовится %d порц. Продукты уже учтены." % [d.name,n]
	return true

func portions(i: int) -> int:
	var n:=0
	for b in batches:
		if int(b.dish)==i: n+=int(b.n)
	return n

func eligible(c: Dictionary, i: int) -> bool:
	return i>=0 and i<prices.size() and (i==int(c.pref) or i==int(c.alt)) and prices[i]<=int(c.budget)

func preferred(c: Dictionary, available_only: bool=false) -> int:
	var best:=-1
	var score:=-100
	for i in range(prices.size()):
		if not eligible(c,i) or (available_only and portions(i)==0): continue
		var s: int=3 if i==int(c.pref) else 1
		if prices[i]<=int(data.dishes[i].price)-5: s+=1
		if prices[i]>=int(data.dishes[i].price)+10: s-=2
		if s>score or (s==score and (best<0 or prices[i]<prices[best])): best=i; score=s
	return best

func forecast() -> Array:
	var out: Array=[]
	out.resize(prices.size())
	out.fill(0)
	for order in data.waves[wave].orders:
		var i:=preferred({"pref":order[0],"alt":order[1],"budget":order[2]})
		if i>=0: out[i]+=1
	return out

func serve(id: int, dish: int) -> bool:
	if phase!="service": return say("Раздача откроется после звонка.")
	if dish<0 or dish>=prices.size(): return say("Такого блюда нет в меню.")
	var index:=-1
	for j in range(customers.size()):
		if int(customers[j].id)==id: index=j; break
	if index<0: return false
	var c: Dictionary=customers[index]
	if not eligible(c,dish): return say("%s: подходит %s или %s до %d ₽." % [c.name,data.dishes[int(c.pref)].name,data.dishes[int(c.alt)].name,c.budget])
	if portions(dish)==0: return say("%s закончилась. Приготовьте партию или предложите доступную замену." % data.dishes[dish].name)
	for b in batches:
		if int(b.dish)==dish and int(b.n)>0: b.n-=1; break
	var happy: float=100.0 if dish==int(c.pref) else 85.0
	if float(c.wait)>50: happy-=15
	cash+=prices[dish]; revenue+=prices[dish]; cogs+=int(data.dishes[dish].cost); served+=1; happiness+=happy
	customers.remove_at(index)
	message="%s: %s! +%d ₽, довольство %d%%." % [c.name,"Спасибо, любимое" if dish==int(c.pref) else "Спасибо за замену",prices[dish],int(happy)]
	return true

func open_wave() -> bool:
	if phase!="plan": return false
	for order in pending: stock[int(order.i)]+=int(order.n)
	pending.clear(); phase="service"; clock=0; next_customer=0
	message="Звонок! %s. Читайте бюджет и допустимую замену на карточках." % data.waves[wave].name
	return true

func tick(delta: float) -> void:
	if phase=="end" or not is_finite(delta) or delta<=0.0: return
	total_time+=delta
	for s in range(stations.size()):
		if stations[s].is_empty(): continue
		stations[s].left-=delta
		if stations[s].left<=0:
			batches.append({"dish":stations[s].dish,"n":stations[s].n,"age":0})
			message="Готово: %d порц. %s." % [stations[s].n,data.dishes[int(stations[s].dish)].name]
			stations[s]={}
	if phase!="service": return
	clock+=delta
	var w: Dictionary=data.waves[wave]
	var interval: float=(float(w.duration)-35.0)/maxi(1,w.orders.size()-1)
	while next_customer<w.orders.size() and clock>=5.0+next_customer*interval:
		var o: Array=w.orders[next_customer]
		serial+=1
		var names: Array=["Аня","Миша","Лена","Тимур","Соня","Лёша","Варя","Саша","Ира","Даня"]
		customers.append({"id":serial,"pref":int(o[0]),"alt":int(o[1]),"budget":int(o[2]),"wait":0.0,"name":names[(serial-1)%10]})
		next_customer+=1
	for j in range(customers.size()-1,-1,-1):
		customers[j].wait+=delta
		if customers[j].wait>=90:
			message="%s ушёл на урок. В следующий раз приготовьте партию заранее." % customers[j].name
			missed+=1; customers.remove_at(j)
	if clock>=float(w.duration): close_wave()

func close_wave() -> void:
	if phase!="service": return
	missed+=customers.size(); customers.clear()
	for b in batches:
		b.age+=1
		if int(b.age)>=(2 if upgrade=="warmer" else 1):
			waste+=int(b.n)*int(data.dishes[int(b.dish)].cost); b.n=0
	var last := is_last_wave()
	if last:
		for s in stations:
			if not s.is_empty(): waste+=int(s.n)*int(data.dishes[int(s.dish)].cost)
		stations=[{},{}]
		for b in batches:
			waste+=int(b.n)*int(data.dishes[int(b.dish)].cost); b.n=0
		cash-=fixed; phase="end"
		message="Нина: Спасибо за смену. Отчёт поможет сделать следующую ещё лучше."
	history.append({"wave":wave,"served":served,"revenue":revenue,"waste":waste,"profit":profit()})
	if not last:
		wave+=1; phase="plan"; clock=0
		message="Нина: Посмотрите итоги. Можно вложить выручку в оборудование."
		if is_last_wave():
			var orders: Array=data.waves[wave].orders
			var min_budget:=int(orders[0][2])
			var max_budget:=min_budget
			for order in orders:
				min_budget=mini(min_budget,int(order[2]))
				max_budget=maxi(max_budget,int(order[2]))
			message="Директор: Следующая группа — %s. Гостей: %d. Бюджеты: %d–%d ₽." % [data.waves[wave].name,orders.size(),min_budget,max_budget]
		elif wave>1:
			message="Нина: Проверьте прогноз перед новой переменой."

func invest(kind: String) -> bool:
	if phase!="plan" or wave<1 or not upgrade.is_empty(): return say("Одно улучшение доступно после первой перемены.")
	if kind!="warmer" and kind!="bulk": return say("Такого улучшения нет.")
	var cost: int=120 if kind=="warmer" else 100
	if cash<cost: return say("На улучшение нужно %d ₽." % cost)
	upgrade=kind; cash-=cost; investment+=cost
	message="Марми́т: готовые порции сохранятся на следующую перемену." if kind=="warmer" else "Большая посуда: партии до 8 порций. Крупная партия готовится на 20% дольше."
	return true

func reserve() -> bool:
	if reserve_used or not is_last_wave() or phase!="plan": return say("Школьный резерв доступен один раз перед последней переменой.")
	reserve_used=true; stock[0]+=5; stock[1]+=5
	initial_assets+=5*(int(data.ingredients[0].cost)+int(data.ingredients[1].cost))
	message="Резерв школы: %s +5, %s +5. Вклад школы учтён отдельно от прибыли." % [data.ingredients[0].name,data.ingredients[1].name]
	return true

func profit() -> int:
	return revenue-cogs-waste-fixed-premiums-investment

func rating() -> int:
	var service: float=30.0*served/total_guests()
	var joy: float=25.0*(happiness/(served*100.0)) if served>0 else 0.0
	var economy: float=25.0*clampf(float(profit()+200)/500.0,0,1)
	var care: float=20.0*clampf(1.0-float(waste)/300.0,0,1)
	return clampi(roundi(service+joy+economy+care),0,100)

func assets() -> int:
	var value:=0
	for i in range(stock.size()): value+=stock[i]*int(data.ingredients[i].cost)
	for b in batches: value+=int(b.n)*int(data.dishes[int(b.dish)].cost)
	for s in stations:
		if not s.is_empty(): value+=int(s.n)*int(data.dishes[int(s.dish)].cost)
	for p in pending: value+=int(p.n)*int(data.ingredients[int(p.i)].cost)
	return value
