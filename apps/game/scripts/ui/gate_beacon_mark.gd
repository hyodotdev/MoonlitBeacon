class_name GateBeaconMark
extends Control

## Crescent moon and beacon diamond beside the entry title, drawn from code.
##
## A small gold crescent over a rising beacon spark with two faint stars:
## the moon/beacon answer to the gate painting, sized for the kicker row so
## the title block reads as a game emblem instead of plain app type. Pure
## decoration; it never takes input and never moves.

const GOLD: Color = Color(0.96, 0.76, 0.40)
const GOLD_DIM: Color = Color(0.96, 0.76, 0.40, 0.55)
const INK: Color = Color(0.02, 0.04, 0.09, 1.0)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(30.0, 30.0)


func _draw() -> void:
	var middle: float = size.x * 0.5
	var moon_at := Vector2(middle, size.y * 0.34)
	var moon_r: float = minf(size.x, size.y) * 0.24
	draw_circle(moon_at, moon_r, GOLD)
	draw_circle(moon_at + Vector2(moon_r * 0.45, -moon_r * 0.25),
		moon_r * 0.82, INK)
	var spark_at := Vector2(middle, size.y * 0.78)
	var spark_r: float = minf(size.x, size.y) * 0.10
	draw_colored_polygon(
		PackedVector2Array([
			spark_at + Vector2(0.0, -spark_r * 1.6),
			spark_at + Vector2(spark_r, 0.0),
			spark_at + Vector2(0.0, spark_r * 1.6),
			spark_at + Vector2(-spark_r, 0.0),
		]),
		GOLD)
	draw_line(spark_at + Vector2(0.0, -spark_r * 2.2),
		moon_at + Vector2(0.0, moon_r * 0.9), GOLD_DIM, 1.0, true)
	draw_circle(Vector2(size.x * 0.16, size.y * 0.62), 1.1, GOLD_DIM)
	draw_circle(Vector2(size.x * 0.84, size.y * 0.52), 1.1, GOLD_DIM)
