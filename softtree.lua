local softtree = {}

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

function softtree.newNode(parentTags, entity, load, unload, update)
	local node = {
		parentTags = parentTags or {},
		parents = {},
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

local function insert(tree, tag, node)
	tag = tag or tostring(node)
	assert(tree.nodeDict[tag] == nil)
	tree.nodeDict[tag] = node
	tree.dirty = true
end

local function remove(tree, tag, node)
	tag = tag or tostring(node)
	if tree.nodeDict[tag] == node then
		tree.nodeDict[tag] = nil
		tree.dirty = true
	end
end

local function getOptimizedNodeArray(nodeDict)
	local inDegree = {}
	local children = {}
	local result = {}
	local queue = {}

	-- 1. 初始化入度表和反向引用表（子节点表）
	for _, node in pairs(nodeDict) do
		inDegree[node] = #node.parentTags
		if inDegree[node] == 0 then
			table.insert(queue, node)
		end

		-- 构建反向映射，方便依赖更新
		for _, parentTag in ipairs(node.parentTags) do
			local parent = nodeDict[parentTag]
			children[parent] = children[parent] or {}
			table.insert(children[parent], node)
		end
	end

	-- 2. 处理队列
	local head = 1
	while head <= #queue do
		local current = queue[head]
		head = head + 1
		table.insert(result, current)

		local subs = children[current]
		if subs then
			for _, child in ipairs(subs) do
				inDegree[child] = inDegree[child] - 1
				if inDegree[child] == 0 then
					table.insert(queue, child)
				end
			end
		end
	end

	-- 3. 写回原数组
	return result
end

local function loadTree(tree)
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
