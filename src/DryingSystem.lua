DryingSystem = {}
local DryingSystem_mt = Class(DryingSystem)

DryingSystem.DEFAULT_DRYING_RATE = 0.01
DryingSystem.SILO_COST_RATIO = 0.7
DryingSystem.ACTIVATION_DISTANCE = 7

local PLAYER_CONTEXT = "PLAYER"

function DryingSystem.new()
    local self = setmetatable({}, DryingSystem_mt)
    self.activeDryers = {}
    self.activatables = {}
    return self
end

function DryingSystem:registerActivatables()
    for _, placeable in pairs(g_currentMission.placeableSystem.placeables) do
        if placeable.spec_silo and placeable.spec_silo.storages then
            self:addActivatable(placeable)
        end
    end
end

function DryingSystem:addActivatable(placeable)
    if self.activatables[placeable.uniqueId] then return end
    local activatable = DryingActivatable.new(self, placeable)
    self.activatables[placeable.uniqueId] = activatable
    g_currentMission.activatableObjectsSystem:addActivatable(activatable)
end

function DryingSystem:removeActivatable(placeableId)
    local activatable = self.activatables[placeableId]
    if activatable == nil then return end
    g_currentMission.activatableObjectsSystem:removeActivatable(activatable)
    self.activatables[placeableId] = nil
end

function DryingSystem:toggleDrying(placeable)
    if placeable == nil then return end

    local placeableId = placeable.uniqueId
    if self.activeDryers[placeableId] then
        self.activeDryers[placeableId] = nil
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
            g_i18n:getText("ms_drying_stopped"))
    else
        self.activeDryers[placeableId] = true
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
            g_i18n:getText("ms_drying_started"))
    end
end

function DryingSystem:isDrying(placeableId)
    return self.activeDryers[placeableId] ~= nil
end

function DryingSystem:onHourChanged()
    if not g_currentMission:getIsServer() then return end

    local ms = g_currentMission.MoistureSystem
    local dryingRate = ms.settings.dryingSpeed or DryingSystem.DEFAULT_DRYING_RATE
    local sellChargeRate = ms.settings.sellDryingChargeRate or 1.0

    local completedDryers = {}

    for placeableId, _ in pairs(self.activeDryers) do
        local placeable = self:getPlaceableByUniqueId(placeableId)
        if placeable == nil or placeable.spec_silo == nil then
            table.insert(completedDryers, placeableId)
        else
            local farmId = placeable:getOwnerFarmId()

            local totalLiters = 0
            for _, storage in ipairs(placeable.spec_silo.storages) do
                for _, fillLevel in pairs(storage.fillLevels) do
                    if fillLevel > 0 then
                        totalLiters = totalLiters + fillLevel
                    end
                end
            end

            if not self:siloNeedsDrying(placeable, ms) then
                table.insert(completedDryers, placeableId)
                g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
                    g_i18n:getText("ms_drying_complete"))
            else
                local volumeFactor = math.max(1, totalLiters / 10000)
                local effectiveDryingRate = dryingRate / volumeFactor

                for _, storage in ipairs(placeable.spec_silo.storages) do
                    for fillTypeIndex, fillLevel in pairs(storage.fillLevels) do
                        if fillLevel > 0 then
                            local _, idealMax = CropValueMap.getIdealRange(fillTypeIndex)
                            if idealMax then
                                local info = ms:getObjectInfo(placeable.uniqueId, fillTypeIndex)
                                if info and info.moisture > idealMax then
                                    info.moisture = math.max(idealMax, info.moisture - effectiveDryingRate)
                                end
                            end
                        end
                    end
                end

                local hourlyCost = DryingSystem.SILO_COST_RATIO * sellChargeRate * effectiveDryingRate * totalLiters
                g_currentMission:addMoneyChange(-hourlyCost, farmId, MoneyType.DRYING_CHARGE, true)
                g_farmManager:getFarmById(farmId):changeBalance(-hourlyCost, MoneyType.DRYING_CHARGE)

                if not self:siloNeedsDrying(placeable, ms) then
                    table.insert(completedDryers, placeableId)
                    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
                        g_i18n:getText("ms_drying_complete"))
                end
            end
        end
    end

    for _, placeableId in ipairs(completedDryers) do
        self.activeDryers[placeableId] = nil
    end
end

function DryingSystem:siloNeedsDrying(placeable, ms)
    for _, storage in ipairs(placeable.spec_silo.storages) do
        for fillTypeIndex, fillLevel in pairs(storage.fillLevels) do
            if fillLevel > 0 then
                local _, idealMax = CropValueMap.getIdealRange(fillTypeIndex)
                if idealMax then
                    local info = ms:getObjectInfo(placeable.uniqueId, fillTypeIndex)
                    if info and info.moisture > idealMax then
                        return true
                    end
                end
            end
        end
    end
    return false
