PilePropertyResponseEvent = {}
PilePropertyResponseEvent_mt = Class(PilePropertyResponseEvent, Event)

InitEventClass(PilePropertyResponseEvent, "PilePropertyResponseEvent")

function PilePropertyResponseEvent.emptyNew()
    return Event.new(PilePropertyResponseEvent_mt)
end

function PilePropertyResponseEvent.new(gridX, gridZ, fillTypeIndex, moisture)
    local self = PilePropertyResponseEvent.emptyNew()
    self.gridX = gridX
    self.gridZ = gridZ
    self.fillTypeIndex = fillTypeIndex
    self.moisture = moisture
    return self
end

function PilePropertyResponseEvent:writeStream(streamId, connection)
    streamWriteFloat32(streamId, self.gridX)
    streamWriteFloat32(streamId, self.gridZ)
    streamWriteInt32(streamId, self.fillTypeIndex)
    streamWriteBool(streamId, self.moisture ~= nil)
    if self.moisture ~= nil then
        streamWriteFloat32(streamId, self.moisture)
    end
end

function PilePropertyResponseEvent:readStream(streamId, connection)
    self.gridX = streamReadFloat32(streamId)
    self.gridZ = streamReadFloat32(streamId)
    self.fillTypeIndex = streamReadInt32(streamId)
    local hasMoisture = streamReadBool(streamId)
    if hasMoisture then
        self.moisture = streamReadFloat32(streamId)
    end
    self:run(connection)
end

function PilePropertyResponseEvent:run(connection)
    local tracker = g_currentMission.groundPropertyTracker
    local key = tracker:getGridKey(self.gridX, self.gridZ, self.fillTypeIndex)

    tracker.pileCache[key] = {
        moisture = self.moisture,
        timestamp = g_time
    }
    tracker.pendingPileRequests[key] = nil
end
