extends RefCounted
## Battlefield composition into horizontal PNG strips for Emacs.
## SPDX-License-Identifier: GPL-3.0-or-later
##
## art.gd describes every sprite as SVG. This file rasterizes the art at the
## display's device pixels per block, keeps a lit terrain layer and a forest
## canopy layer, and composes each frame from an ordered list of draw
## operations. A frame is divided into strips one Emacs text line tall; only
## strips whose operations or terrain changed since the previous frame are
## repainted and written, each as a new numbered file version, so Emacs
## decodes only the lines that changed. PNG encoding dominates the cost of a
## frame, so changed strips are encoded in parallel on the worker pool.

const Art := preload("res://art.gd")
const Battle := preload("res://battle.gd")
const EMPTY := 0
const BRICK := 1
const STEEL := 2
const WATER := 3
const FOREST := 4
const ICE := 5
## File versions kept per strip; older ones are deleted. Emacs reads a strip
## file at its next redisplay, which may come several frames later.
const KEEP := 16
const CLEAR := Color(0, 0, 0, 0)

var theme := "dark"
var palette: Dictionary = Art.PALETTES.dark
var block := 16
var line := 16
var unit := 2.0
var sub := 8
var images := {}
var cw := 0
var ch := 0
var width := 0
var height := 0
var strips := 0
var shown := PackedByteArray()
var terrain: Image
var forest: Image
var frame: Image
var shade: Image
var grid: Image
var lighting := {}
var ops: Array = []
var signatures := PackedStringArray()
var dirty := PackedByteArray()
var serials := PackedInt32Array()
var versions: Array = []
var forest_runs: Array = []
var directory := ""
var published := 0
var batch := PackedInt32Array()
var batch_id := 0
var failures := PackedStringArray()
var mutex := Mutex.new()

## Use palette NAME, DEVICE-BLOCK pixels per map block (a multiple of 4) and
## strips DEVICE-LINE pixels tall. Every layer is rebuilt on the next frame.
func configure(name: String, device_block: int, device_line: int) -> void:
	theme = name
	palette = Art.PALETTES[name]
	block = device_block
	line = device_line
	unit = block / 8.0
	sub = block / 2
	images.clear()
	lighting.clear()
	shade = null
	grid = null
	cw = 0
	ch = 0
	published = 0

# ---------------------------------------------------------------- art cache

func _raster(key: String, source: String) -> Image:
	var image := Image.new()
	var error := image.load_svg_from_string(source, unit)
	if error != OK:
		push_error("Iron Tide: cannot rasterize %s: %s" % [key, error_string(error)])
		image = Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	image.convert(Image.FORMAT_RGBA8)
	images[key] = image
	return image

func _texture(kind: String) -> Image:
	var key := "texture:" + kind
	return images[key] if images.has(key) else _raster(key, Art.texture(kind, palette))

func _sprite(name: String) -> Image:
	return images[name] if images.has(name) else _raster(name, Art.sprite(name, palette))

func _tank(shape: String, look: String, step: int, facing: int) -> Image:
	var key := "tank:%s:%s:%d:%d" % [shape, look, step, facing]
	if images.has(key):
		return images[key]
	var image: Image = _raster(key, Art.tank(shape, look, step))
	match facing:
		1: image.rotate_90(CLOCKWISE)
		2: image.rotate_180()
		3: image.rotate_90(COUNTERCLOCKWISE)
	return image

func _shell(vertical: bool) -> Image:
	var key := "shell:%s" % vertical
	if images.has(key):
		return images[key]
	var image: Image = _sprite("shell").duplicate()
	if not vertical:
		image.rotate_90(CLOCKWISE)
	images[key] = image
	return image

func _label(message: String, size: float, tone: String) -> Image:
	var key := "label:%s:%s:%s" % [message, size, tone]
	return images[key] if images.has(key) else _raster(key, Art.label(message, size, tone, palette))

func _banner(message: String, size: float, tone: String) -> Image:
	var key := "banner:%s:%s:%s" % [message, size, tone]
	return images[key] if images.has(key) else _raster(key, Art.banner(message, size, tone, palette))

# ---------------------------------------------------------------- terrain

static func _band(w: int, h: int, color: Color, alphas: Array, vertical: bool, flip: bool) -> Image:
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var depth := h if vertical else w
	for y in h:
		for x in w:
			var i := y if vertical else x
			if flip:
				i = depth - 1 - i
			var alpha: float = alphas[i] if i < alphas.size() else 0.0
			image.set_pixel(x, y, Color(color, alpha))
	return image

