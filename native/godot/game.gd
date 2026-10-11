extends Node2D
## Real-time armour, collision and ballistics; stdout belongs to GameKit.
## SPDX-License-Identifier: GPL-3.0-or-later

const WIDTH := 21
const HEIGHT := 13
const CELL := 32.0
const DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const NAMES := ["n", "e", "s", "w"]
const PLAYER_START := Vector2i(3, 10)
const ENEMY_STARTS := [Vector2i(8, 10), Vector2i(17, 2), Vector2i(10, 2)]
const MAX_HEALTH := 100
const DAMAGE := 20
const PLAYER_SPEED := 5.5
const ENEMY_SPEED := 2.3
const SHELL_SPEED := 16.0
const PLAYER_RELOAD := 0.28
const ENEMY_RELOAD := 1.6

class Tank extends CharacterBody2D:
	var identity := ""
	var hostile := false
	var facing := 1
	var cooldown := 0.0
	var route: Array[Vector2i] = []

class Shell extends CharacterBody2D:
	var hostile := false
	var direction := Vector2.RIGHT
	var life := 2.0

var navigation := AStarGrid2D.new()
var terrain: Array[String] = []
var player: Tank
var enemies: Array[Tank] = []
var shells: Array[Shell] = []
var effects: Array = []
var events: Array = []
var health := MAX_HEALTH
var shots := 0
var kills := 0
var seconds := 0.0
var ai_clock := 0.0
var event_id := 0
var paused := true
var won := false
var lost := false

func _ready() -> void:
	navigation.region = Rect2i(0, 0, WIDTH, HEIGHT)
	navigation.cell_size = Vector2.ONE
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	navigation.update()
	for y in HEIGHT:
		var row := ""
		for x in WIDTH:
			var solid := x == 0 or y == 0 or x == WIDTH - 1 or y == HEIGHT - 1
			solid = solid or (x == 7 and y not in [2, 6, 10]) or (x == 13 and y not in [2, 6, 10])
			solid = solid or (y == 6 and x not in [3, 7, 10, 13, 17])
			row += "#" if solid else "."
			if solid:
				navigation.set_point_solid(Vector2i(x, y), true)
				var wall := StaticBody2D.new()
				wall.position = _centre(Vector2i(x, y))
				wall.collision_layer = 1
				wall.collision_mask = 0
				var shape := CollisionShape2D.new()
				var rectangle := RectangleShape2D.new()
				rectangle.size = Vector2(CELL, CELL)
				shape.shape = rectangle
				wall.add_child(shape)
				add_child(wall)
		terrain.append(row)
	_reset()

