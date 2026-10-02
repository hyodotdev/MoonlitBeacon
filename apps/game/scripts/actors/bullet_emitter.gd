class_name BulletEmitter
extends RefCounted

## One way of shooting, and the clock that keeps it going: a spiral turning, a fan aimed at you, a ring that drifts,
## a stream that sways. A spirit owns a few of them and ticks them while it is allowed to shoot; each one puts its
## bullets into the `BulletField`. Nothing here draws or moves anything, so it can be tested without a scene.
##
## Every shape is meant to be woven through, so the numbers that matter are the gaps: the arms of a spiral are far
## apart in angle and close along the arm, a ring's bullets are spread wide and slow, and a ring that fires again
## has turned by `ring_step`, so its gaps are somewhere new each time and never in the same place twice running.

enum Pattern { SPIRAL, AIMED, RING, WAVE }

var pattern: int = Pattern.AIMED
## Seconds between one shot and the next. A shot is one bullet per arm, one whole fan or one whole ring.
var interval: float = 0.5
var speed: float = 80.0
## Arms of a spiral, bullets in a fan, bullets in a ring.
var count: int = 1
## How wide an aimed fan is (radians, in all), and how far a wave sways either side of the aim.
var spread: float = 0.0
## How fast a spiral turns and how fast a wave sways (radians a second).
var spin: float = 0.0
var tint: int = BulletField.Tint.PINK
var range_px: float = 280.0
var accel: float = 0.0
var turn: float = 0.0
## A little scatter added to every bullet (radians), so a stream is not a ruled line.
var jitter: float = 0.0
## How far a ring is turned each time it fires.
var ring_step: float = 0.0
## The bullets of a shot start this far from the muzzle, in the direction they fly.
var muzzle: float = 6.0
## `BulletField.Source` of what this emitter shoots.
var source: int = BulletField.Source.NONE

var _timer: float = 0.0
var _angle: float = 0.0
var _time: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Bullets placed by the last tick, for the tests.
var last_placed: int = 0


static func spiral(arms: int, every: float, bullet_speed: float, turning: float, colour: int) -> BulletEmitter:
	var emitter: BulletEmitter = BulletEmitter.new()
	emitter.pattern = Pattern.SPIRAL
	emitter.count = arms
	emitter.interval = every
	emitter.speed = bullet_speed
	emitter.spin = turning
	emitter.tint = colour
	return emitter


static func aimed(shots: int, fan_spread: float, every: float, bullet_speed: float, colour: int) -> BulletEmitter:
	var emitter: BulletEmitter = BulletEmitter.new()
	emitter.pattern = Pattern.AIMED
	emitter.count = shots
	emitter.spread = fan_spread
	emitter.interval = every
	emitter.speed = bullet_speed
	emitter.tint = colour
	return emitter


static func ring(shots: int, every: float, bullet_speed: float, step: float, colour: int) -> BulletEmitter:
	var emitter: BulletEmitter = BulletEmitter.new()
	emitter.pattern = Pattern.RING
	emitter.count = shots
	emitter.interval = every
	emitter.speed = bullet_speed
	emitter.ring_step = step
	emitter.tint = colour
	return emitter


static func wave(sway: float, sway_speed: float, every: float, bullet_speed: float, colour: int) -> BulletEmitter:
	var emitter: BulletEmitter = BulletEmitter.new()
	emitter.pattern = Pattern.WAVE
	emitter.spread = sway
	emitter.spin = sway_speed
	emitter.interval = every
	emitter.speed = bullet_speed
	emitter.tint = colour
	return emitter


## Start again from a known state: the next shot comes after `delay` seconds, and a spiral begins at `start_angle`.
func restart(delay: float = 0.0, start_angle: float = 0.0) -> void:
	_timer = interval - maxf(delay, 0.0)
	_angle = start_angle
	_time = 0.0


## Advance the clock by `delta`. `rate` speeds it up or slows it (a guardian's tempo). Shots that fall due are
## fired from `origin`; `target` is where an aimed shot is aimed. Returns how many bullets were placed.
func tick(delta: float, origin: Vector2, target: Vector2, field: BulletField, rate: float = 1.0) -> int:
	last_placed = 0
	if field == null or interval <= 0.0:
		return 0
	_timer += delta * maxf(rate, 0.0)
	var placed: int = 0
	var guard: int = 0
	while _timer >= interval and guard < 4:
		_timer -= interval
		guard += 1
		placed += _fire(origin, target, field, _timer / maxf(rate, 0.001))
	if guard >= 4:
		_timer = fmod(_timer, interval)
	last_placed = placed
	return placed


func _fire(origin: Vector2, target: Vector2, field: BulletField, advance: float) -> int:
	var aim: float = (target - origin).angle()
	var placed: int = 0
	match pattern:
		Pattern.SPIRAL:
			for arm in count:
				var angle: float = _angle + TAU * float(arm) / float(count) + _scatter()
				if _spawn(field, origin, angle, advance):
					placed += 1
			_angle += spin * interval
		Pattern.AIMED:
			for index in count:
				var t: float = 0.0 if count == 1 else float(index) / float(count - 1) - 0.5
				if _spawn(field, origin, aim + spread * t + _scatter(), advance):
					placed += 1
		Pattern.RING:
			for index in count:
				if _spawn(field, origin, _angle + TAU * float(index) / float(count) + _scatter(), advance):
					placed += 1
			_angle += ring_step
		Pattern.WAVE:
			if _spawn(field, origin, aim + spread * sin(_time * spin) + _scatter(), advance):
				placed += 1
			_time += interval
	return placed


func _spawn(field: BulletField, origin: Vector2, angle: float, advance: float) -> bool:
	var start: Vector2 = origin + Vector2.RIGHT.rotated(angle) * muzzle
	return field.spawn(start, angle, speed, tint, range_px, accel, turn, advance, source)


func _scatter() -> float:
	if jitter <= 0.0:
		return 0.0
	return _rng.randf_range(-jitter, jitter)