func _lighting() -> Dictionary:
	if not lighting.is_empty():
		return lighting
	var edge := maxi(2, sub / 5)
	var strength: float = palette.shadow
	var shadows: Array = []
	for bits in 8:
		var image := Image.create_empty(sub, sub, false, Image.FORMAT_RGBA8)
		var reach := float(sub) * 0.9
		for y in sub:
			for x in sub:
				var fy := clampf(1.0 - (y + 0.5) / reach, 0.0, 1.0)
				var fx := clampf(1.0 - (x + 0.5) / reach, 0.0, 1.0)
				var alpha := 0.0
				if bits & 1:
					alpha = maxf(alpha, fy * fy)
				if bits & 2:
					alpha = maxf(alpha, fx * fx)
				if bits & 4:
					alpha = maxf(alpha, minf(fx, fy) * minf(fx, fy))
				image.set_pixel(x, y, Color(0, 0, 0, alpha * strength))
		shadows.append(image)
	lighting = {"edge": edge, "shadows": shadows,
		"top": _band(sub, edge, Color.WHITE, [0.4, 0.22, 0.08], true, false),
		"left": _band(edge, sub, Color.WHITE, [0.2, 0.08], false, false),
		"bottom": _band(sub, edge, Color.BLACK, [0.5, 0.28, 0.1], true, true),
		"right": _band(edge, sub, Color.BLACK, [0.4, 0.16], false, true),
		"rim": _band(sub, edge, Color.BLACK, [0.3, 0.12], true, true)}
	return lighting

func _at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= cw or y >= ch:
		return STEEL
	return shown[y * cw + x]

static func _solid(code: int) -> bool:
	return code == BRICK or code == STEEL

func _tile(target: Image, kind: String, corner: Vector2i) -> void:
	var tile := _texture(kind)
	target.blit_rect(tile, Rect2i(corner.x % tile.get_width(), corner.y % tile.get_height(), sub, sub), corner)

func _blend(target: Image, image: Image, at: Vector2i) -> void:
	target.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), at)

func _paint_cell(x: int, y: int) -> void:
	var code := _at(x, y)
	var corner := Vector2i(x * sub, y * sub)
	var light := _lighting()
	var edge: int = light.edge
	match code:
		WATER: _tile(terrain, "water", corner)
		ICE: _tile(terrain, "ice", corner)
		BRICK: _tile(terrain, "brick", corner)
		STEEL: _tile(terrain, "steel", corner)
		_: _tile(terrain, "ground", corner)
	if _solid(code):
		if not _solid(_at(x, y - 1)):
			_blend(terrain, light.top, corner)
		if not _solid(_at(x - 1, y)):
			_blend(terrain, light.left, corner)
		if not _solid(_at(x, y + 1)):
			_blend(terrain, light.bottom, corner + Vector2i(0, sub - edge))
		if not _solid(_at(x + 1, y)):
			_blend(terrain, light.right, corner + Vector2i(sub - edge, 0))
	else:
		var bits := 0
		if y > 0 and _solid(_at(x, y - 1)):
			bits |= 1
		if x > 0 and _solid(_at(x - 1, y)):
			bits |= 2
		if x > 0 and y > 0 and _solid(_at(x - 1, y - 1)):
			bits |= 4
		if bits:
			_blend(terrain, light.shadows[bits], corner)
	if code == FOREST:
		_tile(forest, "forest", corner)
		if y + 1 < ch and _at(x, y + 1) != FOREST:
			_blend(forest, light.rim, corner + Vector2i(0, sub - edge))
	else:
		forest.fill_rect(Rect2i(corner, Vector2i(sub, sub)), CLEAR)

## Show terrain CELLS of COLUMNS x ROWS cells, repainting only changes.
func _sync(cells: PackedByteArray, columns: int, rows: int) -> void:
	if columns == cw and rows == ch and shown.size() == cells.size():
		var changed := PackedInt32Array()
		for index in cells.size():
			if cells[index] != shown[index]:
				changed.append(index)
		if not changed.is_empty():
			_update(cells, changed)
		return
	cw = columns
	ch = rows
	width = cw * sub
	height = ch * sub
	strips = ceili(float(height) / line)
	shown = cells.duplicate()
	terrain = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	forest = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	frame = Image.create_empty(width, strips * line, false, Image.FORMAT_RGBA8)
	shade = null
	grid = null
	signatures.resize(strips)
	dirty.resize(strips)
	dirty.fill(1)
	serials.resize(strips)
	var previous := versions.size()
	versions.resize(strips)
	for index in range(previous, strips):
		versions[index] = []
	for y in ch:
		for x in cw:
			_paint_cell(x, y)
	_measure_forest()

