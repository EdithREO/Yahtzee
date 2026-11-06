extends SceneTree

const PORT = 18766
const GRACE_MS = 120000
var server := TCPServer.new()
var peers := {}
var rooms := {}
var next_id := 1
var crypto := Crypto.new()

func _initialize():
	if server.listen(PORT, "127.0.0.1") != OK:
		printerr("Cannot listen on port ", PORT)
		quit(1)
	else:
		print("Room server listening on 127.0.0.1:", PORT)

func _process(_delta):
	while server.is_connection_available():
		var stream := server.take_connection()
		if peers.size() >= 100:
			stream.disconnect_from_host()
			continue
		var ws := WebSocketPeer.new()
		ws.heartbeat_interval = 3.0
		ws.inbound_buffer_size = 8192
		ws.max_queued_packets = 32
		if ws.accept_stream(stream) == OK:
			peers[next_id] = {"ws": ws, "room": "", "seat": -1, "since": Time.get_ticks_msec(), "window": Time.get_ticks_msec(), "requests": 0}
			next_id += 1
	for id in peers.keys():
		if not peers.has(id): continue
		var p: Dictionary = peers[id]
		var ws: WebSocketPeer = p.ws
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			while ws.get_available_packet_count() > 0:
				var packet := ws.get_packet()
				if not ws.was_string_packet() or packet.size() > 2048:
					ws.close(1008, "Invalid packet")
					break
				_handle(id, packet.get_string_from_utf8())
		elif ws.get_ready_state() == WebSocketPeer.STATE_CLOSED or (ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING and Time.get_ticks_msec() - p.since > 10000):
			_disconnect(id)
	var now := Time.get_ticks_msec()
	for code in rooms.keys():
		var r: Dictionary = rooms[code]
		for seat in range(2):
			var s = r.seats[seat]
			if s != null and s.peer == 0 and now - s.disconnected > GRACE_MS:
				r.seats[seat] = null
				if seat == 0 or r.started:
					_close_room(code,"玩家离线超时，房间已关闭。")
					break
				_broadcast(code)
	return false

func _send(id, data):
	if peers.has(id):
		var ws: WebSocketPeer = peers[id].ws
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			if ws.send_text(JSON.stringify(data)) != OK:
				ws.close(1013,"Slow consumer; reconnect")

func _error(id, message):
	_send(id, {"type":"error", "message":message})

func _broadcast(code):
	if not rooms.has(code): return
	var r: Dictionary = rooms[code]
	var online := []
	for s in r.seats: online.append(s != null and s.peer != 0)
	var msg = {"type":"state", "code":code, "online":online, "started":r.started}
	msg["game"] = r.game.snapshot() if r.has("game") else null
	msg["restart"] = r.get("restart",null)
	for s in r.seats:
		if s != null and s.peer != 0: _send(s.peer, msg)

