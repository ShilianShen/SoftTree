local softtree = {}

--- Wraps a table to make it read-only using a proxy and metatable.
--- @param t table The table to be protected.
--- @return table A read-only proxy of the table.
--- Complexity: O(1)
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

--- Creates a new node for the tree.
--- @param parentTags table|nil List of string tags identifying parent nodes.
--- @param entity table|nil The data object managed by this node.
--- @param load function|nil Callback executed when the node is loaded.
--- @param update function|nil Callback executed when the node is marked dirty.
--- @param run function|nil Callback executed during the tree's run cycle.
--- @return table The initialized node object.
--- Complexity: O(1)
function softtree.newNode(parentTags, entity, load, update, run)
	local node = {
		parentTags = parentTags or {},
		entity = entity or {},
		ready = false,
		dirty = true,
		depth = 0,

		load = load,
		update = update,
		run = run,

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

--- Inserts a node into the tree's dictionary.
--- @param tree table The tree instance.
--- @param tag string|nil Unique identifier for the node (defaults to node pointer string).
--- @param node table The node instance to insert.
--- Complexity: O(1)
local function insert(tree, tag, node)
	tag = tag or tostring(node)
	assert(tree.nodeDict[tag] == nil)
	tree.nodeDict[tag] = node
	tree.dirty = true
end

--- Removes a node from the tree's dictionary.
--- @param tree table The tree instance.
--- @param tag string|nil Unique identifier of the node.
--- @param node table The node instance to remove.
--- Complexity: O(1)
local function remove(tree, tag, node)
	tag = tag or tostring(node)
	if tree.nodeDict[tag] == node then
		tree.nodeDict[tag] = nil
		tree.dirty = true
	end
end

--- Rebuilds parent-child references across all nodes in the dictionary.
--- @param nodeDict table Dictionary of all nodes in the tree.
--- Complexity: O(N * P) where N is number of nodes, P is average number of parent tags.
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

--- Performs a topological sort on the nodes based on parent-child dependencies.
--- @param nodeDict table Dictionary of nodes.
--- @return table A sorted array of nodes.
--- Complexity: O(N + E) where N is number of nodes, E is number of dependency edges.
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

--- Calculates the depth level of each node in the tree and the total tree depth.
--- @param tree table The tree instance.
--- Complexity: O(N * P) where N is number of nodes, P is average number of parents.
local function setDepth(tree)
	tree.depth = 0
	for i, node in ipairs(tree.nodeArray) do
		node.depth = 0
		if #node.parentTags == 0 then
			node.depth = 1
		end
		for _, parent in pairs(node.parents) do
			node.depth = math.max(node.depth, parent.depth + 1)
		end
		tree.depth = math.max(tree.depth, node.depth)
	end
end

--- Safely invokes a specific callback function on a node, passing parent data.
--- @param node table The target node.
--- @param funcname string The name of the function to call ('load', etc.).
--- Complexity: O(P) where P is the number of node parents.
local function activateFunc(node, funcname)
	if node[funcname] ~= nil then
		local params = {}
		for tag, parent in pairs(node.parents) do
			params[tag] = parent.const
		end
		node[funcname](node.entity, params)
	end
end

--- Propagates the dirty state down from parent nodes to their children.
--- @param tree table The tree instance.
--- Complexity: O(N * C) where N is the number of nodes and C is the average number of children per node.
local function spreadDirty(tree)
	for _, node in ipairs(tree.nodeArray) do
		if node.dirty then
			for _, child in pairs(node.children) do
				child.dirty = true
			end
		end
	end
end

--- Initializes the tree by sorting nodes and triggering 'load' callbacks.
--- @param tree table The tree instance.
--- Complexity: O(N + E) for sorting + O(N * P) for callbacks.
local function loadTree(tree)
	setParentsAndChildren(tree.nodeDict)
	tree.nodeArray = getOptimizedNodeArray(tree.nodeDict)
	setDepth(tree)
	tree.ready = true
	for _, node in ipairs(tree.nodeArray) do
		if not node.ready then
			activateFunc(node, "load")
			node.ready = true
		end
	end
end

--- Refreshes the tree structure if dirty and triggers 'update' for dirty nodes.
--- @param tree table The tree instance.
--- Complexity: O(N + E) if dirty; otherwise O(N * C) where C is average children.
local function updateTree(tree)
	if tree.dirty then
		setParentsAndChildren(tree.nodeDict)
		tree.nodeArray = getOptimizedNodeArray(tree.nodeDict)
		setDepth(tree)
		tree.dirty = false
	end
	spreadDirty(tree)
	for _, node in ipairs(tree.nodeArray) do
		if node.dirty then
			activateFunc(node, "update")
			node.dirty = false
		end
	end
end

--- Iterates through all nodes and triggers their 'run' callbacks.
--- @param tree table The tree instance.
--- Complexity: O(N * P).
local function runTree(tree)
	for _, node in ipairs(tree.nodeArray) do
		activateFunc(node, "run")
	end
end

--- Retrieves a node by its tag.
--- @param tree table The tree instance.
--- @param tag string The node identifier.
--- @return table|nil The requested node.
--- Complexity: O(1).
local function getTagged(tree, tag)
	return tree.nodeDict[tag]
end

--- Marks a specific node as dirty.
--- @param tree table The tree instance.
--- @param tag string The node identifier.
--- Complexity: O(1).
local function setDirty(tree, tag)
	tree.nodeDict[tag].dirty = true
end

--- Generates a Mermaid.js compatible graph string representing the tree structure.
--- @param tree table The tree instance.
--- @return string Mermaid graph definition.
--- Complexity: O(N * P).
local function getMermaid(tree)
	local mermaid = { "graph" }
	for tag, node in pairs(tree.nodeDict) do
		table.insert(mermaid, string.format('%p["%s"]', node, tag))
		for _, parentTag in ipairs(node.parentTags) do
			local parent = tree.nodeDict[parentTag]
			if parent then
				table.insert(mermaid, string.format("%p", parent) .. "-->" .. string.format("%p", node))
			end
		end
	end
	return table.concat(mermaid, "\n")
end

--- Creates and initializes a new softtree instance.
--- @return table The new tree object.
--- Complexity: O(1).
function softtree.newTree()
	local tree = {
		dirty = true,
		ready = false,
		nodeDict = {},
		nodeArray = {},
		root = softtree.newNode(),
		depth = 0,

		insert = insert,
		remove = remove,
		load = loadTree,
		update = updateTree,
		run = runTree,
		getTagged = getTagged,
		setDirty = setDirty,
		spreadDirty = spreadDirty,

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