## Record the forest canopy as horizontal runs, so frames blend only them.
func _measure_forest() -> void:
	forest_runs.clear()
	for y in ch:
		var x := 0
		while x < cw:
			if shown[y * cw + x] != FOREST:
				x += 1
				continue
			var start := x
			while x < cw and shown[y * cw + x] == FOREST:
				x += 1
			forest_runs.append(Rect2i(start * sub, y * sub, (x - start) * sub, sub))

## Apply changed terrain INDICES of CELLS and repaint their neighbourhoods.
func _update(cells: PackedByteArray, indices: PackedInt32Array) -> void:
	for index in indices:
		shown[index] = cells[index]
	var touched := {}
	for index in indices:
		var x := index % cw
		var y := index / cw
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if x + dx >= 0 and x + dx < cw and y + dy >= 0 and y + dy < ch:
					touched[(y + dy) * cw + x + dx] = true
	for index in touched:
		var y: int = index / cw
		_paint_cell(index % cw, y)
		for strip in range(y * sub / line, mini(strips - 1, ((y + 1) * sub - 1) / line) + 1):
			dirty[strip] = 1
	_measure_forest()

# ---------------------------------------------------------------- operations

## Draw IMAGE's SOURCE rectangle (all of it by default) at device pixel AT.
## KEY identifies the drawing for change detection; operations with an
## empty KEY draw terrain-derived layers, whose changes mark strips dirty
## when the terrain changes.
func _op(key: String, image: Image, at: Vector2i, source := Rect2i()) -> void:
	ops.append([key, image, Rect2i(Vector2i.ZERO, image.get_size()) if source.size == Vector2i.ZERO else source, at])

func _place(key: String, image: Image, native: Vector2) -> void:
	_op(key, image, Vector2i(roundi(native.x * unit), roundi(native.y * unit)))

func _canopy() -> void:
	for run in forest_runs:
		_op("", forest, run.position, run)

func _shade() -> Image:
	if shade == null:
		shade = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
		shade.fill(Color(palette.shade))
	return shade

func _grid() -> Image:
	if grid == null:
		grid = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
		var tone := Color(palette.grid)
		var thickness := maxi(1, block / 16)
		for x in range(0, width, block * 2):
			grid.fill_rect(Rect2i(x, 0, thickness, height), tone)
		for y in range(0, height, block * 2):
			grid.fill_rect(Rect2i(0, y, width, thickness), tone)
	return grid

## Overlay a centred banner reading MESSAGE in colour token TONE, dimming
## the board first when DIM is true.
func banner(message: String, tone: String, dim := true) -> void:
	if dim:
		_op("shade", _shade(), Vector2i.ZERO)
	var units := width / unit
	var size := 2.0 if Art.text_width(message, 2.0) + 24.0 <= units else 1.0
	var image := _banner(message, size, tone)
	_op("banner:%s:%s" % [message, tone], image, Vector2i((width - image.get_width()) / 2, (height - image.get_height()) / 2))

func _look(battle, unit_tank) -> String:
	if unit_tank.flash > 0.0:
		return "flash"
	if not unit_tank.enemy:
		return "player"
	if unit_tank.bonus and int(battle.anim * 8.0) % 2 == 0:
		return "bonus"
	if unit_tank.kind == 3:
		return "armor%d" % clampi(unit_tank.armour, 1, 4)
	return Battle.KINDS[unit_tank.kind]

