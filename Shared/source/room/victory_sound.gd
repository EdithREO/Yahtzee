extends RefCounted

# Original five-second ascending major arpeggio and sustained closing chord.
static func create() -> AudioStreamWAV:
	const RATE := 22050
	const LENGTH := 5.0
	var notes := [523.25,659.25,783.99,1046.5,783.99,1046.5]
	var starts := [0.0,0.30,0.60,0.90,1.20,1.60,2.10]
	var chord := [523.25,659.25,783.99,1046.5]
	var data := PackedByteArray()
	data.resize(int(RATE*LENGTH)*2)
	for i in range(int(RATE*LENGTH)):
		var t := float(i)/RATE
		var value := 0.0
		if t < 2.10:
			var n := 0
			while n < notes.size()-1 and t >= starts[n+1]: n += 1
			var local_t: float = t-starts[n]
			var envelope := minf(local_t/0.015,1.0)*minf((starts[n+1]-t)/0.06,1.0)
			value = _bell(notes[n],local_t)*envelope*0.42
		else:
			var local_t := t-2.10
			var envelope := minf(local_t/0.025,1.0)*exp(-local_t*0.25)*clampf((LENGTH-t)/0.65,0,1)
			for frequency in chord: value += _bell(frequency,local_t)/chord.size()
			value *= envelope*0.50
		data.encode_s16(i*2,int(clampf(value,-1,1)*32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream

static func _bell(frequency: float,t: float) -> float:
	return sin(TAU*frequency*t)*0.80 + sin(TAU*frequency*2*t)*0.16 + sin(TAU*frequency*3*t)*0.04
