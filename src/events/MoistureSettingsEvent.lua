MoistureSettingsEvent = {}
MoistureSettingsEvent_mt = Class(MoistureSettingsEvent, Event)

InitEventClass(MoistureSettingsEvent, "MoistureSettingsEvent")

function MoistureSettingsEvent.emptyNew()
    local self = Event.new(MoistureSettingsEvent_mt)
    return self
end

function MoistureSettingsEvent.new()
    local self = MoistureSettingsEvent.emptyNew()
    self.environment = g_currentMission.MoistureSystem.settings.environment
    self.moistureLossMultiplier = g_currentMission.MoistureSystem.settings.moistureLossMultiplier
    self.moistureGainMultiplier = g_currentMission.MoistureSystem.settings.moistureGainMultiplier
    self.teddingMoistureReduction = g_currentMission.MoistureSystem.settings.teddingMoistureReduction
    self.baleRotEnabled = g_currentMission.MoistureSystem.settings.baleRotEnabled
    self.baleRotRate = g_currentMission.MoistureSystem.settings.baleRotRate
    self.baleGracePeriod = g_currentMission.MoistureSystem.settings.baleGracePeriod
    self.baleExposureDecayRate = g_currentMission.MoistureSystem.settings.baleExposureDecayRate
    self.showFieldMoisture = g_currentMission.MoistureSystem.settings.showFieldMoisture
    self.moistureMeterReporting = g_currentMission.MoistureSystem.settings.moistureMeterReporting
    return self
end

function MoistureSettingsEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.environment)
    streamWriteFloat32(streamId, self.moistureLossMultiplier)
    streamWriteFloat32(streamId, self.moistureGainMultiplier)
    streamWriteFloat32(streamId, self.teddingMoistureReduction)
    streamWriteBool(streamId, self.baleRotEnabled)
    streamWriteFloat32(streamId, self.baleRotRate)
    streamWriteInt32(streamId, self.baleGracePeriod)
    streamWriteFloat32(streamId, self.baleExposureDecayRate)
    streamWriteBool(streamId, self.showFieldMoisture)
    streamWriteInt32(streamId, self.moistureMeterReporting)
end

function MoistureSettingsEvent:readStream(streamId, connection)
    self.environment = streamReadInt32(streamId)
    self.moistureLossMultiplier = streamReadFloat32(streamId)
    self.moistureGainMultiplier = streamReadFloat32(streamId)
    self.teddingMoistureReduction = streamReadFloat32(streamId)
    self.baleRotEnabled = streamReadBool(streamId)
    self.baleRotRate = streamReadFloat32(streamId)
    self.baleGracePeriod = streamReadInt32(streamId)
    self.baleExposureDecayRate = streamReadFloat32(streamId)
    self.showFieldMoisture = streamReadBool(streamId)
    self.moistureMeterReporting = streamReadInt32(streamId)
    self:run(connection)
end

function MoistureSettingsEvent:run(connection)
    if not connection:getIsServer() then
        g_server:broadcastEvent(MoistureSettingsEvent.new())
    end

    g_currentMission.MoistureSystem.settings.environment = self.environment
    g_currentMission.MoistureSystem.settings.moistureLossMultiplier = self.moistureLossMultiplier
    g_currentMission.MoistureSystem.settings.moistureGainMultiplier = self.moistureGainMultiplier
    g_currentMission.MoistureSystem.settings.teddingMoistureReduction = self.teddingMoistureReduction
    g_currentMission.MoistureSystem.settings.baleRotEnabled = self.baleRotEnabled
    g_currentMission.MoistureSystem.settings.baleRotRate = self.baleRotRate
    g_currentMission.MoistureSystem.settings.baleGracePeriod = self.baleGracePeriod
    g_currentMission.MoistureSystem.settings.baleExposureDecayRate = self.baleExposureDecayRate
    g_currentMission.MoistureSystem.settings.showFieldMoisture = self.showFieldMoisture
    g_currentMission.MoistureSystem.settings.moistureMeterReporting = self.moistureMeterReporting

    if connection:getIsServer() then
        -- Update UI controls if they exist
        for _, id in pairs(MoistureSettings.menuItems) do
            local menuOption = MoistureSettings.CONTROLS[id]
            if menuOption then
                local isAdmin = g_currentMission:getIsServer() or g_currentMission.isMasterUser
                menuOption:setState(MoistureSettings.getStateIndex(id))
                menuOption:setDisabled(not isAdmin)
            end
        end
    end
end