func compose_battle(battle) -> void:
	if battle.terrain_reset or cw != battle.cw or ch != battle.ch:
		_sync(battle.cells, battle.cw, battle.ch)
		battle.terrain_reset = false
		battle.dirty_cells.clear()
	elif not battle.dirty_cells.is_empty():
		_update(battle.cells, battle.dirty_cells)
		battle.dirty_cells.clear()
	ops.clear()
	if battle.fortify > 0.0 and battle.fortify < 3.0 and int(battle.anim * 4.0) % 2 == 0:
		var brick := _texture("brick")
		for cell in battle.fort_cells:
			if battle.cells[cell] == STEEL:
				var corner := Vector2i(cell % cw * sub, cell / cw * sub)
				_op("fort", brick, corner, Rect2i(corner.x % brick.get_width(), corner.y % brick.get_height(), sub, sub))
	_place("base" if battle.base_alive else "ruin", _sprite("base" if battle.base_alive else "ruin"), battle.base_pos)
	var twinkle := "sparkle-%d" % (int(battle.anim * 14.0) % 4)
	for item in battle.spawns:
		_place(twinkle, _sprite(twinkle), item.pos)
	if battle.player == null and battle.respawn > 0.0 and battle.respawn < 0.8:
		_place(twinkle, _sprite(twinkle), battle.player_spawn)
	var units: Array = battle.enemies.duplicate()
	if battle.player != null:
		units.append(battle.player)
	for tank in units:
		_place("shadow", _sprite("shadow"), tank.pos + Vector2(0.2, 1.0))
	for tank in units:
		var shape: String = Battle.KINDS[tank.kind] if tank.enemy else "player%d" % clampi(battle.star, 0, 3)
		var look := _look(battle, tank)
		var step := int(tank.travel / 2.0) % 2
		_place("tank:%s:%s:%d:%d" % [shape, look, step, tank.facing], _tank(shape, look, step, tank.facing), tank.pos)
		if tank.shield > 0.0:
			var glow := "shield-%d" % (int(battle.anim * 20.0) % 2)
			_place(glow, _sprite(glow), tank.pos - Vector2.ONE)
	for shell in battle.shells:
		var vertical: bool = shell.dir % 2 == 0
		_place("shell:%s" % vertical, _shell(vertical), shell.pos - Vector2(3, 3))
	_canopy()
	if battle.bonus != null and (battle.bonus.timer > 5.0 or int(battle.anim * 6.0) % 2 == 0):
		var prize: String = "bonus-" + Battle.BONUSES[battle.bonus.kind]
		_place(prize, _sprite(prize), battle.bonus.pos)
	for effect in battle.effects:
		var progress: float = 1.0 - effect.timer / effect.total
		match effect.kind:
			"spark":
				var spark := "blast16-%d" % [0, 1, 3][mini(2, int(progress * 3.0))]
				_place(spark, _sprite(spark), effect.pos - Vector2(8, 8))
			"blast":
				var blast := "blast32-%d" % mini(3, int(progress * 4.0))
				_place(blast, _sprite(blast), effect.pos - Vector2(16, 16))
			"points":
				var label: String = effect.text
				var image := _label(label, 1.0, "text")
				_place("points:" + label, image, effect.pos - Vector2(image.get_width() / unit / 2.0, 4))

## Compose the map PARSED by stage_map.gd, with the editor's CURSOR or null.
func compose_map(parsed: Dictionary, cursor) -> void:
	ops.clear()
	if not parsed.has("terrain"):
		var columns := cw if cw > 0 else 52
		var rows := ch if ch > 0 else 52
		var blank := PackedByteArray()
		blank.resize(columns * rows)
		_sync(blank, columns, rows)
		return
	var columns: int = parsed.width * 2
	var cells := PackedByteArray()
	cells.resize(columns * parsed.height * 2)
	for by in parsed.height:
		for bx in parsed.width:
			var code: int = parsed.terrain[by * parsed.width + bx]
			for oy in 2:
				for ox in 2:
					cells[(by * 2 + oy) * columns + bx * 2 + ox] = code
	_sync(cells, columns, parsed.height * 2)
	var grouped := {}
	var groups := {"H": [] if parsed.base == null else [parsed.base], "P": [] if parsed.player == null else [parsed.player], "E": parsed.spawns}
	for mark in groups:
		for corner in groups[mark]:
			for offset in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				grouped[(corner.y + offset.y) * parsed.width + corner.x + offset.x] = true
			var at := Vector2(corner) * 8.0
			match mark:
				"H":
					_place("base", _sprite("base"), at)
				"P":
					_place("shadow", _sprite("shadow"), at + Vector2(0.2, 1.0))
					_place("tank:player0:player:0:0", _tank("player0", "player", 0, 0), at)
				"E":
					_place("shadow", _sprite("shadow"), at + Vector2(0.2, 1.0))
					_place("tank:basic:basic:0:2", _tank("basic", "basic", 0, 2), at)
					_place("sparkle-1", _sprite("sparkle-1"), at)
	for index in parsed.marks.size():
		if not parsed.marks[index].is_empty() and not grouped.has(index):
			_place("mark", _sprite("mark"), Vector2(index % parsed.width, index / parsed.width) * 8.0)
	_canopy()
	if cursor != null:
		_op("grid", _grid(), Vector2i.ZERO)
		var outline := "cursor-%d" % cursor.size
		_place(outline, _sprite(outline), Vector2(cursor.x, cursor.y) * 8.0)

