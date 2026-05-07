local softtree = {}

--- O(1)
local function getConst(t)
	local proxy = {}
	local mt = {
		__index = t,
		__newindex = function(_, k, v)
			error("Attempt to modify a read-only table", 2)
		end,
		__metatable = false,
	}
	return setmetatable(proxy, mt)
end

--- O(1)
function softtree.newNode(parentTags, entity, load, unload, update)
	local node = {
		parentTags = parentTags or {},
		entity = entity or {},
		ready = false,
		dirty = true,

		load = load,
		unload = unload,
		update = update,

		parents = {},
		children = {},
	}
	node.const = getConst(node.entity)
	setmetatable(node, {
		__newindex = function()
			assert(false)
		end,
		__metatable = false,
	})
	return node
end

--- O(1)
local function insert(tree, tag, node)
	tag = tag or tostring(node)
	assert(tree.nodeDict[tag] == nil)
	tree.nodeDict[tag] = node
	tree.dirty = true
end

--- O(1)
local function remove(tree, tag, node)
	tag = tag or tostring(node)
	if tree.nodeDict[tag] == node then
		tree.nodeDict[tag] = nil
		tree.dirty = true
	end
end

--- O(n+m)
local function setParentsAndChildren(nodeDict)
	for _, node in pairs(nodeDict) do
		node.parents = {}
		node.children = {}
	end
	for tag, node in pairs(nodeDict) do
		for _, parentTag in ipairs(node.parentTags) do
			local parent = nodeDict[parentTag]
			parent.children[tag] = node
			node.parents[parentTag] = parent
		end
	end
end

--- O(n^2)
local function getOptimizedNodeArray(nodeDict)
	local inDegree = {}
	local sorted = 0
	local array = {}
	local count = 0

	for _, node in pairs(nodeDict) do
		array[#array + 1] = node
		inDegree[node] = #node.parentTags
		count = count + 1
	end

	local loop = true
	while loop do
		loop = false
		for i = sorted + 1, #array do
			local node = array[i]
			if inDegree[node] == 0 then
				loop = true
				sorted = sorted + 1
				array[i] = array[sorted]
				array[sorted] = node
				for _, child in pairs(node.children) do
					inDegree[child] = inDegree[child] - 1
				end
			end
		end
	end

	assert(sorted == count)

	return array
end

--- O(\delta^-(x))
local function activateFunc(node, funcname)
	if node[funcname] ~= nil then
		local params = {}
		for tag, parent in pairs(node.parents) do
			params[tag] = parent.const
		end
		node[funcname](node.entity, params)
	end
end

--- O(n)
local function loadTree(tree)
	setParentsAndChildren(tree.nodeDict)
	tree.nodeArray = getOptimizedNodeArray(tree.nodeDict)
	tree.ready = true
	for _, node in ipairs(tree.nodeArray) do
		if not node.ready then
			activateFunc(node, "load")
			node.ready = true
		end
	end
end

--- O(n)
local function unloadTree(tree)
	for _, node in ipairs(tree.nodeArray) do
		if node.ready then
			activateFunc(node, "unload")
			node.ready = false
		end
	end
	tree.ready = false
	tree.nodeArray = nil
end

--- O(n + m)
local function updateTree(tree)
	if tree.dirty then
		setParentsAndChildren(tree.nodeDict)
		tree.nodeArray = getOptimizedNodeArray(tree.nodeDict)
		tree.dirty = false
	end
	for _, node in ipairs(tree.nodeArray) do
		if node.dirty then
			for _, child in pairs(node.children) do
				child.dirty = true
			end
			activateFunc(node, "update")
			node.dirty = false
		end
	end
end

-- O(1)
local function getTagged(tree, tag)
	return tree[tag]
end

-- O(1)
function softtree.newTree()
	local tree = {
		dirty = true,
		ready = false,
		nodeDict = {},
		nodeArray = {},
		root = softtree.newNode(),

		insert = insert,
		remove = remove,
		load = loadTree,
		unload = unloadTree,
		update = updateTree,
		getTagged = getTagged,

		getMermaid = getMermaid,
	}
	setmetatable(tree, {
		__newindex = function()
			assert(false)
		end,
		__metatable = false,
	})
	tree:insert("root", tree.root)
	return tree
end

return softtree
