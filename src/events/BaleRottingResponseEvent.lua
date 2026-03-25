BaleRottingResponseEvent = {}
BaleRottingResponseEvent_mt = Class(BaleRottingResponseEvent, Event)

InitEventClass(BaleRottingResponseEvent, "BaleRottingResponseEvent")

function BaleRottingResponseEvent.emptyNew()
    return Event.new(BaleRottingResponseEvent_mt)
end

function BaleRottingResponseEvent.new(objectId, baleData)
    local self = BaleRottingResponseEvent.emptyNew()
    self.objectId = objectId
    self.baleData = baleData
    return self
end

function BaleRottingResponseEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.objectId)
    streamWriteBool(streamId, self.baleData ~= nil)
    if self.baleData ~= nil then
        streamWriteFloat32(streamId, self.baleData.exposure)
        streamWriteFloat32(streamId, self.baleData.peakExposure)
        streamWriteInt32(streamId, self.baleData.status)
    end
end

function BaleRottingResponseEvent:readStream(streamId, connection)
    self.objectId = streamReadInt32(streamId)
    local hasData = streamReadBool(streamId)
    if hasData then
        self.baleData = {
            exposure = streamReadFloat32(streamId),
            peakExposure = streamReadFloat32(streamId),
            status = streamReadInt32(streamId)
        }
    end
    self:run(connection)
end

function BaleRottingResponseEvent:run(connection)
    local object = NetworkUtil.getObject(self.objectId)
    if object == nil or object.uniqueId == nil then return end

    local brs = g_currentMission.baleRottingSystem
    if self.baleData ~= nil then
        brs.baleRainExposureTimes[object.uniqueId] = self.baleData
    else
        brs.baleRainExposureTimes[object.uniqueId] = nil
    end
    brs.baleDataTimestamps[object.uniqueId] = g_time
    brs.pendingBaleRequests[object.uniqueId] = nil
end
