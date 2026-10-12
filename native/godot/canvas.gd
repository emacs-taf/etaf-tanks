extends RefCounted
## Original pixel art and CPU frame composition for headless Godot.
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Frames are composed at the native 8 px block scale with the Image API (no
## GPU renderer exists in headless mode) and published as PNG files through an
## atomic rename. Terrain is cached and repainted only where cells change.

const Battle := preload("res://battle.gd")
const SUB := 4
const EMPTY := 0
const BRICK := 1
const STEEL := 2
const WATER := 3
const FOREST := 4
const ICE := 5
const SLOTS := 8
const CLEAR := Color(0, 0, 0, 0)

const PALETTES := {
	"dark": {
		"ground": "#0b0c0f", "grid": "#ffffff14",
		"brick": "#b0501e", "brick_light": "#d98544", "mortar": "#4b2311",
		"steel": "#9ea5ad", "steel_light": "#eef1f4", "steel_dark": "#5a6069",
		"water": "#2154c8", "water_light": "#7aa7f6", "water_dark": "#163c96",
		"forest": "#2f7f2f", "forest_light": "#7fc759", "forest_dark": "#174e1b",
		"ice": "#c3d0dc", "ice_light": "#f6fafd", "ice_dark": "#93a3b4",
		"text": "#ffffff", "text_shadow": "#000000", "shade": "#00000088", "danger": "#f0503f",
		"eagle": "#a8adb4", "eagle_light": "#f0f2f4", "eagle_dark": "#4a4f57", "eagle_gold": "#e6b428",
		"ruin": "#6e5646", "ruin_dark": "#3a2c22", "ruin_light": "#9a7f69",
		"shell": "#f6f6f6", "shell_dark": "#8d8d8d",
		"fire_white": "#ffffff", "fire_yellow": "#ffd94c", "fire_orange": "#ec6a22", "fire_red": "#a02414",
		"shield": "#ffffff", "shield_alt": "#72d6ff",
		"bonus_box": "#b5302a", "bonus_edge": "#ffe3a6", "bonus_icon": "#ffffff", "bonus_gold": "#ffd24a",
		"cursor": "#ffffff", "cursor_dark": "#000000", "mark_bad": "#ff4d4d",
	},
	"light": {
		"ground": "#cfc8ad", "grid": "#00000014",
		"brick": "#a8481a", "brick_light": "#cf7a3a", "mortar": "#5c2b12",
		"steel": "#8e959e", "steel_light": "#e8ebef", "steel_dark": "#4d535c",
		"water": "#2d63d0", "water_light": "#8ab4f8", "water_dark": "#1d479f",
		"forest": "#2c7a2c", "forest_light": "#6fbb4c", "forest_dark": "#164a1a",
		"ice": "#e6eef5", "ice_light": "#ffffff", "ice_dark": "#a9b8c7",
		"text": "#1d1d1d", "text_shadow": "#fffdf2", "shade": "#fffbea88", "danger": "#c22d1f",
		"eagle": "#868c94", "eagle_light": "#e9ecef", "eagle_dark": "#3b4048", "eagle_gold": "#c9930f",
		"ruin": "#6e5646", "ruin_dark": "#3a2c22", "ruin_light": "#9a7f69",
		"shell": "#2a2a2a", "shell_dark": "#000000",
		"fire_white": "#ffffff", "fire_yellow": "#ffd94c", "fire_orange": "#ec6a22", "fire_red": "#a02414",
		"shield": "#1f6fd1", "shield_alt": "#ffffff",
		"bonus_box": "#b5302a", "bonus_edge": "#ffe3a6", "bonus_icon": "#ffffff", "bonus_gold": "#ffd24a",
		"cursor": "#000000", "cursor_dark": "#ffffff", "mark_bad": "#d61f1f",
	},
}

const COLORWAYS := {
	"player": {"body": "#d9a21c", "light": "#ffe07a", "dark": "#7a560b", "turret": "#ecbb33", "track": "#3a2e12", "tread": "#93793a"},
	"enemy": {"body": "#b5bac1", "light": "#f2f4f6", "dark": "#585d65", "turret": "#cdd1d6", "track": "#2b2e33", "tread": "#7c8189"},
	"bonus": {"body": "#cf3a2c", "light": "#ff8f7c", "dark": "#6a1811", "turret": "#e5503f", "track": "#391611", "tread": "#9c463b"},
	"armour4": {"body": "#5c9c45", "light": "#b9e597", "dark": "#2a4d1f", "turret": "#71b257", "track": "#1d2d18", "tread": "#5d7a4d"},
	"armour3": {"body": "#c99a2a", "light": "#f6dc8a", "dark": "#62470e", "turret": "#ddb144", "track": "#33280f", "tread": "#86703a"},
	"armour2": {"body": "#c66a32", "light": "#f4b68a", "dark": "#5e2e12", "turret": "#da8150", "track": "#331c10", "tread": "#86563a"},
	"flash": {"body": "#ffffff", "light": "#ffffff", "dark": "#c8ccd2", "turret": "#ffffff", "track": "#9aa0a8", "tread": "#ffffff"},
}

const SPECS := {
	"player0": {"tracks": [1, 12], "tw": 3, "top": 2, "bottom": 15, "hull": Rect2i(4, 4, 8, 10), "turret": Rect2i(5, 6, 6, 6), "barrels": [Rect2i(7, 0, 2, 7)], "muzzle": false, "plates": false, "cut": false},
	"player1": {"tracks": [1, 12], "tw": 3, "top": 2, "bottom": 15, "hull": Rect2i(4, 4, 8, 10), "turret": Rect2i(5, 6, 6, 6), "barrels": [Rect2i(7, 1, 2, 6)], "muzzle": true, "plates": false, "cut": false},
	"player2": {"tracks": [1, 12], "tw": 3, "top": 2, "bottom": 15, "hull": Rect2i(4, 3, 8, 12), "turret": Rect2i(5, 6, 6, 7), "barrels": [Rect2i(7, 1, 2, 6)], "muzzle": true, "plates": true, "cut": false},
	"player3": {"tracks": [0, 12], "tw": 4, "top": 2, "bottom": 15, "hull": Rect2i(4, 3, 8, 12), "turret": Rect2i(4, 6, 8, 7), "barrels": [Rect2i(6, 0, 1, 8), Rect2i(9, 0, 1, 8)], "muzzle": false, "plates": true, "cut": false},
	"basic": {"tracks": [1, 12], "tw": 3, "top": 3, "bottom": 15, "hull": Rect2i(4, 5, 8, 9), "turret": Rect2i(5, 7, 6, 6), "barrels": [Rect2i(7, 1, 2, 7)], "muzzle": false, "plates": false, "cut": false},
	"fast": {"tracks": [2, 12], "tw": 2, "top": 1, "bottom": 14, "hull": Rect2i(4, 3, 8, 10), "turret": Rect2i(6, 6, 4, 4), "barrels": [Rect2i(7, 0, 2, 7)], "muzzle": false, "plates": false, "cut": true},
	"power": {"tracks": [1, 12], "tw": 3, "top": 2, "bottom": 15, "hull": Rect2i(4, 4, 8, 10), "turret": Rect2i(5, 7, 6, 6), "barrels": [Rect2i(6, 0, 1, 8), Rect2i(9, 0, 1, 8)], "muzzle": false, "plates": false, "cut": false},
	"armor": {"tracks": [0, 12], "tw": 4, "top": 2, "bottom": 15, "hull": Rect2i(4, 3, 8, 12), "turret": Rect2i(4, 6, 8, 7), "barrels": [Rect2i(7, 1, 2, 6)], "muzzle": true, "plates": true, "cut": false},
}

const EAGLE := [
	"................",
	"x..............x",
	"xx.....hh.....xx",
	"xxx...hhhh...xxx",
	"xxxx..hbhh..xxxx",
	".xxxx.hhhh.xxxx.",
	".xxxxxhhhhxxxxx.",
	"..xxxxwwwwxxxx..",
	"...xxxwwwwxxx...",
	"....xxwwwwxx....",
	"......wwww......",
	".....w.ww.w.....",
	"....ww.ww.ww....",
	"......wwww......",
	"...gggggggggg...",
	"..gggggggggggg..",
]
const RUIN := [
	"................",
	"................",
	"................",
	"................",
	"......l.........",
	".....lrl....l...",
	"..l..rrr...lr...",
	".lr.rrdrr.lrrl..",
	".rrrrrdrrrrrdr..",
	"lrrdrrrrrdrrrrl.",
	"rrrrrdrrrrrrdrr.",
	"rdrrrrrrdrrrrrrl",
	"rrrrdrrrrrrdrrrr",
	"rrrrrrrdrrrrrdrr",
	"...gggggggggg...",
	"..gggggggggggg..",
]
const ICONS := {
	"helmet": ["............", "....wwww....", "..wwwwwwww..", ".wwwwwwwwww.", ".wwggggggww.", "wwwwwwwwwwww",
		"wwwwwwwwwwww", "www......www", "ww........ww", "............", "............", "............"],
	"clock": ["....wwww....", "..ww....ww..", ".w....g...w.", ".w....g...w.", "w.....g....w", "w.....ggg..w",
		"w..........w", "w..........w", ".w........w.", ".w........w.", "..ww....ww..", "....wwww...."],
	"shovel": ["..........ww", ".........www", "........ww..", ".......ww...", "......ww....", "..w..ww.....",
		".wwwww......", "wwwww.......", "wwwwww......", "wwwwww......", ".wwww.......", "..ww........"],
	"star": [".....gg.....", ".....gg.....", "....gggg....", "gggggggggggg", ".gggggggggg.", "..gggggggg..",
		"...gggggg...", "...gggggg...", "..gggg.ggg..", "..ggg...gg..", ".gg......gg.", "............"],
	"grenade": ["......ww....", ".....w..w...", "....gggg....", "...wwwwww...", "..wwwwwwww..", "..ww.ww.ww..",
		"..wwwwwwww..", "..ww.ww.ww..", "..wwwwwwww..", "..ww.ww.ww..", "...wwwwww...", "............"],
	"tank": [".....ww.....", ".....ww.....", ".....ww.....", "ww.wwwwww.ww", "wwwwggggwwww", "ww.wggggw.ww",
		"wwwwggggwwww", "ww.wwwwww.ww", "wwwwwwwwwwww", "ww........ww", "............", "............"],
}
const FONT := {
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
	"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
	"5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
	"6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
	"7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
	"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
	"9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	"V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
	"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
}

var theme := "dark"
var colors := {}
var sprites := {}
var width := 0
var height := 0
var cw := 0
var ch := 0
var shown := PackedByteArray()
var terrain: Array = []
var forest: Image
var frame: Image
var shade: Image
var grid: Image

func _init() -> void:
	configure("dark")

func configure(name: String) -> void:
	theme = name
	colors = {}
	for key in PALETTES[name]:
		colors[key] = Color(PALETTES[name][key])
	sprites = {}
	cw = 0
	ch = 0

# ---------------------------------------------------------------- terrain

func _paint(image: Image, cx: int, cy: int, code: int, wave: int) -> void:
	var x := cx * SUB
	var y := cy * SUB
	var rect := Rect2i(x, y, SUB, SUB)
	match code:
		BRICK:
			image.fill_rect(rect, colors.brick)
			image.fill_rect(Rect2i(x, y, SUB, 1), colors.brick_light)
			image.fill_rect(Rect2i(x, y + 3, SUB, 1), colors.mortar)
			var joint := x + (1 if cy % 2 == 0 else 3)
			image.fill_rect(Rect2i(joint, y, 1, 3), colors.mortar)
		STEEL:
			image.fill_rect(rect, colors.steel)
			if cy % 2 == 0:
				image.fill_rect(Rect2i(x, y, SUB, 1), colors.steel_light)
			else:
				image.fill_rect(Rect2i(x, y + 3, SUB, 1), colors.steel_dark)
			if cx % 2 == 0:
				image.fill_rect(Rect2i(x, y, 1, SUB), colors.steel_light)
			else:
				image.fill_rect(Rect2i(x + 3, y, 1, SUB), colors.steel_dark)
			image.set_pixel(x + (3 if cx % 2 == 0 else 0), y + (3 if cy % 2 == 0 else 0), colors.steel_light)
		WATER:
			image.fill_rect(rect, colors.water)
			image.set_pixel(x + (cy + wave * 2) % 4, y + 1, colors.water_light)
			image.set_pixel(x + (cy + 2 + wave * 2) % 4, y + 3, colors.water_light)
			image.set_pixel(x + (cy + 1 + wave) % 4, y + 2, colors.water_dark)
		ICE:
			image.fill_rect(rect, colors.ice)
			if (cx + cy) % 2 == 0:
				for i in 4:
					image.set_pixel(x + i, y + 3 - i, colors.ice_light)
			else:
				image.set_pixel(x + 2, y + 1, colors.ice_dark)
		_:
			image.fill_rect(rect, colors.ground)

func _paint_forest(cx: int, cy: int, code: int) -> void:
	var x := cx * SUB
	var y := cy * SUB
	if code != FOREST:
		forest.fill_rect(Rect2i(x, y, SUB, SUB), CLEAR)
		return
	forest.fill_rect(Rect2i(x, y, SUB, SUB), colors.forest)
	var shift := (cx + cy * 3) % 4
	for i in 4:
		forest.set_pixel(x + (i + shift) % 4, y + i, colors.forest_light)
		forest.set_pixel(x + (i + shift + 2) % 4, y + i, colors.forest_dark)

func _paint_cell(index: int, code: int) -> void:
	var cx := index % cw
	var cy := index / cw
	for wave in 2:
		_paint(terrain[wave], cx, cy, code, wave)
	_paint_forest(cx, cy, code)

## Show CELLS (columns COLUMNS by ROWS). Only changed cells are repainted.
func sync(cells: PackedByteArray, columns: int, rows: int) -> void:
	if columns != cw or rows != ch:
		cw = columns
		ch = rows
		width = cw * SUB
		height = ch * SUB
		terrain = [Image.create_empty(width, height, false, Image.FORMAT_RGBA8),
			Image.create_empty(width, height, false, Image.FORMAT_RGBA8)]
		forest = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
		frame = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
		shade = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
		shade.fill(colors.shade)
		grid = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
		for x in range(0, width, 16):
			grid.fill_rect(Rect2i(x, 0, 1, height), colors.grid)
		for y in range(0, height, 16):
			grid.fill_rect(Rect2i(0, y, width, 1), colors.grid)
		shown = PackedByteArray()
		shown.resize(cw * ch)
		for index in cw * ch:
			shown[index] = cells[index]
			_paint_cell(index, cells[index])
		return
	for index in cw * ch:
		if shown[index] != cells[index]:
			shown[index] = cells[index]
			_paint_cell(index, cells[index])

func update(cells: PackedByteArray, indices: PackedInt32Array) -> void:
	for index in indices:
		if index < shown.size() and shown[index] != cells[index]:
			shown[index] = cells[index]
			_paint_cell(index, cells[index])

# ---------------------------------------------------------------- sprites

func _tank_image(spec: Dictionary, way: Dictionary, step: int) -> Image:
	var image := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	var tw: int = spec.tw
	for tx in spec.tracks:
		image.fill_rect(Rect2i(tx, spec.top, tw, spec.bottom - spec.top + 1), way.track)
		for y in range(spec.top + step, spec.bottom + 1, 2):
			image.fill_rect(Rect2i(tx, y, tw, 1), way.tread)
	var hull: Rect2i = spec.hull
	image.fill_rect(hull, way.body)
	image.fill_rect(Rect2i(hull.position.x, hull.position.y, hull.size.x, 1), way.light)
	image.fill_rect(Rect2i(hull.position.x, hull.position.y, 1, hull.size.y), way.light)
	image.fill_rect(Rect2i(hull.end.x - 1, hull.position.y + 1, 1, hull.size.y - 1), way.dark)
	image.fill_rect(Rect2i(hull.position.x + 1, hull.end.y - 1, hull.size.x - 1, 1), way.dark)
	if spec.plates:
		for y in range(hull.position.y + 3, hull.end.y - 2, 3):
			image.fill_rect(Rect2i(hull.position.x + 1, y, hull.size.x - 2, 1), way.dark)
	if spec.cut:
		image.set_pixel(hull.position.x, hull.position.y, CLEAR)
		image.set_pixel(hull.end.x - 1, hull.position.y, CLEAR)
	var turret: Rect2i = spec.turret
	image.fill_rect(turret, way.dark)
	image.fill_rect(turret.grow(-1), way.turret)
	image.set_pixel(turret.position.x + 1, turret.position.y + 1, way.light)
	for corner in [turret.position, Vector2i(turret.end.x - 1, turret.position.y),
			Vector2i(turret.position.x, turret.end.y - 1), turret.end - Vector2i.ONE]:
		image.set_pixelv(corner, way.body)
	for barrel in spec.barrels:
		image.fill_rect(barrel, way.light)
		if barrel.size.x > 1:
			image.fill_rect(Rect2i(barrel.end.x - 1, barrel.position.y, 1, barrel.size.y), way.dark)
	if spec.muzzle:
		var first: Rect2i = spec.barrels[0]
		image.fill_rect(Rect2i(first.position.x - 1, 0, first.size.x + 2, 2), way.light)
		image.fill_rect(Rect2i(first.end.x, 0, 1, 2), way.dark)
	return image

static func _turned(image: Image, facing: int) -> Image:
	match facing:
		1:
			image.rotate_90(CLOCKWISE)
		2:
			image.rotate_180()
		3:
			image.rotate_90(COUNTERCLOCKWISE)
	return image

func tank(shape: String, colorway: String, facing: int, step: int) -> Image:
	var key := "%s|%s|%d|%d" % [shape, colorway, facing, step]
	if not sprites.has(key):
		var way := {}
		for part in COLORWAYS[colorway]:
			way[part] = Color(COLORWAYS[colorway][part])
		sprites[key] = _turned(_tank_image(SPECS[shape], way, step), facing)
	return sprites[key]

func _pattern(rows: Array, palette: Dictionary, size := 16, offset := Vector2i.ZERO, into: Image = null) -> Image:
	var image := into if into != null else Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var key := row[x]
			if palette.has(key):
				image.set_pixel(offset.x + x, offset.y + y, palette[key])
	return image

func base(alive: bool) -> Image:
	var key := "base|%s" % alive
	if not sprites.has(key):
		if alive:
			sprites[key] = _pattern(EAGLE, {"x": colors.eagle, "h": colors.eagle_light, "b": colors.eagle_gold,
				"w": colors.eagle_light, "g": colors.eagle_dark})
		else:
			sprites[key] = _pattern(RUIN, {"r": colors.ruin, "d": colors.ruin_dark, "l": colors.ruin_light, "g": colors.eagle_dark})
	return sprites[key]

func icon(kind: String) -> Image:
	var key := "icon|" + kind
	if not sprites.has(key):
		var image := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
		image.fill_rect(Rect2i(0, 0, 16, 16), colors.bonus_edge)
		image.fill_rect(Rect2i(1, 1, 14, 14), colors.bonus_box)
		for corner in [Vector2i(0, 0), Vector2i(15, 0), Vector2i(0, 15), Vector2i(15, 15)]:
			image.set_pixelv(corner, CLEAR)
		_pattern(ICONS[kind], {"w": colors.bonus_icon, "g": colors.bonus_gold}, 16, Vector2i(2, 2), image)
		sprites[key] = image
	return sprites[key]

func shield(step: int) -> Image:
	var key := "shield|%d" % step
	if not sprites.has(key):
		var image := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
		for i in 16:
			var tone: Color = colors.shield if (i + step * 2) % 4 < 2 else colors.shield_alt
			if (i + step) % 3 != 2:
				for point in [Vector2i(i, 0), Vector2i(15 - i, 15), Vector2i(0, 15 - i), Vector2i(15, i)]:
					image.set_pixelv(point, tone)
		sprites[key] = image
	return sprites[key]

func sparkle(step: int) -> Image:
	var key := "sparkle|%d" % step
	if not sprites.has(key):
		var image := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
		var reach: int = [2, 4, 7, 4][step]
		for i in range(-reach, reach + 1):
			var tone: Color = colors.fire_white if absi(i) < reach / 2 + 1 else colors.shield_alt
			image.set_pixel(8 + i, 8, tone)
			image.set_pixel(8, 8 + i, tone)
		for i in range(-reach / 2, reach / 2 + 1):
			image.set_pixel(8 + i, 8 + i, colors.fire_yellow)
			image.set_pixel(8 + i, 8 - i, colors.fire_yellow)
		image.set_pixel(8, 8, colors.fire_white)
		sprites[key] = image
	return sprites[key]

func burst(size: int, radius: float) -> Image:
	var key := "burst|%d|%d" % [size, int(radius * 10)]
	if not sprites.has(key):
		var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
		var centre := (size - 1) / 2.0
		for y in size:
			for x in size:
				var noise := float((x * 7 + y * 13 + x * y) % 5) * 0.45
				var distance := Vector2(x - centre, y - centre).length() + noise
				if distance < radius * 0.4:
					image.set_pixel(x, y, colors.fire_white)
				elif distance < radius * 0.7:
					image.set_pixel(x, y, colors.fire_yellow)
				elif distance < radius:
					image.set_pixel(x, y, colors.fire_orange)
				elif distance < radius + 1.6 and (x + y) % 2 == 0:
					image.set_pixel(x, y, colors.fire_red)
		sprites[key] = image
	return sprites[key]

# ---------------------------------------------------------------- composition

func _put(image: Image, at: Vector2) -> void:
	frame.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(roundi(at.x), roundi(at.y)))