func _handle(id, raw):
	var p: Dictionary = peers[id]
	var now := Time.get_ticks_msec()
	if now - p.window > 10000:
		p.window = now
		p.requests = 0
	p.requests += 1
	if p.requests > 30:
		p.ws.close(1008, "Rate limit")
		return
	var d = JSON.parse_string(raw)
	if not d is Dictionary or not d.get("type") is String:
		_error(id, "请求格式错误。")
		return
	var kind: String = d.type
	if kind == "ping":
		if d.get("client_ms") is float or d.get("client_ms") is int:
			_send(id,{"type":"pong","client_ms":d.client_ms,"server_ms":Time.get_ticks_msec()})
		return
	if kind == "create" or kind == "join" or kind == "resume":
		if p.room != "":
			_error(id, "您已经在房间中。")
			return
		if kind == "create":
			if rooms.size() >= 200:
				_error(id, "房间数量已达上限。")
				return
			var code := ""
			for i in range(100):
				var bytes := crypto.generate_random_bytes(4)
				if bytes.size() != 4: break
				var number := bytes.decode_u32(0)
				if number >= 4294000000: continue
				code = "%06d" % (number % 1000000)
				if not rooms.has(code): break
				code = ""
			if code == "":
				_error(id, "无法创建房间，请重试。")
				return
			rooms[code] = {"seats":[null,null], "started":false}
			_assign(id, code, 0)
			return
		var code = d.get("code", "")
		if not code is String or code.length() != 6 or not code.is_valid_int() or not rooms.has(code):
			_error(id, "房间码无效或房间不存在。")
			return
		var r: Dictionary = rooms[code]
		if kind == "resume":
			var token = d.get("token", "")
			if not token is String or token.length() != 64:
				_error(id, "恢复失败，请重新加入。")
				return
			for seat in range(2):
				var s = r.seats[seat]
				if s != null and s.token == token:
					if s.peer != 0:
						var old_peer: int = s.peer
						_send(old_peer,{"type":"ended","message":"该座位已在新连接恢复。"})
						if peers.has(old_peer):
							peers[old_peer].room = ""
							peers[old_peer].seat = -1
							peers[old_peer].ws.close(1000,"Session resumed")
					s.peer = id
					p.room = code
					p.seat = seat
					_send(id, {"type":"joined", "code":code, "seat":seat, "token":token,"last_request":s.get("last_request",0)})
					_broadcast(code)
					_replay(id,code)
					return
			_error(id, "会话已过期，请重新加入。")
			return
		if r.started:
			_error(id, "游戏已经开始。")
		elif r.seats[1] != null:
			_error(id, "房间已满。")
		else:
			_assign(id, code, 1)
		return
	if p.room == "" or not rooms.has(p.room):
		_error(id, "请先进入房间。")
		return
	var r: Dictionary = rooms[p.room]
	if kind in ["restart_request","restart_reply"]:
		_restart_action(id,d)
		return
	if kind == "playback_metrics":
		if d.get("roll_id", "") != r.get("active_roll", ""): return
		var playhead = d.get("playhead_ms")
		var rtt = d.get("rtt_ms")
		if not (playhead is float or playhead is int) or not (rtt is float or rtt is int): return
		if not is_finite(float(playhead)) or not is_finite(float(rtt)): return
		if not r.has("client_metrics"): r.client_metrics = {}
		r.client_metrics[p.seat] = {"head":playhead,"at":Time.get_ticks_msec(),"rtt":clampf(float(rtt),0,10000)}
		if r.client_metrics.has(0) and r.client_metrics.has(1):
			var a: Dictionary = r.client_metrics[0]
			var b: Dictionary = r.client_metrics[1]
			var diff = absf((a.head-a.at)-(b.head-b.at))
			for s in r.seats:
				if s != null and s.peer != 0: _send(s.peer,{"type":"sync_metrics","difference_estimate_ms":diff,"rtt_bound_ms":(a.rtt+b.rtt)/2.0})
		return
	if kind in ["select_skill","use_d4","use_blackout","use_biohazard","use_rescue","set_rescue_discard","roll","hold","commit_score"]:
		_game_action(id,d)
	elif kind == "start":
		if p.seat != 0: _error(id, "只有房主可以开始。")
		elif r.started: _error(id, "游戏已经开始。")
		elif r.seats[1] == null or r.seats[1].peer == 0: _error(id, "需要两名玩家在线。")
		else:
			var random := crypto.generate_random_bytes(1)
			if random.is_empty():
				_error(id,"无法选择先手，请重试。")
				return
			r.game = load("res://room/match_state.gd").new(int(random[0])%2)
			_ensure_physics(p.room)
			r.physics.reset_turn()
			r.started = true
			_broadcast(p.room)
			_broadcast_board(p.room)
	elif kind == "test":
		if not r.started: _error(id, "游戏尚未开始。")
		else:
			for s in r.seats:
				if s != null and s.peer != 0: _send(s.peer, {"type":"test", "seat":p.seat})
	elif kind == "leave":
		_leave(id)
	else:
		_error(id, "未知操作。")

func _assign(id, code, seat):
	var token := crypto.generate_random_bytes(32).hex_encode()
	if token.length() != 64:
		_error(id, "无法创建会话。")
		if seat == 0: _remove_room(code)
		return
	rooms[code].seats[seat] = {"token":token, "peer":id, "disconnected":0,"last_request":0}
	peers[id].room = code
	peers[id].seat = seat
	_send(id, {"type":"joined", "code":code, "seat":seat, "token":token})
	_broadcast(code)

func _disconnect(id):
	var p: Dictionary = peers[id]
	if p.room != "" and rooms.has(p.room):
		var s = rooms[p.room].seats[p.seat]
		if s != null and s.peer == id:
			s.peer = 0
			s.disconnected = Time.get_ticks_msec()
			_broadcast(p.room)
	peers.erase(id)

func _leave(id):
	var p: Dictionary = peers[id]
	var code: String = p.room
	if rooms[code].started:
		_close_room(code,"玩家主动退出，对局已关闭。")
		return
	var seat: int = p.seat
	p.room = ""
	p.seat = -1
	rooms[code].seats[seat] = null
	_send(id, {"type":"left"})
	if seat == 0:
		var other = rooms[code].seats[1]
		if other != null and other.peer != 0:
			_send(other.peer, {"type":"ended", "message":"房主已退出，房间已关闭。"})
			peers[other.peer].room = ""
		_remove_room(code)
	else:
		_broadcast(code)

