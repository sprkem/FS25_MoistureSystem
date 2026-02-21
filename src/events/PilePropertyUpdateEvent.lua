PilePropertyUpdateEvent = {}
PilePropertyUpdateEvent_mt = Class(PilePropertyUpdateEvent, Event)

InitEventClass(PilePropertyUpdateEvent, "PilePropertyUpdateEvent")

function PilePropertyUpdateEvent.emptyNew()
    local self = Event.new(PilePropertyUpdateEvent_mt)
    return self
end

function PilePropertyUpdateEvent.new(key, properties, fillTypeIndex, gridX, gridZ)
    local self = PilePropertyUpdateEvent.emptyNew()
    self.key = key
    self.properties = properties or {}
    self.fillTypeIndex = fillTypeIndex
    self.gridX = gridX
    self.gridZ = gridZ
    return self
end

function PilePropertyUpdateEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.key)
    streamWriteInt32(streamId, self.fillTypeIndex)
    streamWriteFloat32(streamId, self.gridX)
    streamWriteFloat32(streamId, self.gridZ)

    -- Write moisture property
    local hasMoisture = self.properties.moisture ~= nil
    streamWriteBool(streamId, hasMoisture)
    if hasMoisture then
        streamWriteFloat32(streamId, self.properties.moisture)
    end
end

function PilePropertyUpdateEvent:readStream(streamId, connection)
    self.key = streamReadString(streamId)
    self.fillTypeIndex = streamReadInt32(streamId)
    self.gridX = streamReadFloat32(streamId)
    self.gridZ = streamReadFloat32(streamId)

    self.properties = {}
    local hasMoisture = streamReadBool(streamId)
    if hasMoisture then
        self.properties.moisture = streamReadFloat32(streamId)
    end

    self:run(connection)
end

function PilePropertyUpdateEvent:run(connection)
    if not connection:getIsServer() then
        g_server:broadcastEvent(PilePropertyUpdateEvent.new(self.key, self.properties, self.fillTypeIndex, self.gridX, self.gridZ))
        return  -- Server already processes event when sent, avoid double-processing
    end

    -- Update or create pile (runs on server when sent, and on clients when broadcast received)
    local tracker = g_currentMission.groundPropertyTracker
    local moistureSystem = g_currentMission.MoistureSystem
    local storage

    if moistureSystem:isGrassOnGroundFillType(self.fillTypeIndex) then
        storage = tracker.grassPiles
    elseif moistureSystem:isHayFillType(self.fillTypeIndex) then
        storage = tracker.hayPiles
    elseif moistureSystem:isStrawFillType(self.fillTypeIndex) then
        storage = tracker.strawPiles
    else
        storage = tracker.gridPiles
    end

    storage[self.key] = {
        properties = self.properties,
        fillType = self.fillTypeIndex,
        gridX = self.gridX,
        gridZ = self.gridZ
    }
end
