local softtree = {}

function softtree.newNode(parents, entity, load, unload, update)
	local node = {
		parents = parents or {},
		entity = entity or {},
		ready = false,
		dirty = true,

		load = load,
		update = update,
		unload = unload,
	}
	return node
end

local function insert(tree, node, tag)
	tag = tag or tostring(node)
	assert(tree.nodeDict[tag] == nil)
	tree.nodeDict[tag] = node
	tree.dirty = true
end

local function remove(tree, node, tag)
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
		inDegree[node] = #node.parents
		if inDegree[node] == 0 then
			table.insert(queue, node)
		end

		-- 构建反向映射，方便依赖更新
		for _, parent in ipairs(node.parents) do
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
				node.load()
			end
			node.ready = true
		end
	end
end

local function unloadTree(tree)
	for _, node in ipairs(tree.nodeArray) do
		if node.ready then
			if node.unload ~= nil then
				node.unload()
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
		tree.dirty = false
	end
	for _, node in ipairs(tree.nodeArray) do
		for _, parent in ipairs(node.parents) do
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
				for _, parent in ipairs(node.parents) do
					table.insert(parents, parent.entity)
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
		for _, parent in ipairs(node.parents) do
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
	tree:insert(tree.root, "root")
	return tree
end

return softtree