func _physics_completed(result: Dictionary, code: String):
	if not rooms.has(code): return
	rooms[code].game.finish_roll(result)
	rooms[code].last_roll = result
	result["trajectory_payload_bytes_both"] = rooms[code].get("tx_bytes",0)
	for s in rooms[code].seats:
		if s != null and s.peer != 0: _send(s.peer, {"type":"roll_result", "result":result})
	_broadcast(code)
	if not result.ok: _broadcast_board(code)
	print("ROLL_METRICS ",JSON.stringify({"roll_id":result.roll_id,"duration":result.duration,"physics_frame_ms_mean":result.physics_frame_ms_mean,"physics_frame_ms_max":result.physics_frame_ms_max,"trajectory_payload_bytes_both":result.trajectory_payload_bytes_both}))

func _physics_sampled(state: Dictionary, code: String):
	if not rooms.has(code): return
	rooms[code].latest_state = state
	var msg := {"type":"roll_state","state":state}
	var bytes := JSON.stringify(msg).to_utf8_buffer().size()
	for s in rooms[code].seats:
		if s != null and s.peer != 0:
			_send(s.peer,msg)
			rooms[code].tx_bytes = rooms[code].get("tx_bytes",0)+bytes

func _replay(id: int, code: String):
	var r: Dictionary = rooms[code]
	if r.has("physics") and r.physics.busy:
		_send(id,{"type":"roll_started","roll_id":r.physics.roll_id,"server_ms":Time.get_ticks_msec()})
		if r.has("latest_state") and r.latest_state.roll_id == r.physics.roll_id:
			_send(id,{"type":"roll_state","state":r.latest_state})
	elif r.has("last_roll"):
		_send(id,{"type":"roll_result","result":r.last_roll})
		if not r.last_roll.ok:
			_send(id,{"type":"board_state","state":r.physics.board_state(r.game.turn_id)})
	elif r.has("game"):
		_send(id,{"type":"board_state","state":r.physics.board_state(r.game.turn_id)})

func _remove_room(code: String):
	if rooms.has(code) and rooms[code].has("physics_view"):
		rooms[code].physics_view.queue_free()
	rooms.erase(code)

func _ensure_physics(code: String):
	var r: Dictionary = rooms[code]
	if r.has("physics"):
		r.physics.turn_skills = r.game.skills
		return
	var view := SubViewport.new()
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(view)
	var world = load("res://room/physics_world.gd").new()
	world.turn_skills = r.game.skills
	view.add_child(world)
	r.physics = world
	r.physics_view = view
	world.completed.connect(_physics_completed.bind(code))
	world.sampled.connect(_physics_sampled.bind(code))

