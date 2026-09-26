extends Node

const PANEL: PackedScene = preload("res://scenes/ui/relic_panel.tscn")


func _ready() -> void:
	var panel: Control = PANEL.instantiate() as Control
	add_child(panel)
	panel.set("visible", true)
	var offer: Array[Relic] = [
		load("res://resources/relics/long_blade.tres"),
		load("res://resources/relics/moon_ring.tres"),
		load("res://resources/relics/twin_arrow.tres"),
	]
	panel.call("_open_offer", offer, "The moonlight offers a gift")
