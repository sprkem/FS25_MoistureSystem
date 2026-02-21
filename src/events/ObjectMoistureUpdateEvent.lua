ObjectMoistureUpdateEvent = {}
ObjectMoistureUpdateEvent_mt = Class(ObjectMoistureUpdateEvent, Event)

InitEventClass(ObjectMoistureUpdateEvent, "ObjectMoistureUpdateEvent")

function ObjectMoistureUpdateEvent.emptyNew()
    local self = Event.new(ObjectMoistureUpdateEvent_mt)
    return self
end

function ObjectMoistureUpdateEvent.new(uniqueId, fillTypeName, moisture)
    local self = ObjectMoistureUpdateEvent.emptyNew()
    self.uniqueId = uniqueId
    self.fillTypeName = fillTypeName
    self.moisture = moisture
    return self
end

function ObjectMoistureUpdateEvent:writeStream(streamId, connection)
    local object = g_currentMission:getObjectByUniqueId(self.uniqueId)
    NetworkUtil.writeNodeObject(streamId, object)
    streamWriteString(streamId, self.fillTypeName)

    -- Write nil flag first
    local hasMoisture = self.moisture ~= nil
    streamWriteBool(streamId, hasMoisture)
    if hasMoisture then
        streamWriteFloat32(streamId, self.moisture)
    end
end

function ObjectMoistureUpdateEvent:readStream(streamId, connection)
    local object = NetworkUtil.readNodeObject(streamId)
    self.uniqueId = object.uniqueId

    self.fillTypeName = streamReadString(streamId)

    local hasMoisture = streamReadBool(streamId)
    if hasMoisture then
        self.moisture = streamReadFloat32(streamId)
    else
        self.moisture = nil
    end

    self:run(connection)
end

function ObjectMoistureUpdateEvent:run(connection)
    if not connection:getIsServer() then
        g_server:broadcastEvent(ObjectMoistureUpdateEvent.new(self.uniqueId, self.fillTypeName, self.moisture))
        return -- Server already updated locally in setObjectMoisture()
    end

    local ms = g_currentMission.MoistureSystem

    if ms.objectMoisture[self.uniqueId] == nil then
        ms.objectMoisture[self.uniqueId] = {}
    end

    ms.objectMoisture[self.uniqueId][self.fillTypeName] = self.moisture
end
