local softtree = {}

-- Returns a read-only proxy table for a given table
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

-- Creates a new node with the given parameters
local function _newNode(parentTags, entity, load, update)
    local node = {
        parentTags = parentTags or {},
        entity = entity or {},
        dirty = true,
        depth = 0,

        load = load,
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

-- Inserts a new node into the tree
local function insert(tree, tag, parentTags, entity, load, update)
    local node = _newNode(parentTags, entity, load, update)
    tag = tag or tostring(entity)
    assert(tree.nodeDict[tag] == nil)
    tree.nodeDict[tag] = node
    tree.dirty = true
end

-- Removes a node from the tree by tag or entity
local function remove(tree, tag, entity)
    tag = tag or tostring(entity)
    if tree.nodeDict[tag] ~= nil then
        tree.nodeDict[tag] = nil
        tree.dirty = true
    end
end

-- Sets the depth of each node and the tree
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

-- Establishes parent-child relationships between nodes
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

-- Returns a topologically sorted array of nodes
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

-- Activates a specific function on a node with parent constants as parameters
local function _activateFunc(node, funcname)
    if node[funcname] ~= nil then
        local params = {}
        for tag, parent in pairs(node.parents) do
            params[tag] = parent.const
        end
        node[funcname](node.entity, params)
    end
end

-- Propagates dirty flag from nodes to their children
local function spread(tree)
    for _, node in ipairs(tree.nodeArray) do
        if node.dirty then
            for _, child in pairs(node.children) do
                child.dirty = true
            end
        end
    end
end

-- Updates the tree structure and activates node functions
local function updateTree(tree)
    if tree.dirty then
        _setParentsAndChildren(tree.nodeDict)
        tree.nodeArray = _getOptimizedNodeArray(tree.nodeDict)
        _setDepth(tree)
        tree.dirty = false
    end

    spread(tree)

    for _, node in ipairs(tree.nodeArray) do
        if node.dirty then
            _activateFunc(node, "load")
            node.dirty = false
        end
        _activateFunc(node, "update")
    end
end

-- Returns the entity of a node identified by tag
local function getTagged(tree, tag)
    return tree.nodeDict[tag].entity
end

-- Marks a node as dirty by tag
local function setDirty(tree, tag)
    tree.nodeDict[tag].dirty = true
end

-- Generates a Mermaid diagram string representing the tree
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

-- Creates and returns a new SoftTree instance
function softtree.newTree()
    local tree = {
        dirty = true,
        nodeDict = {},
        nodeArray = {},
        depth = 0,

        insert = insert,
        remove = remove,
        update = updateTree,

        getTagged = getTagged,
        getMermaid = getMermaid,

        setDirty = setDirty,
        spread = spread,
    }
    tree:insert("root", nil, {})
    return tree
end

return softtree