local softtree = require("softtree")
local love = require("love")
local tree = softtree.newTree()


local function add(entity, parents)
    entity.value = 0
    for _, parent in ipairs(parents) do
        entity.value = entity.value + parent.value
    end
end

local nodeX = softtree.newNode({tree.root}, {value = 1})
local nodeY = softtree.newNode({tree.root}, {value = 2})
local nodeAdd = softtree.newNode({nodeX, nodeY}, {value = 0}, nil, nil, add)
local nodeMul = softtree.newNode({nodeAdd, nodeY}, {value = 0}, nil, nil, nil)
local nodeZ = softtree.newNode({nodeMul}, {value = 0}, nil, nil, nil)

tree:insert(nodeX, "x")
tree:insert(nodeY, "y")
tree:insert(nodeAdd, "x+y")
tree:insert(nodeMul, "(x+y)*y")
tree:insert(nodeZ, "z")

local function dump(t, keys, indent)
    indent = indent or 0
	local spacing = string.rep("  ", indent)
	local next_spacing = string.rep("  ", indent + 1)
	local result = {}

	-- 确定要遍历的范围
	local target_keys = keys
	if not target_keys then
		target_keys = {}
		for k in pairs(t) do
			table.insert(target_keys, k)
		end
	end

	table.insert(result, "{")

	for _, k in ipairs(target_keys) do
		local v = t[k]
		local key_str = string.format("%s", tostring(k))

		if type(v) == "table" then
			-- 递归处理嵌套 table
			table.insert(result, string.format("%s%s = %s", next_spacing, key_str, dump(v, nil, indent + 1)))
		else
			-- 处理基础类型 (string 需要加引号)
			local val_str = type(v) == "string" and string.format('"%s"', v) or tostring(v)
			table.insert(result, string.format("%s%s = %s", next_spacing, key_str, val_str))
		end
	end

	table.insert(result, spacing .. "}")
	return table.concat(result, "\n")
end

function love.load()
    tree:load()
end

function love.update(dt)
    nodeX.entity.value = dt
    nodeX.dirty = true
    tree:update()
end

function love.draw()
    love.graphics.print(dump({nodeX.entity, nodeY.entity, nodeAdd.entity, nodeMul.entity, nodeZ.entity}))
end
