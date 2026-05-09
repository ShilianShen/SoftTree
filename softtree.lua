local softtree = {}

---@brief Wraps a table in a read-only proxy to prevent external modification.
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

---@brief Initializes a new tree node with specified lifecycle callbacks.
---@param parentTags string[]|nil List of tags identifying parent nodes.
---@param entity table|nil The data object managed by this node.
---@param load function|nil Callback triggered when node is `stale`.
---@param update function|nil Callback triggered when node is `dirty`.
---@param run function|nil Callback triggered every tick.
---@return table node The initialized node object.
---@note Complexity: Time O(1), Space O(1)
function softtree.newNode(parentTags, entity, load, update, run)
	local node = {
		parentTags = parentTags or {},
		entity = entity or {},
		stale = true,
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

---@brief Registers a node into the tree's registry and marks the tree as dirty.
---@param tree table The tree instance.
---@param tag string|nil Unique identifier for the node.
---@param node table The node object to insert.
---@note Complexity: Time O(1), Space O(1)
local function insert(tree, tag, node)
	tag = tag or tostring(node)
	assert(tree.nodeDict[tag] == nil)
	tree.nodeDict[tag] = node
	tree.dirty = true
end

---@brief Removes a node from the tree's registry by its tag.
---@param tree table The tree instance.
---@param tag string|nil The unique identifier of the node.
---@param node table The node object to verify and remove.
---@note Complexity: Time O(1), Space O(1)
local function remove(tree, tag, node)
	tag = tag or tostring(node)
	if tree.nodeDict[tag] == node then
		tree.nodeDict[tag] = nil
		tree.dirty = true
	end
end

---@brief Calculates the hierarchical depth for each node in the sorted array.
---@param tree table The tree instance containing the sorted nodeArray.
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

---@brief Reconstructs child-parent references based on string tags.
---@param nodeDict table<string, table> The dictionary of all active nodes.
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

---@brief Performs a topological sort to establish a valid execution order.
---@param nodeDict table<string, table> The dictionary of all nodes.
---@return table[] array An array of nodes ordered by dependency.
---@note Complexity: Time O(N * (N + E)) in worst-case search, Space O(N)
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

---@brief Executes a specific lifecycle function on a node with parent data injected.
---@param node table The target node.
---@param funcname string The name of the function to invoke ('load', 'update', or 'run').
---@note Complexity: Time O(Parents of N), Space O(Parents of N)
local function _activateFunc(node, funcname)
	if node[funcname] ~= nil then
		local params = {}
		for tag, parent in pairs(node.parents) do
			params[tag] = parent.const
		end
		node[funcname](node.entity, params)
	end
end

---@brief Propagates `stale` and `dirty` states down the dependency graph.
---@param nodeArray table[] The topologically sorted node array.
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

---@brief Orchestrates the full tree lifecycle including rebuilding, spreading, and execution.
---@param tree table The tree instance to process.
---@note Complexity: Time O(N * (N + E)) if tree is dirty, else O(N + E), Space O(N + E)
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

---@brief Retrieves a node from the tree by its unique tag.
---@param tree table The tree instance.
---@param tag string The tag to search for.
---@return table|nil node The found node or nil.
---@note Complexity: Time O(1), Space O(1)
local function getTagged(tree, tag)
	return tree.nodeDict[tag]
end

---@brief Manually flags a node as `dirty` to trigger re-calculation in the next tick.
---@param tree table The tree instance.
---@param tag string The tag of the node to flag.
---@note Complexity: Time O(1), Space O(1)
local function setDirty(tree, tag)
	tree.nodeDict[tag].dirty = true
end

---@brief Generates a Mermaid.js string representing the current tree structure.
---@param tree table The tree instance.
---@return string mermaid The formatted Mermaid graph string.
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

---@brief Factory function to create a new softtree instance.
---@return table tree The new tree object with root node initialized.
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
