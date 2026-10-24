class_name QREngine
extends RefCounted

enum ECLevel { LOW = 0, MEDIUM = 1, QUARTILE = 2, HIGH = 3 }

static func generate_qr(
	text: String,
	pixel_size: int = 512,
	fg_color: Color = Color.BLACK,
	bg_color: Color = Color.WHITE,
	quiet_zone: int = 4,
	ec_level: ECLevel = ECLevel.MEDIUM,
	logo: Texture2D = null
) -> Image:
	var byte_data := text.to_utf8_buffer()
	var matrix := _build_matrix(byte_data, ec_level)
	var base_dim := matrix.size()
	var total_modules := base_dim + (quiet_zone * 2)
	
	var module_px := maxi(1, pixel_size / total_modules)
	var final_dim := total_modules * module_px
	
	var img := Image.create(final_dim, final_dim, false, Image.FORMAT_RGBA8)
	img.fill(bg_color)
	
	for y in range(base_dim):
		for x in range(base_dim):
			if matrix[y][x]:
				var start_x := (x + quiet_zone) * module_px
				var start_y := (y + quiet_zone) * module_px
				for py in range(module_px):
					for px in range(module_px):
						img.set_pixel(start_x + px, start_y + py, fg_color)
						
	if logo != null:
		var logo_img := logo.get_image()
		var max_logo_size := int(final_dim * 0.22)
		logo_img.resize(max_logo_size, max_logo_size, Image.INTERPOLATE_LANCZOS)
		
		var offset_x := (final_dim - max_logo_size) / 2
		var offset_y := (final_dim - max_logo_size) / 2
		
		var pad := int(module_px * 1.5)
		for y in range(offset_y - pad, offset_y + max_logo_size + pad):
			for x in range(offset_x - pad, offset_x + max_logo_size + pad):
				if x >= 0 and x < final_dim and y >= 0 and y < final_dim:
					img.set_pixel(x, y, bg_color)
					
		img.blend_rect(logo_img, Rect2i(0, 0, max_logo_size, max_logo_size), Vector2i(offset_x, offset_y))

	return img

static func _build_matrix(data: PackedByteArray, ec_level: ECLevel) -> Array:
	var version := _get_min_version(data.size(), ec_level)
	var dim := 17 + (version * 4)
	
	var grid: Array = []
	var reserved: Array = []
	for y in range(dim):
		var r_grid := []
		var r_res := []
		r_grid.resize(dim)
		r_res.resize(dim)
		r_grid.fill(false)
		r_res.fill(false)
		grid.append(r_grid)
		reserved.append(r_res)

	_place_finder(grid, reserved, 0, 0)
	_place_finder(grid, reserved, dim - 7, 0)
	_place_finder(grid, reserved, 0, dim - 7)

	for i in range(8, dim - 8):
		if not reserved[6][i]:
			grid[6][i] = (i % 2 == 0)
			reserved[6][i] = true
		if not reserved[i][6]:
			grid[i][6] = (i % 2 == 0)
			reserved[i][6] = true

	if version >= 2:
		var pos := _get_alignment_positions(version)
		for ay in pos:
			for ax in pos:
				if not _is_overlapping_finder(ax, ay, dim):
					_place_alignment(grid, reserved, ax, ay)

	grid[dim - 8][8] = true
	reserved[dim - 8][8] = true
	_reserve_format_areas(reserved, dim)

	var bit_stream := _build_bit_stream(data, version)
	_write_data_bits(grid, reserved, bit_stream, dim)
	_apply_format_bits(grid, ec_level, 0, dim)

	return grid

static func _get_min_version(byte_len: int, ec_level: ECLevel) -> int:
	var capacities := [
		[19, 16, 13, 9],
		[34, 28, 22, 16],
		[55, 44, 34, 26],
		[80, 64, 48, 36],
		[108, 86, 62, 46],
		[136, 108, 76, 60]
	]
	for v in range(capacities.size()):
		if byte_len <= capacities[v][ec_level]:
			return v + 1
	return 6

static func _place_finder(grid: Array, reserved: Array, x: int, y: int) -> void:
	for r in range(-1, 8):
		for c in range(-1, 8):
			var gx := x + c
			var gy := y + r
			if gy >= 0 and gy < grid.size() and gx >= 0 and gx < grid.size():
				reserved[gy][gx] = true
				if r >= 0 and r <= 6 and c >= 0 and c <= 6:
					var is_border := (r == 0 or r == 6 or c == 0 or c == 6)
					var is_center := (r >= 2 and r <= 4 and c >= 2 and c <= 4)
					grid[gy][gx] = (is_border or is_center)

static func _place_alignment(grid: Array, reserved: Array, cx: int, cy: int) -> void:
	for r in range(-2, 3):
		for c in range(-2, 3):
			grid[cy + r][cx + c] = (abs(r) == 2 or abs(c) == 2 or (r == 0 and c == 0))
			reserved[cy + r][cx + c] = true

static func _is_overlapping_finder(x: int, y: int, dim: int) -> bool:
	if x < 9 and y < 9: return true
	if x > dim - 9 and y < 9: return true
	if x < 9 and y > dim - 9: return true
	return false

static func _get_alignment_positions(version: int) -> Array:
	match version:
		2: return [6, 18]
		3: return [6, 22]
		4: return [6, 26]
		5: return [6, 30]
		6: return [6, 34]
		_: return []

static func _reserve_format_areas(reserved: Array, dim: int) -> void:
	for i in range(9):
		reserved[8][i] = true
		reserved[i][8] = true
		reserved[dim - 1 - i][8] = true
		reserved[8][dim - 1 - i] = true

static func _build_bit_stream(data: PackedByteArray, version: int) -> Array[bool]:
	var bits: Array[bool] = []
	bits.append_array([false, true, false, false])
	var count := data.size()
	for i in range(7, -1, -1):
		bits.append(((count >> i) & 1) == 1)
	for byte in data:
		for i in range(7, -1, -1):
			bits.append(((byte >> i) & 1) == 1)
	return bits

static func _write_data_bits(grid: Array, reserved: Array, bits: Array[bool], dim: int) -> void:
	var bit_idx := 0
	var upward := true
	var col := dim - 1
	while col > 0:
		if col == 6: col -= 1
		var row_range := range(dim - 1, -1, -1) if upward else range(0, dim)
		for row in row_range:
			for c in [col, col - 1]:
				if not reserved[row][c]:
					var val := false
					if bit_idx < bits.size():
						val = bits[bit_idx]
						bit_idx += 1
					if (row + c) % 2 == 0:
						val = not val
					grid[row][c] = val
		upward = not upward
		col -= 2

static func _apply_format_bits(grid: Array, ec_level: ECLevel, mask: int, dim: int) -> void:
	var format_masks := [0x5412, 0x5125, 0x5E7C, 0x5B4B, 0x45F9, 0x40CE, 0x4F97, 0x4AC0]
	var fmt: int = format_masks[mask % 8]
	
	var bits: Array[bool] = []
	for i in range(14, -1, -1):
		bits.append(((fmt >> i) & 1) == 1)
		
	var idx := 0
	for i in range(6): grid[8][i] = bits[idx]; idx += 1
	grid[8][7] = bits[idx]; idx += 1
	grid[8][8] = bits[idx]; idx += 1
	grid[7][8] = bits[idx]; idx += 1
	for i in range(5, -1, -1): grid[i][8] = bits[idx]; idx += 1
