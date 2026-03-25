BaleRottingRequestEvent = {}
BaleRottingRequestEvent_mt = Class(BaleRottingRequestEvent, Event)

InitEventClass(BaleRottingRequestEvent, "BaleRottingRequestEvent")

function BaleRottingRequestEvent.emptyNew()
    return Event.new(BaleRottingRequestEvent_mt)
end

function BaleRottingRequestEvent.new(objectId)
    local self = BaleRottingRequestEvent.emptyNew()
    self.objectId = objectId
    return self
end

function BaleRottingRequestEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.objectId)
end

function BaleRottingRequestEvent:readStream(streamId, connection)
    self.objectId = streamReadInt32(streamId)
    self:run(connection)
end

function BaleRottingRequestEvent:run(connection)
    if not g_currentMission:getIsServer() then return end

    local object = NetworkUtil.getObject(self.objectId)
    if object == nil or object.uniqueId == nil then return end

    local brs = g_currentMission.baleRottingSystem
    local data = brs.baleRainExposureTimes[object.uniqueId]

    connection:sendEvent(BaleRottingResponseEvent.new(self.objectId, data))
end
