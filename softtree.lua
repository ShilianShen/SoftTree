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
		parents = {},
		children = {},
		inDegree = 0,
		outDegree = 0,
		entity = entity or {},
		ready = false,
		dirty = true,

		load = load,
		update = update,
		unload = unload,
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

--- O(n + m)
local function setParentsAndChildren(nodeDict)
	for _, node in pairs(nodeDict) do
		node.parents = {}
		node.children = {}
		node.inDegree = 0
		node.outDegree = 0
	end
	for tag, node in pairs(nodeDict) do
		for _, parentTag in ipairs(node.parentTags) do
			local parent = nodeDict[parentTag]
			parent.children[tag] = node
			parent.outDegree = parent.outDegree + 1

			node.parents[parentTag] = parent.const
			node.inDegree = node.inDegree + 1
		end
	end
	for tag, node in pairs(nodeDict) do
		print(tag, node.inDegree, node.outDegree)
	end
end

--- O(n * m)
local function getOptimizedNodeArray(nodeDict)
	local inDegree = {}
	local sorted = 0
	local array = {}
	local count = 0

	for _, node in pairs(nodeDict) do
		array[#array + 1] = node
		inDegree[node] = node.inDegree
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

local function loadTree(tree)
	setParentsAndChildren(tree.nodeDict)
	tree.nodeArray = getOptimizedNodeArray(tree.nodeDict)
	tree.ready = true
	for _, node in ipairs(tree.nodeArray) do
		if not node.ready then
			if node.load ~= nil then
				local parents = {}
				for _, parentTag in ipairs(node.parentTags) do
					parents[parentTag] = tree.nodeDict[parentTag].const
				end
				node.load(node.entity, parents)
			end
			node.ready = true
		end
	end
end

local function unloadTree(tree)
	for _, node in ipairs(tree.nodeArray) do
		if node.ready then
			if node.unload ~= nil then
				local parents = {}
				for _, parentTag in ipairs(node.parentTags) do
					parents[parentTag] = tree.nodeDict[parentTag].const
				end
				node.unload(node.entity, parents)
			end
			node.ready = false
		end
	end
	tree.ready = false
	tree.nodeArray = nil
end

local function updateTree(tree)
	if tree.dirty then
		tree.nodeArray = getOptimizedNodeArray(tree.nodeDict)
		for _, node in pairs(tree.nodeDict) do
			node.parents = {}
			for _, parentTag in ipairs(node.parentTags) do
				node.parents[parentTag] = tree.nodeDict[parentTag].const
			end
		end
		tree.dirty = false
	end
	for _, node in ipairs(tree.nodeArray) do
		for _, parentTag in ipairs(node.parentTags) do
			local parent = tree.nodeDict[parentTag]
			if node.dirty or parent.dirty then
				node.dirty = true
				break
			end
		end
	end
	for _, node in ipairs(tree.nodeArray) do
		if node.dirty then
			if node.update ~= nil then
				local parents = {}
				for _, parentTag in ipairs(node.parentTags) do
					parents[parentTag] = tree.nodeDict[parentTag].const
				end
				node.update(node.entity, parents)
			end
			node.dirty = false
		end
	end
end

local function getTagged(tree, tag)
	return tree[tag]
end

local function getMermaid(tree)
	local mermaid = { "graph" }
	for tag, node in pairs(tree.nodeDict) do
		table.insert(mermaid, string.format('%p["%s"]', node, tag))
		for _, parentTag in ipairs(node.parentTags) do
			local parent = tree.nodeDict[parentTag]
			table.insert(mermaid, string.format("%p", parent) .. "-->" .. string.format("%p", node))
		end
	end
	return table.concat(mermaid, "\n")
end

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
