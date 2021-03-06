local lanes = require "lanes"

local DEFAULT_LINDA_KEY = require "PuRest.Util.Threading.defaultLindaKey"

local DEFAULT_TIMEOUT = 30 -- TODO: consider a better value for this

--- Provides a lightweight Semaphore built on a thread queue.
-- Call the object with no parameters to get value lock then pass
-- the new value back to release the lock.
--
-- e.x. Get value and hold lock: value = object()
--      Set value and release lock: object(value)
--
-- @param threadQueue optional An existing thread queue to use
-- @param initalValue optional The inital value to place in the thread queue.
-- @param isBinarySemaphore optional Should this semaphore only hold one value?
--                                   (Not a restriction just a flag)
--
local function Semaphore (threadQueue, initalValue, isBinarySemaphore)
	local threadQueue = threadQueue or lanes.linda()
	local binarySemaphore = isBinarySemaphore or false
	local holdingLock = false
	local lastPoppedValue

	if initalValue then
		threadQueue:send(DEFAULT_LINDA_KEY, initalValue)
	end

    --- Get the thread queue being used by this semaphore.
    --
    -- @return The underlying thread queue.
    --
	local function getThreadQueue ()
		return threadQueue
	end

    --- Should this semaphore only hold one value?
    --  (Not a restriction just a flag)
    --
    -- @return True if only one value should be stored in
    --         this semaphore, otherwise false.
    --
	local function isBinarySemaphore ()
		return binarySemaphore
	end

    --- Is this semaphore instance holding the lock on a thread
    --  queue marked with the binary semaphore flag.
    --
    -- @return True if holding lock, false otherwise.
    --
	local function isHoldingLock ()
		if not binarySemaphore then
			error("You can only check resource locks for binary semaphores.")
		end

		return holdingLock
	end

	return setmetatable(
		{
			getThreadQueue = getThreadQueue,
			isBinarySemaphore = isBinarySemaphore,
			isHoldingLock = isHoldingLock
		},
		{
            --- Hold a lock and get the value or release a lock and set the value.
            -- If binary semaphore flag is on this also denotes if lock is held in
            -- holdingLock field.
            --
            -- @param value optional Value to push onto the queue.
            -- @return Nothing if releasing lock, value from front of queue otherwise.
            --
			__call = function (_, value)
				if value or lastPoppedValue then
					threadQueue:send(DEFAULT_LINDA_KEY, value or lastPoppedValue)
					lastPoppedValue = nil

					if binarySemaphore then
						holdingLock = false
					end
				else
					local _, val, err = threadQueue:receive(DEFAULT_TIMEOUT, DEFAULT_LINDA_KEY)
					
					-- If pop method was interrupted it will need to be called again.
					while val == nil or err do
						_, val, err = threadQueue:receive(DEFAULT_TIMEOUT, DEFAULT_LINDA_KEY)
					end

					lastPoppedValue = val

					if binarySemaphore then
						holdingLock = true
					end

					return val
				end
			end
		})
end

return Semaphore
