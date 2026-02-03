MoistureUpdateEvent = {}
MoistureUpdateEvent_mt = Class(MoistureUpdateEvent, Event)

InitEventClass(MoistureUpdateEvent, "MoistureUpdateEvent")

function MoistureUpdateEvent.emptyNew()
    local self = Event.new(MoistureUpdateEvent_mt)
    return self
end

function MoistureUpdateEvent.new(moisturePercent)
    local self = MoistureUpdateEvent.emptyNew()
    self.moisturePercent = moisturePercent
    return self
end

function MoistureUpdateEvent:writeStream(streamId, connection)
    streamWriteFloat32(streamId, self.moisturePercent)
end

function MoistureUpdateEvent:readStream(streamId, connection)
    self.moisturePercent = streamReadFloat32(streamId)
    self:run(connection)
end

function MoistureUpdateEvent:run(connection)
    if not connection:getIsServer() then
        g_server:broadcastEvent(MoistureUpdateEvent.new(self.moisturePercent))
    end

    g_currentMission.MoistureSystem.currentMoisturePercent = self.moisturePercent
    
    -- Clear moisture position cache since base moisture changed
    -- loc1al cacheSize = #g_currentMission.MoistureSystem.moistureCacheOrder
    g_currentMission.MoistureSystem.moistureCache = {}
    g_currentMission.MoistureSystem.moistureCacheOrder = {}
    -- print(string.format("[MoistureCache] CLEARED: All %d entries (moisture updated to %.1f%%)", 
    --     cacheSize, self.moisturePercent * 100))
end