func _centre(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL

func _cell(unit: Node2D) -> Vector2i:
	return Vector2i(floor(unit.position.x / CELL), floor(unit.position.y / CELL))

func _tank(identity: String, cell: Vector2i, hostile: bool) -> Tank:
	var tank := Tank.new()
	tank.identity = identity
	tank.hostile = hostile
	tank.position = _centre(cell)
	tank.facing = 3 if hostile else 1
	tank.cooldown = 1.6 if hostile else 0.0
	tank.collision_layer = 4 if hostile else 2
	tank.collision_mask = 7
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2.ONE * (CELL * 0.60)
	shape.shape = rectangle
	tank.add_child(shape)
	add_child(tank)
	return tank

func _reset() -> void:
	for shell in shells:
		shell.free()
	shells.clear()
	for enemy in enemies:
		enemy.free()
	enemies.clear()
	if is_instance_valid(player):
		player.free()
	player = _tank("player", PLAYER_START, false)
	for index in ENEMY_STARTS.size():
		enemies.append(_tank("enemy-%d" % (index + 1), ENEMY_STARTS[index], true))
	health = MAX_HEALTH
	shots = 0
	kills = 0
	seconds = 0
	ai_clock = 0
	paused = true
	won = false
	lost = false
	effects.clear()
	events.clear()
	event_id = 0
	_event("整装待发", "按 P 开始；WASD 驾驶，空格开火。", "info")

func _event(title: String, detail: String, kind: String) -> void:
	event_id += 1
	events.push_front({"id": event_id, "title": title, "detail": detail, "kind": kind, "time": int(seconds)})
	if events.size() > 6:
		events.pop_back()

func _passable(cell: Vector2i) -> bool:
	return navigation.is_in_boundsv(cell) and not navigation.is_point_solid(cell)

func _route(tank: Tank, target: Vector2i) -> bool:
	if not _passable(target):
		return false
	# Finish the current physics segment before changing route. Replanning
	# mid-cell must not cut diagonally through the corner of a bulkhead.
	var anchor: Vector2i = tank.route[0] if not tank.route.is_empty() else _cell(tank)
	var path: Array[Vector2i] = navigation.get_id_path(anchor, target)
	if path.is_empty():
		return false
	if tank.position.distance_to(_centre(anchor)) < 0.05:
		path.pop_front()
	tank.route = path
	return true

func _facing(direction: Vector2) -> int:
	if absf(direction.x) > absf(direction.y):
		return 1 if direction.x > 0 else 3
	return 2 if direction.y > 0 else 0

func _advance(tank: Tank, delta: float) -> void:
	if tank.route.is_empty():
		return
	var target := _centre(tank.route[0])
	var displacement := target - tank.position
	var distance := displacement.length()
	if distance < 0.02:
		tank.route.pop_front()
		return
	tank.facing = _facing(displacement)
	var speed := (ENEMY_SPEED if tank.hostile else PLAYER_SPEED) * CELL
	var motion := displacement.normalized() * minf(distance, speed * delta)
	# Godot is the authority for swept tank/wall and tank/tank collision.
	var collision := tank.move_and_collide(motion)
	if collision:
		tank.route.clear()
	elif distance <= speed * delta:
		tank.route.pop_front()

func _clear_shot(enemy: Tank) -> bool:
	var distance := player.position - enemy.position
	if minf(absf(distance.x), absf(distance.y)) > CELL * 0.18:
		return false
	var ray := PhysicsRayQueryParameters2D.create(enemy.position, player.position, 1)
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()

func _shoot(tank: Tank) -> void:
	var shell := Shell.new()
	shell.hostile = tank.hostile
	shell.direction = Vector2(DIRECTIONS[tank.facing])
	shell.position = tank.position
	shell.collision_layer = 0
	# No friendly fire; walls and the opposing armour receive swept hits.
	shell.collision_mask = 3 if tank.hostile else 5
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = CELL * 0.06
	shape.shape = circle
	shell.add_child(shape)
	add_child(shell)
	shells.append(shell)
	tank.cooldown = ENEMY_RELOAD if tank.hostile else PLAYER_RELOAD
	if not tank.hostile:
		shots += 1

func _impact(shell: Shell, collision: KinematicCollision2D) -> void:
	var collider = collision.get_collider()
	effects.append({"x": shell.position.x / CELL, "y": shell.position.y / CELL, "life": 0.22})
	if collider is Tank:
		if collider.hostile:
			enemies.erase(collider)
			collider.free()
			kills += 1
			_event("命中摧毁", "已击毁 %d / 3 辆敌车。" % kills, "success")
			if enemies.is_empty():
				won = true
				_event("战区肃清", "全部敌车已被摧毁。", "success")
		else:
			health = maxi(0, health - DAMAGE)
			_event("装甲受损", "敌方炮弹造成 %d 点损伤。" % DAMAGE, "danger")
			if health == 0:
				lost = true
				_event("战车损毁", "按 N 重新出击。", "danger")

func _physics_process(delta: float) -> void:
	# This runs on Godot's fixed 60 Hz physics clock, independently of orders.
	if paused or won or lost:
		return
	seconds += delta
	player.cooldown = maxf(0, player.cooldown - delta)
	_advance(player, delta)
	for index in range(effects.size() - 1, -1, -1):
		effects[index].life -= delta
		if effects[index].life <= 0:
			effects.remove_at(index)
	ai_clock -= delta
	for enemy in enemies:
		enemy.cooldown = maxf(0, enemy.cooldown - delta)
		if _clear_shot(enemy):
			enemy.route.clear()
			enemy.facing = _facing(player.position - enemy.position)
			if enemy.cooldown <= 0:
				_shoot(enemy)
		elif ai_clock <= 0:
			_route(enemy, _cell(player))
		_advance(enemy, delta)
	if ai_clock <= 0:
		ai_clock = 0.35
	for index in range(shells.size() - 1, -1, -1):
		var shell: Shell = shells[index]
		shell.life -= delta
		var collision := shell.move_and_collide(shell.direction * SHELL_SPEED * CELL * delta)
		if collision:
			_impact(shell, collision)
		if collision or shell.life <= 0:
			shells.remove_at(index)
			shell.free()
		if won or lost:
			player.route.clear()
			break

func capabilities() -> Array:
	return ["move", "navigate", "aim", "fire", "stop", "pause", "restart", "save", "load"]

func _integer(value) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value == floor(float(value))

func command(operation: String, args: Dictionary) -> String:
	if operation == "restart":
		_reset()
		return ""
	if operation in ["save", "load"]:
		if not args.get("path") is String or args.path.is_empty():
			return "请指定存档路径"
		return _save(args.path) if operation == "save" else _load_snapshot(args.path)
	if won or lost:
		return "战斗已结束，请开始新局"
	match operation:
		"pause":
			paused = not paused
			player.route.clear()
			return ""
		"stop":
			player.route.clear()
			return ""
		"aim":
			if not args.get("direction") in NAMES:
				return "方向必须是 n、e、s 或 w"
			player.route.clear()
			player.facing = NAMES.find(args.direction)
			return ""
		"move", "navigate":
			if paused:
				return "请先开始或继续战斗"
			if not _integer(args.get("x")) or not _integer(args.get("y")):
				return "坐标必须为整数"
			var point := Vector2i(int(args.x), int(args.y))
			if operation == "move":
				if absi(point.x) + absi(point.y) != 1:
					return "每次只能沿一个方向驾驶"
				# Coalesce key repeat to at most the current and one next cell.
				# Leaving the window cannot leave a long driving queue behind.
				point += player.route[0] if not player.route.is_empty() else _cell(player)
			if not _passable(point):
				return "掩体阻挡，无法驶入"
			if not _route(player, point):
				return "目的地不可达"
			return ""
		"fire":
			if paused:
				return "请先开始或继续战斗"
			if player.cooldown > 0:
				return "主炮正在装填"
			_shoot(player)
			return ""
		_:
			return "不支持的操作：" + operation

func _entity(tank: Tank) -> Dictionary:
	return {"id": tank.identity, "name": "我方战车" if not tank.hostile else "敌方战车",
		"kind": "enemy" if tank.hostile else "player", "facing": NAMES[tank.facing],
		"x": _cell(tank).x, "y": _cell(tank).y,
		"px": snappedf(tank.position.x / CELL, 0.0625), "py": snappedf(tank.position.y / CELL, 0.0625)}

func observe() -> Dictionary:
	var entities: Array = [_entity(player)]
	for enemy in enemies:
		entities.append(_entity(enemy))
	var flying: Array = []
	for shell in shells:
		flying.append({"px": snappedf(shell.position.x / CELL, 0.0625), "py": snappedf(shell.position.y / CELL, 0.0625),
			"x": _cell(shell).x, "y": _cell(shell).y, "owner": "enemy" if shell.hostile else "player"})
	var flashes: Array = []
	for effect in effects:
		flashes.append({"px": effect.x, "py": effect.y})
	return {"schema": "tanks/1", "title": "Iron Tide",
		"world": {"width": WIDTH, "height": HEIGHT, "terrain": terrain, "entities": entities, "shells": flying, "effects": flashes},
		"player": {"health": health, "facing": NAMES[player.facing], "shots": shots, "kills": kills,
			"score": kills * 100, "seconds": int(seconds), "paused": paused, "won": won, "lost": lost,
			"enemies": enemies.size(), "can_fire": not paused and not won and not lost and player.cooldown <= 0,
			"moving": not player.route.is_empty()}, "events": events}

func _saved_tank(tank: Tank) -> Dictionary:
	return {"id": tank.identity, "x": tank.position.x / CELL, "y": tank.position.y / CELL,
		"facing": tank.facing, "cooldown": tank.cooldown}

func _save(path: String) -> String:
	var raiders: Array = []
	for enemy in enemies:
		raiders.append(_saved_tank(enemy))
	var data := {"format": "iron-tide/1", "player": _saved_tank(player), "enemies": raiders,
		"health": health, "shots": shots, "kills": kills, "seconds": seconds, "won": won, "lost": lost}
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return "无法写入存档：" + error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(data))
	file.close()
	var result := DirAccess.rename_absolute(path + ".tmp", path)
	return "" if result == OK else "无法发布存档：" + error_string(result)