end

function DryingSystem:getPlaceableByUniqueId(uniqueId)
    for _, placeable in pairs(g_currentMission.placeableSystem.placeables) do
        if placeable.uniqueId == uniqueId then
            return placeable
        end
    end
    return nil
end

function DryingSystem:saveToXMLFile(xmlFile, key)
    local i = 0
    for placeableId, _ in pairs(self.activeDryers) do
        local dryerKey = string.format("%s.activeDryers.dryer(%d)", key, i)
        setXMLString(xmlFile, dryerKey .. "#placeableId", placeableId)
        i = i + 1
    end
end

function DryingSystem:loadFromXMLFile(xmlFile, key)
    local i = 0
    while true do
        local dryerKey = string.format("%s.activeDryers.dryer(%d)", key, i)
        if not hasXMLProperty(xmlFile, dryerKey) then
            break
        end
        local placeableId = getXMLString(xmlFile, dryerKey .. "#placeableId")
        if placeableId then
            self.activeDryers[placeableId] = true
        end
        i = i + 1
    end
end

-- Activatable class for silo drying interaction
DryingActivatable = {}
local DryingActivatable_mt = Class(DryingActivatable)

function DryingActivatable.new(dryingSystem, placeable)
    local self = setmetatable({}, DryingActivatable_mt)
    self.dryingSystem = dryingSystem
    self.placeable = placeable
    self.activateText = g_i18n:getText("ms_action_startDrying")
    self.actionEventId = nil
    return self
end

function DryingActivatable:getIsActivatable()
    if self.placeable == nil or self.placeable.rootNode == nil then return false end
    if g_localPlayer == nil or g_localPlayer.rootNode == nil then return false end
    if g_localPlayer:getCurrentVehicle() ~= nil then return false end

    local px, _, pz = getWorldTranslation(g_localPlayer.rootNode)
    local tx, _, tz = getWorldTranslation(self.placeable.rootNode)
    if MathUtil.vector2Length(px - tx, pz - tz) > DryingSystem.ACTIVATION_DISTANCE then
        return false
    end

    local ms = g_currentMission.MoistureSystem
    local objectData = ms.objectInfo[self.placeable.uniqueId]
    if not objectData then return false end

    local hasMoisture = false
    for _, info in pairs(objectData) do
        if info.moisture then
            hasMoisture = true
            break
        end
    end
    if not hasMoisture then return false end

    if self.dryingSystem:isDrying(self.placeable.uniqueId) then
        self.activateText = g_i18n:getText("ms_action_stopDrying")
    else
        self.activateText = g_i18n:getText("ms_action_startDrying")
    end

    return true
end

function DryingActivatable:getDistance(x, _, z)
    if self.placeable == nil or self.placeable.rootNode == nil then return math.huge end
    local tx, _, tz = getWorldTranslation(self.placeable.rootNode)
    return MathUtil.vector2Length(x - tx, z - tz)
end

function DryingActivatable:registerCustomInput(inputContext)
    if inputContext ~= PLAYER_CONTEXT then
        return
    end

    local _, actionEventId = g_inputBinding:registerActionEvent(
        InputAction.MOISTURE_START_DRYING,
        self,
        self.onKeybindPressed,
        false,
        true,
        false,
        true
    )

    if actionEventId ~= nil and actionEventId ~= "" then
        self.actionEventId = actionEventId
        g_inputBinding:setActionEventText(actionEventId, self.activateText)
        g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_HIGH)
        g_inputBinding:setActionEventTextVisibility(actionEventId, true)
    end
end

function DryingActivatable:removeCustomInput()
    g_inputBinding:removeActionEventsByTarget(self)
    self.actionEventId = nil
end

function DryingActivatable:onKeybindPressed()
    if self.placeable == nil then return end

    if g_currentMission:getIsServer() then
        self.dryingSystem:toggleDrying(self.placeable)
    else
        g_client:getServerConnection():sendEvent(DryingToggleEvent.new(self.placeable.uniqueId))
    end

    if self.actionEventId then
        if self.dryingSystem:isDrying(self.placeable.uniqueId) then
            g_inputBinding:setActionEventText(self.actionEventId, g_i18n:getText("ms_action_stopDrying"))
        else
            g_inputBinding:setActionEventText(self.actionEventId, g_i18n:getText("ms_action_startDrying"))
        end
    end
end

function DryingActivatable:run()
    self:onKeybindPressed()
end
