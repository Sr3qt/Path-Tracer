@tool
class_name PTTextureAbstract
extends Resource

## TODO CHANGE NAME WHEN PR IS DONE IN 4.4
## STILL WAITNING FOR THIS https://github.com/godotengine/godot/pull/67777
##
## A wrapper for either a procedural texture function or sampled texture.

enum TextureTypeFlagBits {IS_SAMPLE = 1, IS_SPATIAL = 2}

## If this texture is spatial then world coordinates will be used in sampling/calculations
## Otherwise the objects uvs will be used
@export var is_spatial := false

# TODO ADD texture updated signal


static func get_texture_type(texture : PTTextureAbstract) -> int:
	var type : int = 0

	type += int(texture.is_spatial) * TextureTypeFlagBits.IS_SPATIAL
	if texture is PTSampledTexture:
		type += TextureTypeFlagBits.IS_SAMPLE

	return type


func get_type() -> int:
	return PTTextureAbstract.get_texture_type(self)


func get_texture_id(index : int) -> int:
	return (get_type() << 30) ^ index