func _text_width(text: String, scale: int) -> int:
	return text.length() * 6 * scale - scale

func text(message: String, at: Vector2i, scale: int, tone: Color) -> void:
	for pass_index in 2:
		var shadow := pass_index == 0
		var tint: Color = colors.text_shadow if shadow else tone
		var x := at.x + (scale if shadow else 0)
		var y := at.y + (scale if shadow else 0)
		for glyph in message:
			if FONT.has(glyph):
				var rows: Array = FONT[glyph]
				for row in 7:
					var bits: String = rows[row]
					for column in 5:
						if bits[column] == "1":
							frame.fill_rect(Rect2i(x + column * scale, y + row * scale, scale, scale), tint)
			x += 6 * scale

func banner(message: String, tone: Color, dim := true) -> void:
	if dim:
		frame.blend_rect(shade, Rect2i(0, 0, width, height), Vector2i.ZERO)
	var scale := 2 if _text_width(message, 2) <= width - 8 else 1
	var at := Vector2i((width - _text_width(message, scale)) / 2, (height - 7 * scale) / 2)
	text(message, at, scale, tone)

func _tank_look(battle, unit) -> Array:
	var shape: String = ("player%d" % battle.star) if not unit.enemy else Battle.KINDS[unit.kind]
	var way := "player"
	if unit.flash > 0.0:
		way = "flash"
	elif unit.enemy:
		way = "enemy"
		if unit.bonus and int(battle.anim * 8.0) % 2 == 0:
			way = "bonus"
		elif unit.kind == 3 and unit.armour > 1:
			way = "armour%d" % unit.armour
	return [shape, way]

