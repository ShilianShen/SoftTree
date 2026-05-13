local font1 = love.graphics.newFont(24)
local font2 = love.graphics.newFont(12)
local dirtyColor = { 0.6, 0.2, 0.2 }
local cleanColor = { 0.2, 0.5, 0.3 }
local shineColor = { 0.9, 0.8, 0.2 }
local nightColor = { 0.1, 0.1, 0.12 }
local lightColor = { 0.95, 0.95, 0.9 }
local smooth = 0.5
local scaleMax = 1
local scaleMin = 0.5
local infoDict = {}
local mouseX, mouseY
local bufferT = 1
local winW, winH = 0, 0
local time = 0

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

local function calc(tree)
	-- remove
	for tag, _ in pairs(infoDict) do
		if tree.nodeDict[tag] == nil then
			infoDict[tag] = nil
		end
	end

	-- insert
	for tag, node in pairs(tree.nodeDict) do
		if infoDict[tag] == nil then
			infoDict[tag] = {
				node = node,
				text = love.graphics.newText(font1, tag),
			}
		end
	end

	-- mesh
	local mesh = {}
	for tag, node in pairs(tree.nodeDict) do
		mesh[node.depth] = mesh[node.depth] or {}
		table.insert(mesh[node.depth], tag)
	end
	for _, row in ipairs(mesh) do
		table.sort(row)
	end

	-- calc
	local nodeH = winH / (tree.depth + 1)
	local k = 1
	for i = 1, #mesh do
		local nodeW = winW / (#mesh[i] + 1) * k
		for j = 1, #mesh[i] do
			local tag = mesh[i][j]
			local info = infoDict[tag]
			local node = info.node
			info.x = j * nodeW + winW * (1 - k)
			info.y = i * nodeH
			info.d = ((mouseX - info.x) / nodeW) ^ 2 + ((mouseY - info.y) / nodeH) ^ 2
			info.s = scaleMax + (scaleMin - scaleMax) * math.tanh(info.d / 2)
			info.w = info.s * info.text:getWidth()
			info.h = info.s * info.text:getHeight()
			info.r = info.s * font1:getHeight() / 2
			info.t = node.dirty and time or (info.t or 0)
			info.k = math.max(0, 1 - (time - info.t) / bufferT)
		end
	end
end

local function merge(t1, t2)
	local t = {}
	for k, v in pairs(t1) do
		t[k] = v
	end
	for k, v in pairs(t2) do
		t[k] = v
	end
	return t
end

local function drawEntity(tab, depth, indent)
	depth = depth or 0
	indent = indent or 16
	local strings = dump(tab, depth)
	local x, y = 0, (love.graphics.getHeight() - font2:getHeight() * #strings) / 2
	love.graphics.setFont(font2)
	for _, string in ipairs(strings) do
		x = x - (string == "}" and indent or 0)
		love.graphics.setColor(nightColor)
		love.graphics.rectangle("fill", x, y, font2:getWidth(string), font2:getHeight())
		love.graphics.setColor(lightColor)
		love.graphics.print(string, x, y)
		y = y + font2:getHeight()
		x = x + (string.match(string, "{") and indent or 0)
	end
end

local function drawEdge(info1, info2, theme)
	love.graphics.setColor(theme or lightColor)
	local dy = smooth * (info2.y - info1.y)
	local vertices = { info1.x, info1.y, info1.x, info1.y + dy, info2.x, info2.y - dy, info2.x, info2.y }
	local curve = love.math.newBezierCurve(vertices)
	love.graphics.line(curve:render())
end

local function drawNode(info, theme)
	love.graphics.setColor(nightColor)
	love.graphics.circle("fill", info.x, info.y, info.r)

	love.graphics.setColor(theme or lightColor)
	love.graphics.circle("line", info.x, info.y, info.r)

	love.graphics.setColor(cleanColor)
	love.graphics.rectangle("fill", info.x, info.y, info.w, info.h)

	love.graphics.setColor(dirtyColor)
	love.graphics.rectangle("fill", info.x, info.y, info.w * info.k, info.h)

	love.graphics.setColor(theme or lightColor)
	love.graphics.draw(info.text, info.x, info.y, 0, info.s, info.s)
end

local function draw(tree)
	for tag, node in pairs(tree.nodeDict) do
		local info1 = infoDict[tag]
		for tag2, _ in pairs(node.children) do
			local info2 = infoDict[tag2]
			drawEdge(info1, info2)
		end
	end

	for _, info in pairs(infoDict) do
		drawNode(info)
	end

	for _, info in pairs(infoDict) do
		local dist = (mouseX - info.x) ^ 2 + (mouseY - info.y) ^ 2
		if dist < info.r ^ 2 then
			drawEntity(info.node.entity)
			love.graphics.setLineWidth(2)
			for tag2, _ in pairs(merge(info.node.children, info.node.parents)) do
				local info2 = infoDict[tag2]
				drawEdge(info, info2, shineColor)
			end
			for tag2, _ in pairs(merge(info.node.children, info.node.parents)) do
				local info2 = infoDict[tag2]
				drawNode(info2, shineColor)
			end
			drawNode(info, shineColor)
			break
		end
	end
end

local function call(tree)
	winW, winH = love.graphics.getDimensions()
	mouseX, mouseY = love.mouse.getPosition()
	time = love.timer.getTime()
	love.graphics.push("all")
	love.graphics.setLineWidth(1)
	calc(tree)
	draw(tree)
	love.graphics.pop()
end

return call
