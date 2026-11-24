-- Standalone GoodSignal-compatible signal.
-- Tokyo UI downloads this file to replace its broken Quenty dependency.

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

local function copyList(list)
	if table.clone then
		return table.clone(list)
	end

	local result = {}
	for index, value in ipairs(list) do
		result[index] = value
	end
	return result
end

function Signal.new()
	return setmetatable({
		_connections = {},
	}, Signal)
end

function Signal:Connect(handler)
	if type(handler) ~= "function" then
		error("Signal:Connect expects a function", 2)
	end

	local connection = setmetatable({
		Connected = true,
		_signal = self,
		_handler = handler,
	}, Connection)

	table.insert(self._connections, connection)
	return connection
end

function Signal:Once(handler)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal:Fire(...)
	local connections = self._connections
	local snapshot = copyList(connections)

	for _, connection in ipairs(snapshot) do
		if connection.Connected and connection._handler then
			local ok, err = pcall(connection._handler, ...)
			if not ok then
				warn("[Mad City] Signal handler failed: " .. tostring(err))
			end
		end
	end

	-- Compact connections that were disconnected while firing.
	local write = 1
	for read = 1, #connections do
		local connection = connections[read]
		if connection.Connected then
			connections[write] = connection
			write += 1
		end
	end
	for index = #connections, write, -1 do
		connections[index] = nil
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		if task and task.spawn then
			task.spawn(thread, ...)
		else
			coroutine.resume(thread, ...)
		end
	end)
	return coroutine.yield()
end

function Connection:Disconnect()
	if not self.Connected then
		return
	end

	self.Connected = false
	self._handler = nil
	self._signal = nil
end

function Connection:Destroy()
	self:Disconnect()
end

return Signal
