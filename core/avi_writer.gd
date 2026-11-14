class_name AviWriter
extends RefCounted
## A Motion-JPEG .avi file, one JPEG per frame (what Godot's Movie Maker writes, and what video editors such as
## DaVinci Resolve, Premiere and VLC read). MALLET writes it itself from the rendered frames so the video holds only
## the shot, at its true size.
##   var a := AviWriter.new(); a.open(path, w, h, fps); a.add_jpeg(bytes)...; a.close()

var _f: FileAccess
var _w := 0
var _h := 0
var _fps := 60
var _frames := 0
var _index := PackedByteArray()
var _movi_at := 0                            ## file offset of the "movi" list's size field
var _avih_frames_at := 0
var _strh_len_at := 0
var _max_frame := 0


func open(path: String, width: int, height: int, fps: int) -> bool:
	_f = FileAccess.open(path, FileAccess.WRITE)
	if _f == null:
		return false
	_w = width
	_h = height
	_fps = maxi(fps, 1)
	_f.store_buffer("RIFF".to_ascii_buffer())
	_f.store_32(0)                                       # (whole file size: filled in by close)
	_f.store_buffer("AVI ".to_ascii_buffer())
	_f.store_buffer("LIST".to_ascii_buffer())
	_f.store_32(4 + 8 + 56 + 8 + 4 + 8 + 56 + 8 + 40)
	_f.store_buffer("hdrl".to_ascii_buffer())
	_f.store_buffer("avih".to_ascii_buffer())
	_f.store_32(56)
	_f.store_32(1000000 / _fps)                          # microseconds per frame
	_f.store_32(0)                                       # max bytes per second (filled in)
	_f.store_32(0)
	_f.store_32(0x10)                                    # AVIF_HASINDEX
	_avih_frames_at = _f.get_position()
	_f.store_32(0)                                       # total frames (filled in)
	_f.store_32(0)
	_f.store_32(1)                                       # streams
	_f.store_32(0)                                       # suggested buffer size (filled in)
	_f.store_32(_w)
	_f.store_32(_h)
	for i in 4:
		_f.store_32(0)
	_f.store_buffer("LIST".to_ascii_buffer())
	_f.store_32(4 + 8 + 56 + 8 + 40)
	_f.store_buffer("strl".to_ascii_buffer())
	_f.store_buffer("strh".to_ascii_buffer())
	_f.store_32(56)
	_f.store_buffer("vids".to_ascii_buffer())
	_f.store_buffer("MJPG".to_ascii_buffer())
	_f.store_32(0)                                       # flags
	_f.store_16(0)                                       # priority
	_f.store_16(0)                                       # language
	_f.store_32(0)                                       # initial frames
	_f.store_32(1)                                       # scale
	_f.store_32(_fps)                                    # rate (frames per second = rate / scale)
	_f.store_32(0)                                       # start
	_strh_len_at = _f.get_position()
	_f.store_32(0)                                       # length in frames (filled in)
	_f.store_32(0)                                       # suggested buffer size
	_f.store_32(0xFFFFFFFF)                              # quality: default
	_f.store_32(0)                                       # sample size
	_f.store_16(0)
	_f.store_16(0)
	_f.store_16(_w)
	_f.store_16(_h)
	_f.store_buffer("strf".to_ascii_buffer())
	_f.store_32(40)                                      # BITMAPINFOHEADER
	_f.store_32(40)
	_f.store_32(_w)
	_f.store_32(_h)
	_f.store_16(1)
	_f.store_16(24)
	_f.store_buffer("MJPG".to_ascii_buffer())
	_f.store_32(_w * _h * 3)
	for i in 4:
		_f.store_32(0)
	_f.store_buffer("LIST".to_ascii_buffer())
	_movi_at = _f.get_position()
	_f.store_32(0)                                       # (movi size: filled in)
	_f.store_buffer("movi".to_ascii_buffer())
	return true


func add_jpeg(jpeg: PackedByteArray) -> void:
	var offset := _f.get_position() - (_movi_at + 4)     # (index offsets count from the "movi" tag)
	_f.store_buffer("00dc".to_ascii_buffer())
	_f.store_32(jpeg.size())
	_f.store_buffer(jpeg)
	if jpeg.size() % 2 == 1:
		_f.store_8(0)                                    # (chunks are word aligned)
	var e := PackedByteArray()
	e.resize(16)
	e.encode_u32(0, 0x63643030)                          # "00dc"
	e.encode_u32(4, 0x10)                                # AVIIF_KEYFRAME
	e.encode_u32(8, offset)
	e.encode_u32(12, jpeg.size())
	_index.append_array(e)
	_frames += 1
	_max_frame = maxi(_max_frame, jpeg.size())


func add_image(img: Image, quality := 0.95) -> void:
	add_jpeg(img.save_jpg_to_buffer(quality))


func frame_count() -> int:
	return _frames


func close() -> void:
	if _f == null:
		return
	var movi_end := _f.get_position()
	_f.store_buffer("idx1".to_ascii_buffer())
	_f.store_32(_index.size())
	_f.store_buffer(_index)
	var end := _f.get_position()
	_f.seek(4)
	_f.store_32(end - 8)
	_f.seek(_movi_at)
	_f.store_32(movi_end - _movi_at - 4)
	_f.seek(_avih_frames_at - 12)                        # (max bytes per second, then total frames)
	_f.store_32(_max_frame * _fps)
	_f.seek(_avih_frames_at)
	_f.store_32(_frames)
	_f.seek(_avih_frames_at + 12)
	_f.store_32(_max_frame)
	_f.seek(_strh_len_at)
	_f.store_32(_frames)
	_f.store_32(_max_frame)
	_f.close()
	_f = null


## Where each video frame's data is in an .avi: [[offset, size], ...] in order (Godot's "00db" chunks or "00dc").
static func video_chunks(path: String) -> Array:
	var out := []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var head := f.get_buffer(mini(f.get_length(), 65536))
	var movi := -1
	for i in head.size() - 4:
		if head[i] == 0x6D and head[i + 1] == 0x6F and head[i + 2] == 0x76 and head[i + 3] == 0x69:   # "movi"
			movi = i
			break
	if movi < 0:
		return out
	var p := movi + 4
	var length := f.get_length()
	while p + 8 <= length:
		f.seek(p)
		var id := f.get_buffer(4).get_string_from_ascii()
		var sz := f.get_32()
		if id == "idx1" or sz > length:
			break
		if id == "00db" or id == "00dc":
			out.append([p + 8, sz])
		p += 8 + sz + (sz & 1)
	f.close()
	return out


## A .avi's frame size, rate and count, from its header and index (for checks).
static func info(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var b := f.get_buffer(f.get_length())
	f.close()
	if b.size() < 200 or b.slice(0, 4).get_string_from_ascii() != "RIFF" or b.slice(8, 12).get_string_from_ascii() != "AVI ":
		return {}
	var frames := 0
	var idx := -1
	for i in range(b.size() - 8, 11, -1):              # (the index is the last chunk)
		if b[i] == 0x69 and b[i + 1] == 0x64 and b[i + 2] == 0x78 and b[i + 3] == 0x31:
			idx = i
			break
	if idx >= 0:
		frames = b.decode_u32(idx + 4) / 16
	return {"width": b.decode_u32(64), "height": b.decode_u32(68), "frames_header": b.decode_u32(48),
		"fps": 1000000.0 / maxf(b.decode_u32(32), 1), "frames_index": frames, "rate": b.decode_u32(132)}
