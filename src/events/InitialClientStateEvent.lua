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

    -- Subsystem data (pile, object moisture, bale rotting) is loaded on-demand
end

function MSInitialClientStateEvent:readStream(streamId, connection)
    -- Read MoistureSystem data
    g_currentMission.MoistureSystem:readInitialClientState(streamId, connection)


    self:run(connection)
end

function MSInitialClientStateEvent:run(connection)
    -- Trigger any post-sync updates if needed
end
