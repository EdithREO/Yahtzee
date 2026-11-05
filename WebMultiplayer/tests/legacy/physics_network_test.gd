extends SceneTree

var a := WebSocketPeer.new()
var b := WebSocketPeer.new()
var deadline := 0
var stage := 0
var code := ""
var done := false

func _initialize():
	deadline = Time.get_ticks_msec() + 150000
	a.connect_to_url("ws://127.0.0.1:18766/ws")
	b.connect_to_url("ws://127.0.0.1:18766/ws")

func _process(_delta):
	a.poll()
	b.poll()
	if stage == 0 and a.get_ready_state() == WebSocketPeer.STATE_OPEN and b.get_ready_state() == WebSocketPeer.STATE_OPEN:
		a.send_text('{"type":"create"}')
		stage = 1
	for peer in [a,b]:
		while peer.get_available_packet_count() > 0:
			var d = JSON.parse_string(peer.get_packet().get_string_from_utf8())
			if d.type == "error":
				printerr(d.message)
				quit(1)
			if stage == 1 and peer == a and d.type == "joined":
				code = d.code
				b.send_text(JSON.stringify({"type":"join","code":code}))
				stage = 2
			elif stage == 2 and peer == a and d.type == "state" and d.online == [true,true]:
				a.send_text('{"type":"start"}')
				stage = 3
			elif stage == 3 and peer == a and d.type == "state" and d.started:
				var actor := a if d.game.current_player == 0 else b
				actor.send_text(JSON.stringify({"type":"roll","request_id":1,"turn_id":d.game.turn_id}))
				stage = 4
			elif stage == 4 and peer == b and d.type == "roll_result":
				print("NETWORK_PHYSICS_RESULT ok=", d.result.ok, " count=", d.result.get("dice",[]).size())
				a.send_text('{"type":"leave"}')
				done = true
				a.close()
				b.close()
				quit(0 if d.result.ok else 1)
	if Time.get_ticks_msec() > deadline and not done:
		printerr("NETWORK TIMEOUT stage=",stage)
		quit(1)
	return false