func compose_battle(battle) -> void:
	if battle.terrain_reset:
		sync(battle.cells, battle.cw, battle.ch)
		battle.terrain_reset = false
		battle.dirty_cells.clear()
	elif not battle.dirty_cells.is_empty():
		update(battle.cells, battle.dirty_cells)
		battle.dirty_cells.clear()
	var wave := int(battle.anim / 0.6) % 2
	frame.blit_rect(terrain[wave], Rect2i(0, 0, width, height), Vector2i.ZERO)
	if battle.fortify > 0.0 and battle.fortify < 3.0 and int(battle.anim * 4.0) % 2 == 0:
		for cell in battle.fort_cells:
			if battle.cells[cell] == STEEL:
				_paint(frame, cell % cw, cell / cw, BRICK, 0)
	_put(base(battle.base_alive), battle.base_pos)
	if battle.bonus != null and (battle.bonus.timer > 5.0 or int(battle.anim * 6.0) % 2 == 0):
		_put(icon(Battle.BONUSES[battle.bonus.kind]), battle.bonus.pos)
	for item in battle.spawns:
		_put(sparkle(int(battle.anim * 14.0) % 4), item.pos)
	if battle.player == null and battle.respawn > 0.0 and battle.respawn < 0.8:
		_put(sparkle(int(battle.anim * 14.0) % 4), battle.player_spawn)
	var units: Array = battle.enemies.duplicate()
	if battle.player != null:
		units.append(battle.player)
	for unit in units:
		var look := _tank_look(battle, unit)
		_put(tank(look[0], look[1], unit.facing, int(unit.travel / 2.0) % 2), unit.pos)
		if unit.shield > 0.0:
			_put(shield(int(battle.anim * 20.0) % 2), unit.pos)
	for shell in battle.shells:
		var vertical: bool = shell.dir % 2 == 0
		var size := Vector2i(3, 4) if vertical else Vector2i(4, 3)
		var corner := Vector2i(roundi(shell.pos.x) - size.x / 2, roundi(shell.pos.y) - size.y / 2)
		frame.fill_rect(Rect2i(corner, size), colors.shell)
		frame.fill_rect(Rect2i(corner + Vector2i(1, 1), Vector2i.ONE), colors.shell_dark)
	frame.blend_rect(forest, Rect2i(0, 0, width, height), Vector2i.ZERO)
	for effect in battle.effects:
		var progress: float = 1.0 - effect.timer / effect.total
		match effect.kind:
			"spark":
				var spark := burst(16, [3.0, 5.0, 4.0][mini(2, int(progress * 3.0))])
				_put(spark, effect.pos - Vector2(8, 8))
			"blast":
				var blast := burst(32, [6.0, 10.0, 14.0, 10.0][mini(3, int(progress * 4.0))])
				_put(blast, effect.pos - Vector2(16, 16))
			"points":
				var label: String = effect.text
				text(label, Vector2i(roundi(effect.pos.x) - _text_width(label, 1) / 2, roundi(effect.pos.y) - 4), 1, colors.text)

