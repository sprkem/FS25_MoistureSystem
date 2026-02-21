MSInitialClientStateEvent = {}
local MSInitialClientStateEvent_mt = Class(MSInitialClientStateEvent, Event)

InitEventClass(MSInitialClientStateEvent, "MSInitialClientStateEvent")

function MSInitialClientStateEvent.emptyNew()
    return Event.new(MSInitialClientStateEvent_mt)
end

function MSInitialClientStateEvent.new()
    return MSInitialClientStateEvent.emptyNew()
end

function MSInitialClientStateEvent:writeStream(streamId, connection)
    -- Write MoistureSystem data
    g_currentMission.MoistureSystem:writeInitialClientState(streamId, connection)

    -- Write subsystem data
    if g_currentMission.baleRottingSystem then
        g_currentMission.baleRottingSystem:writeInitialClientState(streamId, connection)
    end

    if g_currentMission.groundPropertyTracker then
        g_currentMission.groundPropertyTracker:writeInitialClientState(streamId, connection)
    end
end

function MSInitialClientStateEvent:readStream(streamId, connection)
    -- Read MoistureSystem data
    g_currentMission.MoistureSystem:readInitialClientState(streamId, connection)

    -- Read subsystem data
    if g_currentMission.baleRottingSystem then
        g_currentMission.baleRottingSystem:readInitialClientState(streamId, connection)
    end

    if g_currentMission.groundPropertyTracker then
        g_currentMission.groundPropertyTracker:readInitialClientState(streamId, connection)
    end

    self:run(connection)
end

function MSInitialClientStateEvent:run(connection)
    -- Trigger any post-sync updates if needed
end