func _valid_tank(data, identity: String) -> bool:
	if not data is Dictionary or data.get("id") != identity:
		return false
	for key in ["x", "y", "cooldown"]:
		if not data.get(key) is float or not is_finite(data[key]):
			return false
	for y in range(int(floor(data.y - 0.299)), int(floor(data.y + 0.299)) + 1):
		for x in range(int(floor(data.x - 0.299)), int(floor(data.x + 0.299)) + 1):
			if not _passable(Vector2i(x, y)):
				return false
	return _integer(data.get("facing")) and data.facing >= 0 and data.facing < 4 and data.cooldown >= 0 and data.cooldown <= ENEMY_RELOAD

func _load_snapshot(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 1024 * 1024:
		return "无法读取存档，或文件超过 1 MiB"
	var decoder := JSON.new()
	if decoder.parse(file.get_as_text()) != OK:
		return "无效的存档 JSON"
	var data = decoder.data
	if not data is Dictionary or data.get("format") != "iron-tide/1" or not _valid_tank(data.get("player"), "player"):
		return "不兼容或无效的存档"
	for key in ["health", "shots", "kills"]:
		if not _integer(data.get(key)) or data[key] < 0:
			return "存档计数无效"
	if data.health > MAX_HEALTH or data.kills > 3 or not data.get("seconds") is float or not is_finite(data.seconds) or data.seconds < 0:
		return "存档进度无效"
	if not data.get("enemies") is Array or data.enemies.size() != 3 - data.kills:
		return "存档敌车数量无效"
	if not data.get("won") is bool or not data.get("lost") is bool or data.won != (data.kills == 3) or data.lost != (data.health == 0) or (data.won and data.lost):
		return "存档胜负状态无效"
	var ids: Array = []
	var occupied: Array = [Vector2(data.player.x, data.player.y)]
	for enemy in data.enemies:
		if not enemy is Dictionary or not enemy.get("id") in ["enemy-1", "enemy-2", "enemy-3"] or enemy.id in ids or not _valid_tank(enemy, enemy.id):
			return "存档敌车无效"
		var position := Vector2(enemy.x, enemy.y)
		for other in occupied:
			if absf(position.x - other.x) < 0.59 and absf(position.y - other.y) < 0.59:
				return "存档车辆位置重叠"
		occupied.append(position)
		ids.append(enemy.id)
	_reset()
	player.position = Vector2(data.player.x, data.player.y) * CELL
	player.facing = int(data.player.facing)
	player.cooldown = data.player.cooldown
	for enemy in enemies:
		enemy.free()
	enemies.clear()
	for enemy in data.enemies:
		var unit := _tank(enemy.id, Vector2i.ZERO, true)
		unit.position = Vector2(enemy.x, enemy.y) * CELL
		unit.facing = int(enemy.facing)
		unit.cooldown = enemy.cooldown
		enemies.append(unit)
	health = int(data.health)
	shots = int(data.shots)
	kills = int(data.kills)
	seconds = data.seconds
	won = data.won
	lost = data.lost
	_event("已读取存档", "战斗保持暂停，路线和在途炮弹已清空。", "info")
	return ""
