class_name RadioSpeechBuilder
extends RefCounted
## 运行期按报文字母／数字拼接已有 NATO 录音，不写入音频文件。
var _libraries: Dictionary = {}
var _programs: Dictionary = {}

static func fingerprint(sig: RadioConfigParser.RadioSignal) -> String:
	return RadioFileReceiver.sha256(JSON.stringify([sig.content_text, sig.speech_library, sig.speech_letter_gap, sig.speech_word_gap, sig.character_set, sig.group_size, sig.group_pause_ms]).to_utf8_buffer())

func build(sig: RadioConfigParser.RadioSignal, audio_manager) -> Dictionary:
	var key: String = fingerprint(sig)
	if _programs.has(key): return _programs[key]
	var library: Dictionary = _library(sig.speech_library, audio_manager)
	if library.has("error"): return library
	var events: Array[Dictionary] = []
	var ignored: int = 0
	var count: int = 0
	for character: String in sig.content_text.to_upper():
		if library.tokens.has(character):
			if not events.is_empty():
				var gap: float = sig.speech_letter_gap
				if sig.character_set == "numbers" and count % maxi(sig.group_size, 1) == 0:
					gap = maxf(gap, sig.group_pause_ms / 1000.0)
				events[-1].gap = maxf(float(events[-1].gap), gap)
			events.append({"token": character, "gap": 0.0})
			count += 1
		elif character in [" ", "\n", "\r", "\t", ".", ",", ":", ";", "-", "/"]:
			if not events.is_empty(): events[-1].gap = maxf(float(events[-1].gap), sig.speech_word_gap)
		else:
			ignored += 1
	if events.is_empty(): return {"error": "报文中没有可播报的 A–Z／0–9 字符。"}
	if events.size() > 4096: return {"error": "单轮语音报文超过 4096 个字符。"}
	var pcm := PackedByteArray()
	var starts: Array[float] = []
	var tokens: Array[String] = []
	for i in range(events.size()):
		var event: Dictionary = events[i]
		var clip: AudioStreamWAV = library.clips[library.tokens[event.token]]
		if pcm.size() + clip.data.size() + int(float(event.gap) * 96000.0) > 32 * 1024 * 1024:
			return {"error": "单轮语音超过 32MiB，请分成多条报文。"}
		starts.append(pcm.size() / 96000.0)
		tokens.append(str(event.token))
		pcm.append_array(clip.data)
		if i < events.size() - 1:
			var padding := PackedByteArray()
			padding.resize(maxi(0, roundi((float(event.gap) - float(library.tail)) * 48000.0)) * 2)
			padding.fill(0)
			pcm.append_array(padding)
	var stream := AudioStreamWAV.new()
	stream.mix_rate = 48000
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = pcm
	var program: Dictionary = {"stream": stream, "starts": starts, "tokens": tokens, "ignored": ignored, "key": key}
	if _programs.size() >= 4: _programs.erase(_programs.keys()[0])
	_programs[key] = program
	return program

func _library(directory: String, audio_manager) -> Dictionary:
	if _libraries.has(directory): return _libraries[directory]
	var manifest_path: String = directory.path_join("manifest.json")
	if not FileAccess.file_exists(manifest_path): return {"error": "NATO 词库清单不存在。"}
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary or not manifest.get("tokens") is Dictionary: return {"error": "NATO 词库清单无效。"}
	var clips: Dictionary = {}
	for token: String in manifest.tokens:
		var name: String = str(manifest.tokens[token])
		if name != name.get_file() or name.get_extension().to_lower() != "wav": return {"error": "NATO 词库文件名无效。"}
		if clips.has(name): continue
		var data: PackedByteArray = FileAccess.get_file_as_bytes(directory.path_join(name))
		var clip: AudioStreamWAV = audio_manager.load_audio_from_bytes(name, data) as AudioStreamWAV
		if clip == null or clip.mix_rate != 48000 or clip.stereo or clip.format != AudioStreamWAV.FORMAT_16_BITS:
			return {"error": "NATO 词库不是 48kHz 单声道 PCM：" + name}
		clips[name] = clip
	var library: Dictionary = {"tokens": manifest.tokens, "clips": clips, "tail": float(manifest.get("tail_seconds", 0.12))}
	if _libraries.size() >= 2: _libraries.erase(_libraries.keys()[0])
	_libraries[directory] = library
	return library
