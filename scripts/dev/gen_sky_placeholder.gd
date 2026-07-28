extends Node
## Writes the equirectangular reference panorama used as the stand-in sky.
##
##   godot --path . --headless res://scenes/dev/gen_sky_placeholder.tscn ++ [width]
##
## Regenerate it at authoring resolution (4096) if you want a bigger reference
## to paint over. The point of the image is that it is *readable*: it shows
## where the seam falls, which way each cardinal band points once it is on the
## sky, and how much an equirectangular projection stretches near the poles.
##
## Mapping, which is also the contract any hand-authored panorama has to follow:
##   u = x / width   -> yaw   0..360 degrees, left to right
##   v = y / height  -> pitch +90 (top row) down to -90 (bottom row)
## so the horizon is the middle row and the top and bottom rows each collapse to
## a single point in the sky.

const BAND_COLORS: Array[Color] = [
	Color(0.95, 0.20, 0.20),  # u = 0.00, the seam
	Color(0.30, 0.90, 0.35),  # u = 0.25
	Color(0.30, 0.55, 1.00),  # u = 0.50
	Color(0.95, 0.85, 0.25),  # u = 0.75
]

## Sampled from the ProceduralSkyMaterial this replaces, so swapping between the
## two does not change the lighting of the arena underneath.
const TOP_COLOR := Color(0.13, 0.07, 0.12)
const HORIZON_COLOR := Color(0.5, 0.17, 0.1)
const BOTTOM_COLOR := Color(0.06, 0.04, 0.05)

const OUT_PATH := "res://assets/sky/placeholder_panorama.png"


func _ready() -> void:
	var width := 2048
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_int():
		width = args[0].to_int()
	var height := width / 2

	var image := Image.create(width, height, false, Image.FORMAT_RGB8)
	_paint_gradient(image)
	_paint_grid(image)
	_paint_bands(image)
	_paint_poles(image)

	DirAccess.make_dir_recursive_absolute(OUT_PATH.get_base_dir())
	var error := image.save_png(OUT_PATH)
	print("%s (%dx%d) -> %d" % [OUT_PATH, width, height, error])
	get_tree().quit(0 if error == OK else 1)


## Vertical ramp through the same three colours the procedural sky uses, so the
## placeholder reads as the same time of day.
func _paint_gradient(image: Image) -> void:
	var height := image.get_height()
	for y in height:
		var v := float(y) / float(height - 1)
		var color: Color = TOP_COLOR.lerp(HORIZON_COLOR, minf(v * 2.0, 1.0)) if v < 0.5 \
				else HORIZON_COLOR.lerp(BOTTOM_COLOR, (v - 0.5) * 2.0)
		for x in image.get_width():
			image.set_pixel(x, y, color)


## A 15-degree graticule, with the horizon picked out. Painting a straight line
## here shows exactly how much it will bow once it is wrapped onto the sky.
func _paint_grid(image: Image) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var line := Color(1.0, 0.85, 0.7, 1.0)

	for step in range(0, 360, 15):
		var x := int(round(float(step) / 360.0 * float(width))) % width
		for y in height:
			image.set_pixel(x, y, image.get_pixel(x, y).lerp(line, 0.25))

	for step in range(-90, 91, 15):
		var y := int(round((90.0 - float(step)) / 180.0 * float(height - 1)))
		# The horizon is the row every other row is measured against, so it gets
		# to be obvious.
		var strength := 0.7 if step == 0 else 0.25
		var thickness := maxi(1, height / 512) if step == 0 else 1
		for offset in thickness:
			var row := clampi(y + offset, 0, height - 1)
			for x in width:
				image.set_pixel(x, row, image.get_pixel(x, row).lerp(line, strength))


## Four coloured pillars at the quarter turns, each tagged with that many blocks
## below the horizon so the render tells you which yaw it ended up facing.
func _paint_bands(image: Image) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var half := maxi(2, width / 200)

	for index in BAND_COLORS.size():
		var center := int(round(float(index) * 0.25 * float(width)))
		var color := BAND_COLORS[index]
		for offset in range(-half, half + 1):
			var x := posmod(center + offset, width)
			# Stops short of the poles: up there the band is all stretch and no
			# information.
			for y in range(height / 6, height - height / 6):
				image.set_pixel(x, y, color)

		var block := maxi(3, width / 128)
		for tag in index + 1:
			var top := height / 2 + block * 2 + tag * block * 2
			for by in range(top, mini(top + block, height)):
				for bx in range(center - block, center + block):
					image.set_pixel(posmod(bx, width), by, color)


## Solid caps on the two rows that collapse to a point, so a mis-set projection
## shows up as a smear instead of hiding in the gradient.
func _paint_poles(image: Image) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var cap := maxi(2, height / 64)
	for y in cap:
		for x in width:
			image.set_pixel(x, y, Color(0.85, 0.9, 1.0))
			image.set_pixel(x, height - 1 - y, Color(0.15, 0.12, 0.14))
