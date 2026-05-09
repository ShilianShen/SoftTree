local softtree = {}

---@brief Wraps a table to make it read-only via a proxy.
---@param t table The target table to protect.
---@return table proxy The read-only proxy table.
---@note Complexity: Time O(1), Space O(1)
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

---@brief Initializes a new tree node with specified lifecycle callbacks and dependencies.
---@param parentTags string[]|nil List of tags identifying parent nodes.
---@param entity table|nil The data object associated with this node.
---@param load function|nil Callback for resource loading.
---@param update function|nil Callback for logic re-calculation.
---@param run function|nil Callback for per-tick execution.
---@return table node The initialized node object.
---@note Complexity: Time O(1), Space O(1)
function softtree.newNode(parentTags, entity, load, update, run)
	local node = {
		parentTags = parentTags or {},
		entity = entity or {},
		stale = true, -- Indicates resource reloading is required
		dirty = true, -- Indicates logic re-calculation is required
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

---@brief Registers a node into the tree and marks the tree structure as dirty.
---@param tree table The tree instance.
---@param tag string|nil Unique identifier; defaults to node memory address.
---@param node table The node instance to insert.
---@note Complexity: Time O(1), Space O(1)
local function insert(tree, tag, node)
	tag = tag or tostring(node)
	assert(tree.nodeDict[tag] == nil)
	tree.nodeDict[tag] = node
	tree.dirty = true
end

---@brief Removes a node from the tree and marks the tree structure as dirty.
---@param tree table The tree instance.
---@param tag string|nil Unique identifier.
---@param node table The node instance to remove.
---@note Complexity: Time O(1), Space O(1)
local function remove(tree, tag, node)
	tag = tag or tostring(node)
	if tree.nodeDict[tag] == node then
		tree.nodeDict[tag] = nil
		tree.dirty = true
	end
end

---@brief Computes and assigns the hierarchical depth for every node in the sorted array.
---@param tree table The tree instance.
---@note Complexity: Time O(N + E), Space O(1)
local function _setDepth(tree)
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

---@brief Rebuilds the parent-child adjacency pointers based on registered parentTags.
---@param nodeDict table<string, table> Dictionary of tags to nodes.
---@note Complexity: Time O(N + E), Space O(E)
local function _setParentsAndChildren(nodeDict)
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

---@brief Performs topological sorting to generate an optimized execution order.
---@param nodeDict table<string, table> The dictionary of all nodes.
---@return table[] nodeArray Array of nodes ordered by dependency.
---@note Complexity: Time O(N * (N + E)) in worst case for this specific loop, Space O(N)
local function _getOptimizedNodeArray(nodeDict)
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

---@brief Invokes a specific lifecycle function on a node with parent data context.
---@param node table The target node.
---@param funcname string The name of the function to call ("load", "update", or "run").
---@note Complexity: Time O(P) where P is parent count, Space O(P)
local function _activateFunc(node, funcname)
	if node[funcname] ~= nil then
		local params = {}
		for tag, parent in pairs(node.parents) do
			params[tag] = parent.const
		end
		node[funcname](node.entity, params)
	end
end

---@brief Propagates stale and dirty states down the dependency graph.
---@param nodeArray table[] Sorted array of nodes.
---@note Complexity: Time O(N + E), Space O(1)
local function _spread(nodeArray)
	for _, node in ipairs(nodeArray) do
		if node.stale then
			for _, child in pairs(node.children) do
				child.stale = true
				child.dirty = true
			end
		elseif node.dirty then
			for _, child in pairs(node.children) do
				child.dirty = true
			end
		end
	end
end

---@brief Processes the entire tree, handling structural updates, state spread, and lifecycle execution.
---@param tree table The tree instance to process.
---@note Complexity: Time O(N + E), Space O(N + E) (when rebuilding structure)
local function tickTree(tree)
	if tree.dirty then
		_setParentsAndChildren(tree.nodeDict)
		tree.nodeArray = _getOptimizedNodeArray(tree.nodeDict)
		_setDepth(tree)
		tree.dirty = false
	end

	_spread(tree.nodeArray)

	for _, node in ipairs(tree.nodeArray) do
		if node.stale then
			_activateFunc(node, "load")
			node.stale = false
		end
		if node.dirty then
			_activateFunc(node, "update")
			node.dirty = false
		end
		_activateFunc(node, "run")
	end
end

---@brief Retrieves a node by its tag.
---@param tree table The tree instance.
---@param tag string The node identifier.
---@return table|nil node The found node or nil.
---@note Complexity: Time O(1), Space O(1)
local function getTagged(tree, tag)
	return tree.nodeDict[tag]
end

---@brief Explicitly marks a specific node as stale.
---@param tree table The tree instance.
---@param tag string The node identifier.
---@note Complexity: Time O(1), Space O(1)
local function setStale(tree, tag)
	tree.nodeDict[tag].stale = true
end

---@brief Explicitly marks a specific node as dirty.
---@param tree table The tree instance.
---@param tag string The node identifier.
---@note Complexity: Time O(1), Space O(1)
local function setDirty(tree, tag)
	tree.nodeDict[tag].dirty = true
end

---@brief Generates a Mermaid.js compatible string representing the tree structure.
---@param tree table The tree instance.
---@return string mermaid The formatted graph string.
---@note Complexity: Time O(N + E), Space O(N + E)
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

---@brief Creates a new softtree instance.
---@return table tree The tree container object.
---@note Complexity: Time O(1), Space O(1)
function softtree.newTree()
	local tree = {
		dirty = true,
		stale = true,
		nodeDict = {},
		nodeArray = {},
		root = softtree.newNode(),
		depth = 0,

		insert = insert,
		remove = remove,
		tick = tickTree,

		getTagged = getTagged,
		getMermaid = getMermaid,

		setStale = setStale,
		setDirty = setDirty,
		spread = _spread,
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