# ---------------------------------------------------------------- publication

## Mark strips whose operations changed and repaint every dirty strip.
func _finish() -> void:
	var tags: Array = []
	tags.resize(strips)
	tags.fill("")
	for op in ops:
		var at: Vector2i = op[3]
		var top := maxi(at.y, 0)
		var bottom := mini(at.y + op[2].size.y, height)
		if top >= bottom or op[0].is_empty():
			continue
		var tag := "%s@%d,%d|" % [op[0], at.x, at.y]
		for strip in range(top / line, (bottom - 1) / line + 1):
			tags[strip] += tag
	for index in strips:
		var signature: String = tags[index]
		if signature != signatures[index]:
			signatures[index] = signature
			dirty[index] = 1
	var start := 0
	while start < strips:
		if not dirty[start]:
			start += 1
			continue
		var end := start
		while end < strips and dirty[end]:
			end += 1
		_paint(start * line, end * line)
		start = end

## Repaint device rows TOP to BOTTOM from terrain and the operations.
func _paint(top: int, bottom: int) -> void:
	var limit := mini(bottom, height)
	if limit > top:
		frame.blit_rect(terrain, Rect2i(0, top, width, limit - top), Vector2i(0, top))
	if bottom > limit:
		frame.fill_rect(Rect2i(0, maxi(top, limit), width, bottom - maxi(top, limit)), CLEAR)
	for op in ops:
		var source: Rect2i = op[2]
		var at: Vector2i = op[3]
		var first := maxi(at.y, top)
		var last := mini(at.y + source.size.y, limit)
		if first < last:
			frame.blend_rect(op[1], Rect2i(source.position.x, source.position.y + first - at.y, source.size.x, last - first), Vector2i(at.x, first))

## Repaint and write the changed strips of frame ID into TARGET.
## Return "" or a message describing the write failure.
func publish(target: String, id: int) -> String:
	if target != directory:
		directory = target
		for index in strips:
			versions[index] = []
		dirty.fill(1)
	_finish()
	batch.clear()
	for index in strips:
		if dirty[index]:
			batch.append(index)
	if batch.is_empty():
		return ""
	batch_id = id
	failures.clear()
	var task := WorkerThreadPool.add_group_task(_write, batch.size(), -1, true, "Iron Tide strips")
	WorkerThreadPool.wait_for_group_task_completion(task)
	if not failures.is_empty():
		return failures[0]
	for index in batch:
		var kept: Array = versions[index]
		kept.append(_strip_path(index, id))
		while kept.size() > KEEP:
			DirAccess.remove_absolute(kept.pop_front())
		serials[index] = id
		dirty[index] = 0
	published = id
	return ""

func _strip_path(index: int, id: int) -> String:
	return "%s/%d-%d.png" % [directory, index, id]

## Encode and atomically write the batch's Nth strip; runs on the worker pool.
func _write(n: int) -> void:
	var index := batch[n]
	var image := frame.get_region(Rect2i(0, index * line, width, line))
	if (index + 1) * line <= height:
		image.convert(Image.FORMAT_RGB8)
	var path := _strip_path(index, batch_id)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	var failure := ""
	if file == null:
		failure = "无法写入画面文件：" + error_string(FileAccess.get_open_error())
	else:
		file.store_buffer(image.save_png_to_buffer())
		file.close()
		var result := DirAccess.rename_absolute(path + ".tmp", path)
		if result != OK:
			failure = "无法发布画面文件：" + error_string(result)
	if not failure.is_empty():
		mutex.lock()
		failures.append(failure)
		mutex.unlock()

## Describe the published strips for the observation.
func description() -> Dictionary:
	return {"id": published, "block": block, "line": line, "width": width, "strips": Array(serials)}
