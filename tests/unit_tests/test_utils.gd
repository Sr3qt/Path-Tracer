extends GutTest


func test_create_missing_texture_grid() -> void:
	var result2 : Array[int] = [
		56, 16, 56, 56,
		0, 0, 0, 56,

		0, 0, 0, 56,
		56, 16, 56, 56,
	]
	var result4 : Array[int] = [
		56, 16, 56, 56,
		0, 0, 0, 56,
		56, 16, 56, 56,
		0, 0, 0, 56,

		0, 0, 0, 56,
		56, 16, 56, 56,
		0, 0, 0, 56,
		56, 16, 56, 56,

		56, 16, 56, 56,
		0, 0, 0, 56,
		56, 16, 56, 56,
		0, 0, 0, 56,

		0, 0, 0, 56,
		56, 16, 56, 56,
		0, 0, 0, 56,
		56, 16, 56, 56,
	]

	# Unfortunately i do not know any other way to create a PackedByteArray
	#  without it wrongly converting numbers
	var res2 : PackedByteArray = []
	var res4 : PackedByteArray = []
	res2.resize(result2.size())
	res4.resize(result4.size())

	for i in range(res2.size()):
		res2.encode_u8(i, result2[i])


	for i in range(res4.size()):
		res4.encode_u8(i, result4[i])


	assert_true(PTUtils.create_missing_texture_grid(2) == res2, "Created 2x2 texture")
	assert_true(PTUtils.create_missing_texture_grid(4) == res4, "Created 4x4 texture")


func test_is_aabb_valid() -> void:
	var bbox1 := AABB()
	var bbox2 := AABB(Vector3(0, 0, 1), Vector3.ONE)
	var bbox3 := AABB(Vector3(-1, -1, 0), Vector3.ONE)
	var bbox4 := AABB(Vector3(0, 0, 1), -Vector3.ONE)
	var bbox5 := AABB(Vector3(0, 2, -3), Vector3.ZERO)
	var bbox6 := AABB(Vector3(4, -2, 1), Vector3(0, 2, -2))
	var bbox7 := AABB(Vector3(4, INF, 1), 2 * Vector3.ONE)
	var bbox8 := AABB(Vector3(4, 0, 1), Vector3(0, 2, INF))
	var bbox9 := AABB(Vector3(4, 0, 1), Vector3(0, 2, 2))
	var bbox10 := AABB(Vector3(2, -2, 2), Vector3(0, 1, 0))
	var bbox11 := AABB(Vector3(4, 0, INF), Vector3(0, 2, INF))

	assert_false(PTUtils.is_aabb_valid(bbox1), "ZERO vectors")
	assert_true(PTUtils.is_aabb_valid(bbox2), "Trivial True")
	assert_true(PTUtils.is_aabb_valid(bbox3), "Trivial True")
	assert_false(PTUtils.is_aabb_valid(bbox4), "Negative size")
	assert_false(PTUtils.is_aabb_valid(bbox5), "Zero size")
	assert_false(PTUtils.is_aabb_valid(bbox6), "Negative axis")
	assert_false(PTUtils.is_aabb_valid(bbox7), "INF pos")
	assert_false(PTUtils.is_aabb_valid(bbox8), "INF size")
	assert_true(PTUtils.is_aabb_valid(bbox9), "Axis zero")
	assert_true(PTUtils.is_aabb_valid(bbox10), "Axis zero")
	assert_false(PTUtils.is_aabb_valid(bbox11), "Double INF")


func test_merge_aabb() -> void:
	var bbox1 := AABB()
	var bbox2 := AABB(Vector3(0, 0, 1), Vector3.ONE)
	var bbox3 := AABB(Vector3(-1, -1, 0), Vector3.ONE)
	var bbox4 := AABB(Vector3(0, 0, 1), -Vector3.ONE)
	var bbox5 := AABB(Vector3(0, 2, -3), Vector3.ZERO)
	var bbox6 := AABB(Vector3(4, -2, 1), Vector3(0, 2, -2))
	var bbox7 := AABB(Vector3(4, INF, 1), 2 * Vector3.ONE)
	var bbox8 := AABB(Vector3(4, 0, 1), Vector3(0, 2, INF))
	# var bbox9 := AABB(Vector3(4, 0, 1), Vector3(0, 2, 2))
	var bbox10 := AABB(Vector3(2, -2, 2), Vector3(0, 1, 0))
	# var bbox11 := AABB(Vector3(4, 0, INF), Vector3(0, 2, INF))
	# var bbox12 := AABB(Vector3(0, -2, -1), Vector3(4, 3, 3))
	var bbox13 := AABB(Vector3(0, -2, 1), Vector3(2, 3, 1))

	var res1 := PTUtils.merge_aabb(bbox1, bbox2)
	var res2 := PTUtils.merge_aabb(bbox3, bbox4)
	var res3 := PTUtils.merge_aabb(bbox2, bbox6)
	var res4 := PTUtils.merge_aabb(bbox5, bbox6)
	var res5 := PTUtils.merge_aabb(bbox7, bbox8)
	var res6 := PTUtils.merge_aabb(bbox2, bbox10)

	assert_eq(res1, bbox2, "Ignore ZERO")
	assert_eq(res2, bbox3, "Ignore Negative")
	assert_eq(res3, bbox2, "Ignore Negative")
	assert_eq(res4, bbox1, "Ignore Sizes")
	assert_eq(res5, bbox1, "Ignore Two INFs")
	assert_eq(res6, bbox13, "Pass One Zero Axis")
