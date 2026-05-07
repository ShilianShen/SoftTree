local softtree = {}

--- Creates a read-only proxy for a table.
--- @param t table The table to be protected.
--- @return table A proxy table that throws an error on modification.
--- @time O(1)
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

--- Creates a new node for the softtree.
--- @param parentTags table|nil List of tags representing parent nodes.
--- @param entity table|nil The data object associated with this node.
--- @param load function|nil Callback triggered when the node is loaded.
--- @param unload function|nil Callback triggered when the node is unloaded.
--- @param update function|nil Callback triggered during the update cycle.
--- @return table The initialized node object.
--- @time O(1)
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

--- Inserts a node into the tree's dictionary.
--- @param tree table The tree instance.
--- @param tag string|nil Unique identifier for the node. Defaults to node's string representation.
--- @param node table The node object to insert.
--- @time O(1)
local function insert(tree, tag, node)
    tag = tag or tostring(node)
    assert(tree.nodeDict[tag] == nil)
    tree.nodeDict[tag] = node
    tree.dirty = true
end

--- Removes a node from the tree's dictionary.
--- @param tree table The tree instance.
--- @param tag string|nil Unique identifier for the node.
--- @param node table The node object to remove.
--- @time O(1)
local function remove(tree, tag, node)
    tag = tag or tostring(node)
    if tree.nodeDict[tag] == node then
        tree.nodeDict[tag] = nil
        tree.dirty = true
    end
end

--- Rebuilds the parent-child relationships between nodes based on parentTags.
--- @param nodeDict table The dictionary containing all nodes in the tree.
--- @time O(n + m) where n is number of nodes and m is number of edges.
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

--- Performs a topological sort to return an array of nodes in dependency order.
--- @param nodeDict table The dictionary of nodes.
--- @return table An ordered array of nodes.
--- @time O(n^2) due to the iterative search for zero in-degree nodes.
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

--- Executes a specific lifecycle function on a node, passing parent data as read-only proxies.
--- @param node table The target node.
--- @param funcname string The name of the function to execute (e.g., "load", "update").
--- @time O(\delta^-(x)) proportional to the number of parents.
local function activateFunc(node, funcname)
    if node[funcname] ~= nil then
        local params = {}
        for tag, parent in pairs(node.parents) do
            params[tag] = parent.const
        end
        node[funcname](node.entity, params)
    end
end

--- Initializes the tree, sorts dependencies, and triggers the 'load' callback for all nodes.
--- @param tree table The tree instance.
--- @time O(n)
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

--- Triggers the 'unload' callback for all nodes and clears the execution order.
--- @param tree table The tree instance.
--- @time O(n)
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

--- Updates the tree state, rebuilding the graph if dirty and triggering 'update' callbacks.
--- @param tree table The tree instance.
--- @time O(n + m)
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

--- Retrieves a node from the tree by its tag.
--- @param tree table The tree instance.
--- @param tag string The node identifier.
--- @return table|nil The node if found.
--- @time O(1)
local function getTagged(tree, tag)
    return tree.nodeDict[tag]
end

--- Factory function to create and initialize a new softtree instance.
--- @return table The initialized tree object.
--- @time O(1)
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