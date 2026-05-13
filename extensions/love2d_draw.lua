local font1 = love.graphics.newFont(24)
local font2 = love.graphics.newFont(12)
local dirtyColor = { 0.6, 0.2, 0.2 }
local cleanColor = { 0.2, 0.5, 0.3 }
local shineColor = { 0.9, 0.8, 0.2 }
local nightColor = { 0.1, 0.1, 0.12 }
local lightColor = { 0.95, 0.95, 0.9 }
local scaleMax = 1
local scaleMin = 0.5

local function lpairs(t)
	local keys = {}
	for k in pairs(t) do
		table.insert(keys, tostring(k))
	end
	table.sort(keys)

	local i = 0
	return function()
		i = i + 1
		if keys[i] then
			return keys[i], t[keys[i]]
		end
	end
end

local function dump(tab, depth, result)
	result = result or { "{" }
	for key, value in lpairs(tab) do
		if type(value) == "table" and depth > 0 then
			table.insert(result, key .. " = {")
			dump(value, depth - 1, result)
		else
			table.insert(result, key .. " = " .. tostring(value))
		end
	end
	table.insert(result, "}")
	return result
end

local function actv(t)
	return math.tanh(t / 2)
end

local function calc(tree)
	local mesh = {}
	for tag, node in pairs(tree.nodeDict) do
		mesh[node.depth] = mesh[node.depth] or {}
		table.insert(mesh[node.depth], tag)
	end

	local visual = {}
	local winW, winH = love.graphics.getDimensions()
	local mouseX, mouseY = love.mouse.getPosition()

	local nodeH = winH / (tree.depth + 1)
	local k = 1
	for i = 1, #mesh do
		local nodeW = winW / (#mesh[i] + 1) * k
		for j = 1, #mesh[i] do
			local tag = mesh[i][j]
			local info = {
				node = tree.nodeDict[tag],
				x = j * nodeW + winW * (1 - k),
				y = i * nodeH,
				text = love.graphics.newText(font1, tag),
			}
			info.d = ((mouseX - info.x) / nodeW) ^ 2 + ((mouseY - info.y) / nodeH) ^ 2
			info.s = scaleMax + (scaleMin - scaleMax) * actv(info.d)
			info.w = info.s * info.text:getWidth()
			info.h = info.s * info.text:getHeight()
			info.r = info.s * font1:getHeight() / 2
			if not tree.nodeDict[tag].dirty then
				info.c = cleanColor
			else
				info.c = dirtyColor
			end
			visual[tag] = info
		end
	end
	return visual
end

local function comp(info, jnfo)
	return info.s < jnfo.s
end

local function drawEntity(tab, depth, indent)
	depth = depth or 0
	indent = indent or 16
	local strings = dump(tab, depth)
	local x, y = 0, (love.graphics.getHeight() - font2:getHeight() * #strings) / 2
	for _, string in ipairs(strings) do
		if string == "}" then
			x = x - indent
		end

		local text = love.graphics.newText(font2, string)
		love.graphics.setColor(nightColor)
		love.graphics.rectangle("fill", x, y, text:getWidth(), text:getHeight())

		love.graphics.setColor(lightColor)
		love.graphics.draw(text, x, y)

		y = y + text:getHeight()

		if string.match(string, "{") then
			x = x + indent
		end
	end
end

local function drawEdge(info1, info2, theme)
	love.graphics.setColor(theme or lightColor)
	love.graphics.line(info1.x, info1.y, info2.x, info2.y)
end

local function drawNode(info, theme)
	love.graphics.setColor(nightColor)
	love.graphics.circle("fill", info.x, info.y, info.r)

	love.graphics.setColor(theme or lightColor)
	love.graphics.circle("line", info.x, info.y, info.r)

	love.graphics.setColor(info.c)
	love.graphics.rectangle("fill", info.x, info.y, info.w, info.h)

	love.graphics.setColor(theme or lightColor)
	love.graphics.draw(info.text, info.x, info.y, 0, info.s, info.s)
end

local function draw(tree, visual)
	local mouseX, mouseY = love.mouse.getPosition()
	local indices = {}
	for _, info in pairs(visual) do
		indices[#indices + 1] = info
	end
	table.sort(indices, comp)

	for tag, node in pairs(tree.nodeDict) do
		local info1 = visual[tag]
		for tag2, _ in pairs(node.children) do
			local info2 = visual[tag2]
			drawEdge(info1, info2)
		end
	end

	for _, info in ipairs(indices) do
		drawNode(info)
	end

	for _, info in pairs(visual) do
		local dist = (mouseX - info.x) ^ 2 + (mouseY - info.y) ^ 2
		if dist < info.r ^ 2 then
			drawEntity(info.node.entity)
			for tag2, _ in pairs(info.node.children) do
				drawEdge(info, visual[tag2], shineColor)
			end
			for tag2, _ in pairs(info.node.parents) do
				drawEdge(info, visual[tag2], shineColor)
			end
			drawNode(info, shineColor)
			break
		end
	end
end

local function soft(tree)
	love.graphics.push("all")
	love.graphics.setLineWidth(1)
	local visual = calc(tree)
	draw(tree, visual)
	love.graphics.pop()
end

return soft