func compose_map(parsed: Dictionary, cursor) -> void:
	if not parsed.has("terrain"):
		if frame == null:
			sync(PackedByteArray([0, 0, 0, 0]), 2, 2)
		frame.fill(colors.ground)
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
	sync(cells, columns, parsed.height * 2)
	frame.blit_rect(terrain[0], Rect2i(0, 0, width, height), Vector2i.ZERO)
	var grouped := {}
	var groups := {"H": [] if parsed.base == null else [parsed.base], "P": [] if parsed.player == null else [parsed.player], "E": parsed.spawns}
	for mark in groups:
		for corner in groups[mark]:
			for offset in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				grouped[(corner.y + offset.y) * parsed.width + corner.x + offset.x] = true
			var at := Vector2(corner) * 8.0
			match mark:
				"H":
					_put(base(true), at)
				"P":
					_put(tank("player0", "player", 0, 0), at)
				"E":
					_put(tank("basic", "enemy", 2, 0), at)
					_put(sparkle(1), at)
	for index in parsed.marks.size():
		if not parsed.marks[index].is_empty() and not grouped.has(index):
			var at := Vector2i(index % parsed.width, index / parsed.width) * 8
			frame.fill_rect(Rect2i(at, Vector2i(8, 8)), colors.mark_bad)
			frame.fill_rect(Rect2i(at + Vector2i(2, 2), Vector2i(4, 4)), colors.ground)
	frame.blend_rect(forest, Rect2i(0, 0, width, height), Vector2i.ZERO)
	if cursor != null:
		frame.blend_rect(grid, Rect2i(0, 0, width, height), Vector2i.ZERO)
		var box := Rect2i(cursor.x * 8, cursor.y * 8, cursor.size * 8, cursor.size * 8)
		_outline(box, colors.cursor)
		_outline(box.grow(-1), colors.cursor_dark)

func _outline(box: Rect2i, tone: Color) -> void:
	frame.fill_rect(Rect2i(box.position.x, box.position.y, box.size.x, 1), tone)
	frame.fill_rect(Rect2i(box.position.x, box.end.y - 1, box.size.x, 1), tone)
	frame.fill_rect(Rect2i(box.position.x, box.position.y, 1, box.size.y), tone)
	frame.fill_rect(Rect2i(box.end.x - 1, box.position.y, 1, box.size.y), tone)

## Write the composed frame into DIRECTORY slot ID; return its path or "".
func publish(directory: String, id: int) -> String:
	var path := "%s/frame-%d.png" % [directory, id % SLOTS]
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(frame.save_png_to_buffer())
	file.close()
	return path if DirAccess.rename_absolute(temporary, path) == OK else ""
