--- Softtree — a lightweight dependency-graph scheduler for Lua.
-- Manages a directed acyclic graph (DAG) of nodes, each carrying an entity
-- and optional `load`, `update`, and `run` lifecycle callbacks. On every
-- `tick`, the tree performs a topological sort, propagates staleness and
-- dirtiness from parents to children, and invokes the appropriate callbacks
-- in dependency order.

local softtree = {}

--- Wraps a table in a read-only proxy.
-- Any attempt to write through the proxy raises an error. The original
-- table remains mutable via its direct reference.
-- @param t table  The table to protect.
-- @return table  A read-only proxy for `t`.
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

--- Creates a new node for use in a softtree.
-- The returned node is itself write-protected; all mutable state lives inside
-- `node.entity`. `node.const` exposes a read-only view of `entity` that is
-- passed to parent-parameter tables in lifecycle callbacks.
-- @param parentTags table   Ordered list of tag strings identifying this node's parents. Defaults to `{}`.
-- @param entity     table   Arbitrary user data carried by the node. Defaults to `{}`.
-- @param load       function|nil  Called once when the node is marked stale, before `update`.
-- @param update     function|nil  Called whenever the node is dirty (including after a load).
-- @param run        function|nil  Called on every tick regardless of dirty/stale state.
-- @return table  A new, write-protected node table.
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

--- Inserts a node into the tree under the given tag.
-- Asserts that the tag is not already occupied. Marks the tree dirty so the
-- next `tick` rebuilds the sorted node array.
-- @param tree table   The softtree to insert into.
-- @param tag  string  Unique string key for the node. Defaults to `tostring(node)` when `nil`.
-- @param node table   The node to insert.
local function insert(tree, tag, node)
	tag = tag or tostring(node)
	assert(tree.nodeDict[tag] == nil)
	tree.nodeDict[tag] = node
	tree.dirty = true
end

--- Removes a node from the tree if its tag maps to the given node.
-- Silently does nothing if the tag is absent or maps to a different node.
-- Marks the tree dirty so the next `tick` rebuilds the sorted node array.
-- @param tree table   The softtree to remove from.
-- @param tag  string  Tag key of the node to remove. Defaults to `tostring(node)` when `nil`.
-- @param node table   The node expected at `tag`; removal is skipped if the tag maps elsewhere.
local function remove(tree, tag, node)
	tag = tag or tostring(node)
	if tree.nodeDict[tag] == node then
		tree.nodeDict[tag] = nil
		tree.dirty = true
	end
end

--- Computes and assigns the depth of every node in the sorted node array.
-- Depth is defined as 1 for root nodes (those with no parent tags) and
-- `max(parent.depth) + 1` for all others. Also updates `tree.depth` to the
-- maximum depth found.
-- @param tree table  The softtree whose node depths are to be recalculated.
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

--- Rebuilds the `parents` and `children` tables for every node in `nodeDict`.
-- Clears all existing parent/child references before re-deriving them from
-- each node's `parentTags` list. Tags that do not resolve to a node in
-- `nodeDict` are silently skipped.
-- @param nodeDict table  A tag-to-node mapping (e.g., `tree.nodeDict`).
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

--- Produces a topologically sorted array of nodes from `nodeDict`.
-- Uses Kahn's algorithm (in-degree reduction). Asserts that the graph is
-- acyclic; a cycle causes the assertion `sorted == count` to fail.
-- @param nodeDict table  A tag-to-node mapping whose nodes have up-to-date `parentTags` and `children`.
-- @return table  An array of all nodes ordered so every parent precedes its children.
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

--- Invokes a named lifecycle callback on a node if it is defined.
-- Builds a `params` table mapping each parent tag to its read-only `const`
-- view, then calls `node[funcname](node.entity, params)`.
-- @param node     table   The node whose callback is to be activated.
-- @param funcname string  Name of the callback field (`"load"`, `"update"`, or `"run"`).
local function _activateFunc(node, funcname)
	if node[funcname] ~= nil then
		local params = {}
		for tag, parent in pairs(node.parents) do
			params[tag] = parent.const
		end
		node[funcname](node.entity, params)
	end
end

--- Propagates staleness and dirtiness from parents to children in topological order.
-- A stale node marks all its children both stale and dirty. A non-stale but
-- dirty node marks all its children dirty only. Traversal assumes `nodeArray`
-- is already topologically sorted.
-- @param nodeArray table  A topologically sorted array of nodes (e.g., `tree.nodeArray`).
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

--- Advances the tree by one tick, invoking all pending lifecycle callbacks.
-- Rebuilds the sorted node array and depth data when the tree is marked dirty.
-- Then spreads staleness/dirtiness, calls `load` on stale nodes (clearing
-- stale, setting dirty), calls `update` on dirty nodes (clearing dirty), and
-- calls `run` on every node unconditionally.
-- @param tree table  The softtree to tick.
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
			node.dirty = true
		end
		if node.dirty then
			_activateFunc(node, "update")
			node.dirty = false
		end
		_activateFunc(node, "run")
	end
end

--- Retrieves the node registered under the given tag.
-- Returns `nil` if no node is registered under `tag`.
-- @param tree table   The softtree to query.
-- @param tag  string  The tag key to look up.
-- @return table|nil  The node associated with `tag`, or `nil` if absent.
local function getTagged(tree, tag)
	return tree.nodeDict[tag]
end

--- Marks the node registered under `tag` as stale.
-- A stale node will have its `load` callback invoked on the next `tick`,
-- and its dirtiness and staleness will propagate to its children via `_spread`.
-- @param tree table   The softtree containing the target node.
-- @param tag  string  The tag key of the node to mark stale.
local function setStale(tree, tag)
	tree.nodeDict[tag].stale = true
end

--- Marks the node registered under `tag` as dirty.
-- A dirty node will have its `update` callback invoked on the next `tick`.
-- Dirtiness propagates to children via `_spread`.
-- @param tree table   The softtree containing the target node.
-- @param tag  string  The tag key of the node to mark dirty.
local function setDirty(tree, tag)
	tree.nodeDict[tag].dirty = true
end

--- Generates a Mermaid graph definition for the tree's current node structure.
-- Each node is represented by its pointer address as a unique identifier and
-- its tag as a display label. Only edges whose parent tag resolves to a node
-- in `nodeDict` are emitted.
-- @param tree table  The softtree to visualize.
-- @return string  A Mermaid `graph` definition string suitable for rendering.
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

--- Creates a new, empty softtree with a pre-inserted root node.
-- The returned tree is write-protected at the top level. The root node is
-- inserted under the tag `"root"` and serves as the conventional ancestor
-- for all other nodes in the graph.
-- @return table  A new softtree table with `insert`, `remove`, `tick`,
--                `getTagged`, `getMermaid`, `setStale`, `setDirty`, and
--                `spread` methods bound to it.
-- @usage
--   local softtree = require("softtree")
--   local tree = softtree.newTree()
--   local node = softtree.newNode({"root"}, {value = 0},
--     function(entity, parents) entity.value = 1 end,
--     function(entity, parents) print(entity.value) end
--   )
--   tree:insert("myNode", node)
--   tree:tick()
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
