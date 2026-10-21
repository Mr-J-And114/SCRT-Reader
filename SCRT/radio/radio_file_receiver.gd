class_name RadioFileReceiver
extends RefCounted
## 接收模拟只推进数据块；真正落盘前仍校验分段、整包并走 Vdisc 的安装链路。
const MAX_PACKAGE_BYTES: int = 32 * 1024 * 1024
var main = null
var receipts: Dictionary = {}
var active_signal: RadioConfigParser.RadioSignal = null
var status: String = "等待文件信号。"
var _owner_dir: String = ""
var _block_timer: float = 0.0
var _cursor: int = 0

func setup(p_main) -> void:
	main = p_main

static func sha256(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	if not bytes.is_empty(): ctx.update(bytes)
	return ctx.finish().hex_encode()

static func safe_name(value: String) -> bool:
	return not value.is_empty() and value == value.get_file() and not value.contains("..") and not value.contains(":") and not value.contains("\\") and not value.contains("/")

func get_storage_dir() -> String:
	if main == null or main.user_mgr == null or not main.user_mgr.is_logged_in or main.save_mgr == null:
		return ""
	return main.save_mgr.get_game_root_dir().path_join("saves").path_join(main.user_mgr.get_username()).path_join("radio")

func bind_player() -> void:
	var dir: String = get_storage_dir()
	if dir == _owner_dir:
		return
	active_signal = null
	receipts = {}
	_owner_dir = dir
	status = "等待文件信号。"
	if dir.is_empty():
		return
	var path: String = dir.path_join("receipts.json")
	# 写入中断时只恢复同一玩家目录中的备份。
	if not FileAccess.file_exists(path) and FileAccess.file_exists(path + ".bak"):
		DirAccess.rename_absolute(path + ".bak", path)
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null and file.get_length() <= MAX_PACKAGE_BYTES * 2:
			var data = JSON.parse_string(file.get_as_text())
			if data is Dictionary:
				receipts = data
				_sanitize_receipts()

func _sanitize_receipts() -> void:
	# 未完成存档也验证每个块；损坏的块可重新接收，不把旧 complete 当作事实。
	for id in receipts.keys():
		if not receipts[id] is Dictionary:
			receipts.erase(id)
			continue
		var receipt: Dictionary = receipts[id]
		if not receipt.get("parts", {}) is Dictionary:
			receipts.erase(id)
			continue
		for key in receipt.get("parts", {}).keys():
			var parts: Dictionary = receipt.parts
			if not parts[key] is Dictionary:
				parts.erase(key)
				continue
			var part: Dictionary = parts[key]
			if not part.get("blocks", {}) is Dictionary:
				parts.erase(key)
				continue
			for block_key in part.get("blocks", {}).keys():
				var block = part.blocks[block_key]
				if not block is Dictionary or sha256(Marshalls.base64_to_raw(str(block.get("data", "")))) != str(block.get("sha256", "")):
					part.blocks.erase(block_key)
			part["complete"] = not _assemble_part(part).is_empty()

static func atomic_write(path: String, bytes: PackedByteArray) -> bool:
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return false
	var temp: String = path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(temp)
		return false
	var backup: String = path + ".bak"
	if FileAccess.file_exists(backup):
		if DirAccess.remove_absolute(backup) != OK:
			return false
	var existed: bool = FileAccess.file_exists(path)
	if existed and DirAccess.rename_absolute(path, backup) != OK:
		return false
	if DirAccess.rename_absolute(temp, path) != OK:
		if existed: DirAccess.rename_absolute(backup, path)
		return false
	if existed: DirAccess.remove_absolute(backup)
	return true

func _save() -> bool:
	return not _owner_dir.is_empty() and atomic_write(_owner_dir.path_join("receipts.json"), JSON.stringify(receipts).to_utf8_buffer())

func _validate(sig: RadioConfigParser.RadioSignal) -> String:
	if sig == null or sig.type != "data" or sig.content_data.is_empty():
		return "该信号没有可接收的文件数据。"
	var meta: Dictionary = sig.transfer
	var id: String = str(meta.get("id", ""))
	var filename: String = str(meta.get("filename", ""))
	var count: int = int(meta.get("part_count", 0))
	var index: int = int(meta.get("part_index", 0))
	var size: int = int(meta.get("total_bytes", 0))
	if not safe_name(id) or not safe_name(filename) or filename.get_extension().to_lower() != "scp":
		return "文件传输标识或文件名无效。"
	if count < 1 or count > 32 or index < 1 or index > count or size < 4 or size > MAX_PACKAGE_BYTES or sig.content_data.size() > size:
		return "文件分段范围无效。"
	if str(meta.get("package_sha256", "")).length() != 64 or sha256(sig.content_data) != str(meta.get("part_sha256", "")):
		return "电台分段校验失败，请检查信号配置与源文件。"
	var mgr = main.vdisc_task_mgr
	var task_id: String = str(meta.get("task_id", ""))
	if mgr == null or not mgr.definitions.has(task_id):
		return "该文件没有对应的 Vdisc 任务配置。"
	var download: Dictionary = mgr.definitions[task_id].get("download", {})
	if str(download.get("filename", "")) != filename or str(download.get("radio_transfer_id", "")) != id:
		return "电台文件与任务接收配置不一致。"
	return ""

func begin(sig: RadioConfigParser.RadioSignal) -> bool:
	bind_player()
	if _owner_dir.is_empty():
		status = "请先登录。"
		return false
	var error: String = _validate(sig)
	if not error.is_empty():
		status = "[ERROR] " + error
		return false
	var meta: Dictionary = sig.transfer
	var id: String = str(meta.id)
	if not receipts.has(id):
		receipts[id] = {"filename": str(meta.filename), "task_id": str(meta.task_id), "part_count": int(meta.part_count), "total_bytes": int(meta.total_bytes), "package_sha256": str(meta.package_sha256), "parts": {}}
	var receipt: Dictionary = receipts[id]
	for field in ["filename", "task_id", "package_sha256"]:
		if str(receipt.get(field, "")) != str(meta.get(field, "")):
			status = "[ERROR] 同名传输的版本或分段配置发生冲突，未覆盖已有进度。"
			return false
	for field in ["part_count", "total_bytes"]:
		if int(receipt.get(field, 0)) != int(meta.get(field, 0)):
			status = "[ERROR] 同名传输的版本或分段配置发生冲突，未覆盖已有进度。"
			return false
	var parts: Dictionary = receipt.get("parts", {})
	for required in meta.get("requires_parts", []):
		if not parts.has(str(int(required))) or not bool(parts[str(int(required))].get("complete", false)):
			status = "[INFO] 请先接收第 %d 段。" % int(required)
			return false
	var part_key: String = str(int(meta.part_index))
	var block_size: int = clampi(int(meta.get("block_size", 4096)), 64, 65536)
	if parts.has(part_key):
		var part: Dictionary = parts[part_key]
		if str(part.get("sha256", "")) != str(meta.part_sha256) or int(part.get("size", 0)) != sig.content_data.size() or int(part.get("block_size", 0)) != block_size:
			status = "[ERROR] 该分段与已经保存的版本不一致。"
			return false
	else:
		parts[part_key] = {"size": sig.content_data.size(), "sha256": str(meta.part_sha256), "block_size": block_size, "blocks": {}, "complete": false}
		receipt["parts"] = parts
	if not _save():
		status = "[ERROR] 无法保存接收进度。"
		return false
	active_signal = sig
	_block_timer = 0.0
	_cursor = 0
	status = "[BUSY] 正在接收第 %d / %d 段。" % [int(meta.part_index), int(meta.part_count)]
	if _all_parts_complete(receipt):
		_commit(id)
	elif bool(parts[part_key].get("complete", false)):
		pause("[OK] 本台分段已接收。" + str(meta.get("next_hint", "请寻找其他发送电台。")))
	return true

func pause(message: String = "[PAUSED] 接收暂停，已收到的数据块保留。") -> void:
	active_signal = null
	status = message

func process(delta: float, sig: RadioConfigParser.RadioSignal, quality: float, locked: bool) -> void:
	bind_player()
	if active_signal == null:
		return
	if sig == null or sig.id != active_signal.id:
		pause()
		return
	if not locked or quality < 0.5:
		status = "[PAUSED] 信号不足，等待恢复；已收数据保留。"
		return
	_block_timer += delta
	var interval: float = clampf(float(active_signal.transfer.get("block_interval", 0.25)), 0.05, 5.0)
	if _block_timer < interval:
		return
	_block_timer = fmod(_block_timer, interval)
	var meta: Dictionary = active_signal.transfer
	var receipt: Dictionary = receipts[str(meta.id)]
	var part: Dictionary = receipt.parts[str(int(meta.part_index))]
	var block_size: int = int(part.block_size)
	var count: int = ceili(float(part.size) / block_size)
	# 每次循环只处理一个广播块；弱信号缺块在下一轮补齐。
	var block_index: int = _cursor % count
	_cursor += 1
	if not part.blocks.has(str(block_index)):
		if quality < 0.7 and randf() > quality:
			status = "[WARN] 数据块校验未通过，等待循环广播补齐。"
			return
		var bytes: PackedByteArray = active_signal.content_data.slice(block_index * block_size, mini((block_index + 1) * block_size, int(part.size)))
		part.blocks[str(block_index)] = {"data": Marshalls.raw_to_base64(bytes), "sha256": sha256(bytes)}
		if not _save():
			part.blocks.erase(str(block_index))
			pause("[ERROR] 接收进度保存失败，请检查磁盘后重试。")
			return
	status = "[BUSY] 接收第 %d / %d 段 | 数据块 %d / %d" % [int(meta.part_index), int(meta.part_count), part.blocks.size(), count]
	if part.blocks.size() == count:
		var result: PackedByteArray = _assemble_part(part)
		if result.is_empty():
			part.blocks.clear()
			part.complete = false
			_save()
			pause("[ERROR] 分段校验失败，请重新接收本台。")
			return
		part.complete = true
		_save()
		if _all_parts_complete(receipt):
			_commit(str(meta.id))
		else:
			pause("[OK] 第 %d 段接收完成。%s" % [int(meta.part_index), str(meta.get("next_hint", "请寻找其他发送电台。"))])

func _assemble_part(part: Dictionary) -> PackedByteArray:
	var result := PackedByteArray()
	var size: int = int(part.get("size", 0))
	var block_size: int = int(part.get("block_size", 0))
	if size <= 0 or size > MAX_PACKAGE_BYTES or block_size < 64 or block_size > 65536 or not part.get("blocks", {}) is Dictionary:
		return result
	var count: int = ceili(float(size) / block_size)
	for i in range(count):
		var block: Dictionary = part.blocks.get(str(i), {})
		var bytes: PackedByteArray = Marshalls.base64_to_raw(str(block.get("data", "")))
		if bytes.size() != mini(block_size, size - i * block_size) or sha256(bytes) != str(block.get("sha256", "")):
			return PackedByteArray()
		result.append_array(bytes)
	return result if result.size() == size and sha256(result) == str(part.get("sha256", "")) else PackedByteArray()

func assemble_package(id: String) -> PackedByteArray:
	var result := PackedByteArray()
	var receipt: Dictionary = receipts.get(id, {})
	var parts: Dictionary = receipt.get("parts", {})
	var count: int = int(receipt.get("part_count", 0))
	if count < 1 or count > 32:
		return result
	for i in range(1, count + 1):
		var part: Dictionary = parts.get(str(i), {})
		var bytes: PackedByteArray = _assemble_part(part)
		if bytes.is_empty() or result.size() + bytes.size() > MAX_PACKAGE_BYTES:
			return PackedByteArray()
		result.append_array(bytes)
	return result if result.size() == int(receipt.get("total_bytes", 0)) and sha256(result) == str(receipt.get("package_sha256", "")) else PackedByteArray()

func is_package_ready(id: String) -> bool:
	return not assemble_package(id).is_empty()

func _all_parts_complete(receipt: Dictionary) -> bool:
	var count: int = int(receipt.get("part_count", 0))
	if count < 1 or count > 32: return false
	for i in range(1, count + 1):
		if not bool(receipt.get("parts", {}).get(str(i), {}).get("complete", false)): return false
	return true

func _commit(id: String) -> void:
	var bytes: PackedByteArray = assemble_package(id)
	if bytes.is_empty():
		pause("[ERROR] 整包校验失败，未生成磁盘。")
		return
	var task_id: String = str(receipts[id].task_id)
	if main.vdisc_task_mgr.get_task_status(task_id) in ["downloaded", "submitted", "confiscated"]:
		pause("[OK] 文件已接收；已有磁盘或归档进度保留。")
		return
	var result: Dictionary = main.vdisc_task_mgr.store_download(task_id, bytes, false, id)
	pause(("[OK] " if result.get("ok", false) else "[ERROR] ") + ("文件集齐并校验通过，已保存到个人任务箱。退出 RADIO 后 scan / load 查看。" if result.get("ok", false) else str(result.get("message", "保存失败，可点击接收重试。"))))

func get_progress(sig: RadioConfigParser.RadioSignal) -> Dictionary:
	if sig == null or sig.transfer.is_empty():
		return {}
	var receipt: Dictionary = receipts.get(str(sig.transfer.get("id", "")), {})
	var parts: Dictionary = receipt.get("parts", {})
	var part: Dictionary = parts.get(str(int(sig.transfer.get("part_index", 0))), {})
	var received: int = (part.get("blocks", {}) as Dictionary).size()
	var total: int = ceili(float(part.get("size", sig.content_data.size())) / maxi(int(part.get("block_size", sig.transfer.get("block_size", 4096))), 64))
	var completed: int = 0
	for value in parts.values():
		if bool(value.get("complete", false)): completed += 1
	return {"ratio": float(received) / maxi(total, 1), "received": received, "total": total, "completed_parts": completed, "part_count": int(sig.transfer.get("part_count", 0)), "complete": bool(part.get("complete", false))}

func save_sstv(png: PackedByteArray, signal_id: String) -> Dictionary:
	bind_player()
	if _owner_dir.is_empty() or png.is_empty():
		return {"ok": false, "message": "请先登录并完成图片接收。"}
	var filename: String = "sstv_%s_%d.png" % [signal_id.sha256_text().left(8), Time.get_ticks_usec()]
	var path: String = _owner_dir.path_join("images").path_join(filename)
	var ok: bool = atomic_write(path, png)
	return {"ok": ok, "message": "图片已保存，可在已保存图片中查看。" if ok else "图片保存失败。", "path": path}

func get_saved_images() -> Array[String]:
	bind_player()
	var files: Array[String] = []
	if _owner_dir.is_empty(): return files
	var dir := DirAccess.open(_owner_dir.path_join("images"))
	if dir == null: return files
	for filename in dir.get_files():
		if filename.get_extension().to_lower() == "png": files.append(dir.get_current_dir().path_join(filename))
	files.sort()
	files.reverse()
	return files