func _integer(value, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(float(value)) and value >= low and value <= high

func _game_action(id: int, d: Dictionary):
	var p: Dictionary = peers[id]
	var r: Dictionary = rooms[p.room]
	if not r.started or not r.has("game"):
		_error(id,"游戏尚未开始。")
		return
	var allowed := ["type","request_id","turn_id"]
	if d.type == "select_skill": allowed.append("skill_id")
	if d.type == "use_d4": allowed.append("indices")
	if d.type in ["use_biohazard", "use_rescue", "set_rescue_discard"]: allowed.append("index")
	if d.type == "hold": allowed.append_array(["index","held"])
	if d.type == "commit_score": allowed.append("category")
	if d.size() != allowed.size() or not _integer(d.get("request_id"),1,9007199254740991) or not _integer(d.get("turn_id"),1,100000):
		_error(id,"操作请求格式无效。")
		return
	for key in d:
		if not allowed.has(key):
			_error(id,"不接受客户端点数或额外参数。")
			return
	if d.type == "select_skill" and not d.get("skill_id") is String:
		_error(id,"技能请求无效。")
		return
	if d.type == "use_d4":
		var indices = d.get("indices")
		if not indices is Array or indices.size() != 2 or not _integer(indices[0],0,4) or not _integer(indices[1],0,4):
			_error(id,"请选择两颗骰子。")
			return
		d.indices = [int(indices[0]),int(indices[1])]
	if d.type == "hold" and (not _integer(d.get("index"),0,4) or not d.get("held") is bool):
		_error(id,"保留请求无效。")
		return
	if d.type == "use_biohazard" and not _integer(d.get("index"),0,4):
		_error(id,"母体骰子无效。")
		return
	if d.type == "use_rescue" and not _integer(d.get("index"),0,4):
		_error(id,"要记录的骰子无效。")
		return
	if d.type == "set_rescue_discard" and not _integer(d.get("index"),0,5):
		_error(id,"不计分的骰子无效。")
		return
	if d.type == "commit_score" and not _integer(d.get("category"),0,11):
		_error(id,"计分项目无效。")
		return
	var seat: Dictionary = r.seats[p.seat]
	if int(d.request_id) <= seat.get("last_request",0):
		_error(id,"重复或过期请求已拒绝。")
		return
	seat.last_request = int(d.request_id)
	for member in r.seats:
		if member == null or member.peer == 0:
			_error(id,"对方已离线，等待重连后继续。")
			return
	if r.has("restart"):
		_error(id,"请先完成重新开始确认。")
		return
	var had_biohazard: bool = d.type == "commit_score" and r.game.skills.biohazard_snapshot().mother >= 0
	var error: String = r.game.operate(d.type,p.seat,d)
	if error != "":
		_error(id,error)
		return
	if d.type in ["select_skill", "use_blackout", "use_rescue", "set_rescue_discard"]:
		_broadcast(p.room)
		_send(id,{"type":"ack","request_id":d.request_id})
		return
	if d.type in ["use_d4", "use_biohazard"]:
		if d.type == "use_d4":
			r.physics.activate_d4(r.game.skills.d4_dice())
		else:
			r.physics.dice[int(d.index)].max_contacts_reported = 16
		r.erase("last_roll")
		r.erase("latest_state")
		r.erase("active_roll")
		_broadcast_board(p.room)
	elif d.type == "roll":
		if not r.physics.request_roll(r.game.held):
			r.game.busy = false
			r.game.rolls -= 1
			_error(id,"物理投掷尚未结束。")
			return
		r.active_roll = r.physics.roll_id
		r.tx_bytes = 0
		r.client_metrics = {}
		for member in r.seats:
			_send(member.peer,{"type":"roll_started","roll_id":r.active_roll,"server_ms":Time.get_ticks_msec(),"actor":p.seat})
	elif d.type == "hold":
		r.physics.set_held(int(d.index),d.held)
		if r.has("last_roll") and r.last_roll.ok:
			var current_poses: Array = r.physics.board_state(r.game.turn_id).dice
			for i in range(5):
				r.last_roll.dice[i].position = current_poses[i].position
				r.last_roll.dice[i].rotation = current_poses[i].rotation
		var message := {"type":"board_state","state":r.physics.board_state(r.game.turn_id),"animate":true,"index":d.index}
		for member in r.seats: _send(member.peer,message)
	elif d.type == "commit_score" and not r.game.over:
		r.erase("last_roll")
		r.erase("latest_state")
		r.erase("active_roll")
		r.physics.reset_turn()
		_broadcast_board(p.room)
	elif d.type == "commit_score" and (r.physics.clear_d4() or had_biohazard):
		r.erase("last_roll")
		r.erase("latest_state")
		r.erase("active_roll")
		_broadcast_board(p.room)
	_send(id,{"type":"ack","request_id":d.request_id})
	_broadcast(p.room)

func _broadcast_board(code: String):
	var r: Dictionary = rooms[code]
	var message := {"type":"board_state","state":r.physics.board_state(r.game.turn_id)}
	for member in r.seats:
		if member != null and member.peer != 0: _send(member.peer,message)

func _close_room(code: String, message: String):
	for member in rooms[code].seats:
		if member != null and member.peer != 0 and peers.has(member.peer):
			_send(member.peer,{"type":"ended","message":message})
			peers[member.peer].room = ""
			peers[member.peer].seat = -1
	_remove_room(code)

func _restart_action(id: int,d: Dictionary):
	var p: Dictionary = peers[id]
	var r: Dictionary = rooms[p.room]
	if not r.has("game") or r.game.busy:
		_error(id,"请在骰子停止后请求重开。")
		return
	if not r.game.skills.is_ready():
		_error(id,"请等待两位玩家选好技能。")
		return
	if not _integer(d.get("request_id"),1,9007199254740991) or not _integer(d.get("turn_id"),1,100000):
		_error(id,"请求格式无效。")
		return
	var member: Dictionary = r.seats[p.seat]
	if d.request_id <= member.last_request or int(d.turn_id) != r.game.turn_id:
		_error(id,"重复或过期请求。")
		return
	member.last_request = int(d.request_id)
	for s in r.seats:
		if s == null or s.peer == 0:
			_error(id,"需要双方在线。")
			return
	if d.type == "restart_request":
		if r.has("restart"):
			_error(id,"已有请求等待确认。")
			return
		r.restart = p.seat
	else:
		if not r.has("restart") or r.restart == p.seat or not d.get("accept") is bool:
			_error(id,"只能由对方同意或拒绝。")
			return
		if d.accept:
			var next_turn: int = r.game.turn_id+1
			r.game = load("res://room/match_state.gd").new(int(crypto.generate_random_bytes(1)[0])%2)
			r.game.turn_id = next_turn
			_ensure_physics(p.room)
			r.physics.reset_turn()
			for key in ["last_roll","latest_state","active_roll"]: r.erase(key)
			_broadcast_board(p.room)
		r.erase("restart")
	_send(id,{"type":"ack","request_id":d.request_id})
	_broadcast(p.room)
