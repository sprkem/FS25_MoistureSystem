PilePropertyRequestEvent = {}
PilePropertyRequestEvent_mt = Class(PilePropertyRequestEvent, Event)

InitEventClass(PilePropertyRequestEvent, "PilePropertyRequestEvent")

function PilePropertyRequestEvent.emptyNew()
    return Event.new(PilePropertyRequestEvent_mt)
end

function PilePropertyRequestEvent.new(gridX, gridZ, fillTypeIndex)
    local self = PilePropertyRequestEvent.emptyNew()
    self.gridX = gridX
    self.gridZ = gridZ
    self.fillTypeIndex = fillTypeIndex
    return self
end

function PilePropertyRequestEvent:writeStream(streamId, connection)
    streamWriteFloat32(streamId, self.gridX)
    streamWriteFloat32(streamId, self.gridZ)
    streamWriteInt32(streamId, self.fillTypeIndex)
end

function PilePropertyRequestEvent:readStream(streamId, connection)
    self.gridX = streamReadFloat32(streamId)
    self.gridZ = streamReadFloat32(streamId)
    self.fillTypeIndex = streamReadInt32(streamId)
    self:run(connection)
end

function PilePropertyRequestEvent:run(connection)
    if not g_currentMission:getIsServer() then return end

    local tracker = g_currentMission.groundPropertyTracker
    local key = tracker:getGridKey(self.gridX, self.gridZ, self.fillTypeIndex)
    local storage = tracker:getStorageForFillType(self.fillTypeIndex)
    local pile = storage[key]

    local moisture = nil
    if pile and pile.properties then
        moisture = pile.properties.moisture
    end

    connection:sendEvent(PilePropertyResponseEvent.new(self.gridX, self.gridZ, self.fillTypeIndex, moisture))
end
