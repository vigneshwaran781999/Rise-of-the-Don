extends SceneTree
## Writes res://icon.ico, the Windows icon of the exported game and its window (M8), from the
## project icon res://icon.svg: PNG images at 256, 128, 64, 48, 32 and 16 px in one ICO file.
## Re-run after changing icon.svg:
##   "$GODOT" --headless --path . --script res://tools/godot/make_icon.gd

const SOURCE: String = "res://icon.svg"
const TARGET: String = "res://icon.ico"
const SIZES: PackedInt32Array = [256, 128, 64, 48, 32, 16]


func _init() -> void:
	var svg: String = FileAccess.get_file_as_string(SOURCE)
	var pngs: Array[PackedByteArray] = []
	for size: int in SIZES:
		var image := Image.new()
		var err: Error = image.load_svg_from_string(svg, float(size) / 128.0)
		if err != OK:
			push_error("make_icon: could not render %s at %d px (%s)" % [SOURCE, size, error_string(err)])
			quit(1)
			return
		if image.get_width() != size:
			image.resize(size, size, Image.INTERPOLATE_LANCZOS)
		pngs.append(image.save_png_to_buffer())
	var out := StreamPeerBuffer.new()
	out.big_endian = false
	out.put_u16(0)                 # reserved
	out.put_u16(1)                 # type: icon
	out.put_u16(SIZES.size())
	var offset: int = 6 + 16 * SIZES.size()
	for i: int in SIZES.size():
		var size: int = SIZES[i]
		out.put_u8(0 if size >= 256 else size)     # width (0 means 256)
		out.put_u8(0 if size >= 256 else size)     # height
		out.put_u8(0)                              # palette colours
		out.put_u8(0)                              # reserved
		out.put_u16(1)                             # colour planes
		out.put_u16(32)                            # bits per pixel
		out.put_u32(pngs[i].size())
		out.put_u32(offset)
		offset += pngs[i].size()
	for png: PackedByteArray in pngs:
		out.put_data(png)
	var file := FileAccess.open(TARGET, FileAccess.WRITE)
	if file == null:
		push_error("make_icon: could not write %s" % TARGET)
		quit(1)
		return
	file.store_buffer(out.data_array)
	file.close()
	print("make_icon: wrote %s (%s px, %d bytes)" % [TARGET, ", ".join(Array(SIZES).map(func(s: int) -> String: return str(s))), out.data_array.size()])
	quit(0)
