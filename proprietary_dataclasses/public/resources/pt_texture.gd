@tool
class_name PTTexture
extends Resource

## A wrapper for either a procedural texture function or sampled texture.

enum TextureType {IS_SAMPLE = 1, IS_SPATIAL = 2}

@export var is_spatial := true
var procedural_texture : String

var texture_2d

var texture_3d # IDK maybe this makes sense later

# TODO ADD texture updated signal


static func get_texture_type(texture : PTTexture) -> int:
	var type : int = 0
	
	type += int(texture.is_spatial) * TextureType.IS_SPATIAL
	#if texture is PTSampleTexture:
	#	type += TextureType.IS_SAMPLE
	
	return type


func get_type() -> int:
	return PTTexture.get_texture_type(self)


func get_texture_id(index : int) -> int:
	
	return (get_type() << 30) + index
