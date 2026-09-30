class_name SoftDisc
extends RefCounted

## Soft radial discs, generated in code.
##
## Shadows, light pools, colour patches and spark flashes all need the same thing:
## a round gradient that fades to nothing at its rim, stretched into an ellipse.
## A PNG for each would be four more files in the asset manifest for something the
## engine can build exactly, and each script used to carry its own copy of the same
## twelve lines. They keep one static texture each and ask for it here.
##
## The discs are drawn with linear filtering (set on the node that draws them). With
## the project's nearest-neighbour default a stretched gradient bands into steps.


## A radial gradient, white in RGB, with the given alpha at each stop.
##
## `stops` are `Vector2(offset, alpha)` from the centre (0) to the rim (1), in order.
static func radial(stops: Array[Vector2], size: int = 64) -> GradientTexture2D:
	var gradient := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for stop in stops:
		offsets.append(stop.x)
		colors.append(Color(1.0, 1.0, 1.0, stop.y))
	gradient.offsets = offsets
	gradient.colors = colors
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = size
	texture.height = size
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture
