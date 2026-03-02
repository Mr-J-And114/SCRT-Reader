@tool
class_name AgentModelUtils
extends RefCounted

class ToolCallsInfo:
	var id: String = ""
	var function: ToolCallsInfoFunc = ToolCallsInfoFunc.new()
	var type: String = "function"
	# Gemini 工具调用要求在后续回传 functionCall 时携带 thought_signature
	var thought_signature: String = ""
	func to_dict():
		return {
			"id": id,
			"type": type,
			"thought_signature": thought_signature,
			"function": function.to_dict()
		}

class ToolCallsInfoFunc:
	var name: String = ""
	var arguments: String = ""

	func to_dict():
		return {
			"name": name,
			"arguments": arguments
		}

static func get_proxy_config() -> Dictionary:
	var host := ""
	var port := 0
	var enabled := false

	if AlphaAgentPlugin.global_setting != null:
		host = str(AlphaAgentPlugin.global_setting.http_proxy_host).strip_edges()
		var port_text = str(AlphaAgentPlugin.global_setting.http_proxy_port).strip_edges()
		if not port_text.is_empty() and port_text.is_valid_int():
			port = int(port_text)

	enabled = not host.is_empty() and port > 0 and port <= 65535
	return {
		"enabled": enabled,
		"host": host,
		"port": port
	}

static func apply_proxy_to_http_client(client: HTTPClient) -> void:
	if client == null:
		return

	var proxy = get_proxy_config()
	if proxy.get("enabled", false):
		var host = str(proxy.get("host", ""))
		var port = int(proxy.get("port", 0))
		client.set_http_proxy(host, port)
		client.set_https_proxy(host, port)
	else:
		client.set_http_proxy("", 0)
		client.set_https_proxy("", 0)

static func apply_proxy_to_http_request(request_node: HTTPRequest) -> void:
	if request_node == null:
		return

	var proxy = get_proxy_config()
	if proxy.get("enabled", false):
		var host = str(proxy.get("host", ""))
		var port = int(proxy.get("port", 0))
		request_node.set_http_proxy(host, port)
		request_node.set_https_proxy(host, port)
	else:
		request_node.set_http_proxy("", 0)
		request_node.set_https_proxy("", 0)
