extends GutTest

var container : PTObjectContainer= null


func before_all():
	gut.p("hello")
	container = PTObjectContainer.new()


func after_each():
	container.clean()


func test_merge():
	container.add_object(PTSphere.new())
	container.add_object(PTSphere.new())
	container.add_object(PTSphere.new())
	container.add_object(PTTriangle.new())

	var other := PTObjectContainer.new()

	other.add_object(PTPlane.new())
	other.add_object(PTPlane.new())
	other.add_object(PTSphere.new())
	other.add_object(PTSphere.new())
	other.add_object(PTSphere.new())
	other.add_object(PTSphere.new())

	var res := container.merge(other)

	assert_eq(container.object_count, 10)
	assert_eq(other.object_count, 6)

	assert_true(res[PTObject.ObjectType.SPHERE])
	assert_true(res[PTObject.ObjectType.PLANE])
	assert_false(res[PTObject.ObjectType.TRIANGLE])

	assert_true(TestHelper.check_dictionary_index(container.spheres, container._object_to_object_index))
	assert_true(TestHelper.check_dictionary_index(container.planes, container._object_to_object_index))
	assert_true(TestHelper.check_dictionary_index(container.triangles, container._object_to_object_index))
