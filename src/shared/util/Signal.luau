--!strict
-- Minimal signal. Handlers run in their own thread so one failure cannot break others.

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

type Handler = (...any) -> ()

export type Signal = {
	Connect: (self: Signal, handler: Handler) -> Connection,
	Once: (self: Signal, handler: Handler) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	Wait: (self: Signal) -> ...any,
	DisconnectAll: (self: Signal) -> (),
}

type SignalImpl = Signal & {
	_handlers: { [Connection]: Handler },
}

local Signal = {}
Signal.__index = Signal

function Signal.new(): Signal
	local self = setmetatable({ _handlers = {} }, Signal)
	return (self :: any) :: Signal
end

function Signal.Connect(self: SignalImpl, handler: Handler): Connection
	local connection = {} :: any
	connection.Connected = true
	function connection.Disconnect(conn: Connection)
		conn.Connected = false
		self._handlers[conn] = nil
	end
	self._handlers[connection] = handler
	return connection
end

function Signal.Once(self: SignalImpl, handler: Handler): Connection
	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal.Fire(self: SignalImpl, ...: any)
	for _, handler in self._handlers do
		task.spawn(handler, ...)
	end
end

function Signal.Wait(self: SignalImpl): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal.DisconnectAll(self: SignalImpl)
	for connection in self._handlers do
		connection.Connected = false
	end
	table.clear(self._handlers)
end

return Signal
