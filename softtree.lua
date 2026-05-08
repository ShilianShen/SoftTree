local softtree = {}

--- Wraps a table to make it read-only via a proxy. Complexity: O(1).
--- @param t table The table to be protected.
--- @return table A read-only proxy table.
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

--- Creates a new tree node with specified lifecycle callbacks. Complexity: O(1).
--- @param parentTags table|nil List of tags representing parent nodes.
--- @param entity table|nil The data object associated with this node.
--- @param load function|nil Callback triggered when the node is loaded.
--- @param unload function|nil Callback triggered when the node is unloaded.
--- @param update function|nil Callback triggered when the node is updated.
--- @return table The initialized node object.
function softtree.newNode(parentTags, entity, load, unload, update)
    local node = {
        parentTags = parentTags or {},
        entity = entity or {},
        ready = false,
        dirty = true,
        depth = 0,

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

--- Inserts a node into the tree's dictionary. Complexity: O(1).
--- @param tree table The tree instance.
--- @param tag string|nil Unique identifier for the node.
--- @param node table The node instance to insert.
local function insert(tree, tag, node)
    tag = tag or tostring(node)
    assert(tree.nodeDict[tag] == nil)
    tree.nodeDict[tag] = node
    tree.dirty = true
end

--- Removes a node from the tree's dictionary by tag. Complexity: O(1).
--- @param tree table The tree instance.
--- @param tag string|nil Unique identifier of the node.
--- @param node table The node instance to remove.
local function remove(tree, tag, node)
    tag = tag or tostring(node)
    if tree.nodeDict[tag] == node then
        tree.nodeDict[tag] = nil
        tree.dirty = true
    end
end

--- Rebuilds parent and child references for all nodes in the dictionary. Complexity: O(n+m).
--- @param nodeDict table Dictionary of all nodes in the tree.
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

--- Performs a topological sort to return an optimized execution array. Complexity: O(n^2).
--- @param nodeDict table Dictionary of nodes to sort.
--- @return table A list of nodes in dependency order.
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

--- Calculates and sets the hierarchical depth for each node and the tree itself. Complexity: O(n).
--- @param tree table The tree instance.
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

--- Executes a specific lifecycle function on a node. Complexity: O(\delta^-(x)).
--- @param node table The target node.
--- @param funcname string The name of the function to invoke (e.g., "load", "update").
local function activateFunc(node, funcname)
    if node[funcname] ~= nil then
        local params = {}
        for tag, parent in pairs(node.parents) do
            params[tag] = parent.const
        end
        node[funcname](node.entity, params)
    end
end

--- Rebuilds the tree structure and triggers 'load' for all nodes. Complexity: O(n).
--- @param tree table The tree instance.
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

--- Triggers 'unload' for all nodes and clears the execution array. Complexity: O(n).
--- @param tree table The tree instance.
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

--- Updates dirty nodes and propagates dirtiness through the hierarchy. Complexity: O(n + m).
--- @param tree table The tree instance.
local function updateTree(tree)
    if tree.dirty then
        setParentsAndChildren(tree.nodeDict)
        tree.nodeArray = getOptimizedNodeArray(tree.nodeDict)
        setDepth(tree)
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

--- Retrieves a specific tag from the tree. Complexity: O(1).
--- @param tree table The tree instance.
--- @param tag string The identifier to look up.
--- @return table|nil The node associated with the tag.
local function getTagged(tree, tag)
    return tree.nodeDict[tag]
end

local function setDirty(tree, tag)
    tree.nodeDict[tag].dirty = true
end

--- Generates a Mermaid.js graph string representing the tree structure. Complexity: O(n+m).
--- @param tree table The tree instance to visualize.
--- @return string A string formatted in Mermaid syntax for graph rendering.
local function getMermaid(tree)
    local mermaid = { "graph" }
    for tag, node in pairs(tree.nodeDict) do
        -- Use pointer addresses as unique IDs for Mermaid nodes
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

--- Initializes a new softtree instance. Complexity: O(1).
--- @return table The new tree object.
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
        unload = unloadTree,
        update = updateTree,
        getTagged = getTagged,
        setDirty = setDirty,
        
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
