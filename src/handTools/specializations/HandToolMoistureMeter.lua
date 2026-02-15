----------------------------------------------------------------------------------------------------
-- HandToolMoistureMeter
----------------------------------------------------------------------------------------------------

HandToolMoistureMeter = {}

local specName = "spec_FS25_MoistureSystem.moistureMeter"

---Register XML paths
function HandToolMoistureMeter.registerXMLPaths(xmlSchema)
    xmlSchema:setXMLSpecializationType("HandToolMoistureMeter")
    SoundManager.registerSampleXMLPaths(xmlSchema, "handTool.moistureMeter.sounds", "start")
    SoundManager.registerSampleXMLPaths(xmlSchema, "handTool.moistureMeter.sounds", "cancel")
    SoundManager.registerSampleXMLPaths(xmlSchema, "handTool.moistureMeter.sounds", "complete")
    xmlSchema:setXMLSpecializationType()
end

---Register functions
function HandToolMoistureMeter.registerFunctions(handTool)
    SpecializationUtil.registerFunction(handTool, "performMeasurement", HandToolMoistureMeter.performMeasurement)
end

---Register event listeners
function HandToolMoistureMeter.registerEventListeners(handTool)
    SpecializationUtil.registerEventListener(handTool, "onPostLoad", HandToolMoistureMeter)
    SpecializationUtil.registerEventListener(handTool, "onDelete", HandToolMoistureMeter)
    SpecializationUtil.registerEventListener(handTool, "onUpdate", HandToolMoistureMeter)
    -- SpecializationUtil.registerEventListener(handTool, "onDraw", HandToolMoistureMeter)
    SpecializationUtil.registerEventListener(handTool, "onHeldStart", HandToolMoistureMeter)
    SpecializationUtil.registerEventListener(handTool, "onHeldEnd", HandToolMoistureMeter)
    SpecializationUtil.registerEventListener(handTool, "onRegisterActionEvents", HandToolMoistureMeter)
end

---Check if prerequisites are present
function HandToolMoistureMeter.prerequisitesPresent()
    return true
end

---Initialize on load
function HandToolMoistureMeter:onPostLoad(savegame)
    local spec = self[specName]

    if self.isClient then
        -- spec.defaultCrosshair = self:createCrosshairOverlay("gui.crosshairDefault")

        -- Load sounds
        spec.samples = {}
        spec.samples.start = g_soundManager:loadSampleFromXML(self.xmlFile, "handTool.moistureMeter.sounds", "start",
            self.baseDirectory, self.components, 1, AudioGroup.VEHICLE, self.i3dMappings, self)
        spec.samples.cancel = g_soundManager:loadSampleFromXML(self.xmlFile, "handTool.moistureMeter.sounds", "cancel",
            self.baseDirectory, self.components, 1, AudioGroup.VEHICLE, self.i3dMappings, self)
        spec.samples.complete = g_soundManager:loadSampleFromXML(self.xmlFile, "handTool.moistureMeter.sounds",
            "complete", self.baseDirectory, self.components, 1, AudioGroup.VEHICLE, self.i3dMappings, self)
    end

    spec.activateText = g_i18n:getText("moistureSystem_measureLocation")
    spec.isActive = false
    spec.isHolding = false
    spec.holdStartTime = 0
    spec.holdDuration = 4000 -- 4 seconds in milliseconds
    spec.lastSoundSecond = 0 -- Track which second we last played a sound for
end

---Cleanup
function HandToolMoistureMeter:onDelete()
    local spec = self[specName]

    -- if spec.defaultCrosshair ~= nil then
    --     spec.defaultCrosshair:delete()
    --     spec.defaultCrosshair = nil
    -- end

    if spec.samples ~= nil then
        g_soundManager:deleteSamples(spec.samples)
    end
end

---Called when player picks up the tool
function HandToolMoistureMeter:onHeldStart()
    if g_localPlayer == nil or self:getCarryingPlayer() ~= g_localPlayer then return end

    local spec = self[specName]
    spec.isActive = true
end

---Called when player drops/holsters the tool
function HandToolMoistureMeter:onHeldEnd()
    if g_localPlayer == nil then return end

    local spec = self[specName]
    spec.isActive = false
end

---Register action events (button bindings)
function HandToolMoistureMeter:onRegisterActionEvents()
    if self:getIsActiveForInput(true) then
        local _, eventId = self:addActionEvent(
            InputAction.ACTIVATE_HANDTOOL,
            self,
            HandToolMoistureMeter.onActionCallback,
            true, true, false, true, nil
        )

        local spec = self[specName]
        spec.activateActionEventId = eventId

        g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_VERY_HIGH)
        g_inputBinding:setActionEventText(eventId, spec.activateText)
        g_inputBinding:setActionEventActive(eventId, true)
    end
end

---Called when activate button is pressed or released
---@param actionName string The action name
---@param inputValue number > 0 when pressed, <= 0 when released
function HandToolMoistureMeter:onActionCallback(actionName, inputValue)
    local spec = self[specName]
    local isPressed = inputValue > 0

    if isPressed then
        -- Button pressed - start holding
        if not spec.isHolding then
            spec.isHolding = true
            spec.holdStartTime = g_currentMission.time
            spec.lastSoundSecond = 0 -- Reset sound tracking

            -- Play start sound
            if self.isClient and spec.samples ~= nil and spec.samples.start ~= nil then
                g_soundManager:playSample(spec.samples.start)
            end
        end
    else
        -- Button released
        if spec.isHolding then
            local elapsedTime = g_currentMission.time - spec.holdStartTime
            if elapsedTime < spec.holdDuration then
                -- Play cancel sound
                if self.isClient and spec.samples ~= nil and spec.samples.cancel ~= nil then
                    g_soundManager:playSample(spec.samples.cancel)
                end
            end
            spec.isHolding = false
        end
    end
end

---Update function - check hold duration
function HandToolMoistureMeter:onUpdate(dt)
    local spec = self[specName]

    if spec.isHolding then
        -- Check if hold duration reached
        local elapsedTime = g_currentMission.time - spec.holdStartTime

        -- Play start sound at 1, 2, and 3 second marks
        local currentSecond = math.floor(elapsedTime / 1000)
        if currentSecond > spec.lastSoundSecond and currentSecond < 4 then
            spec.lastSoundSecond = currentSecond
            if self.isClient and spec.samples ~= nil and spec.samples.start ~= nil then
                g_soundManager:playSample(spec.samples.start)
            end
        end

        if elapsedTime >= spec.holdDuration then
            -- Perform measurement
            spec.isHolding = false

            -- Play complete sound
            if self.isClient and spec.samples ~= nil and spec.samples.complete ~= nil then
                g_soundManager:playSample(spec.samples.complete)
            end

            self:performMeasurement()
        end
    end
end

---Perform the measurement
function HandToolMoistureMeter:performMeasurement()
    local player = self:getCarryingPlayer()
    if player == nil then return end

    -- Get player position
    local x, y, z = getWorldTranslation(player.rootNode)
    local moisture = g_currentMission.MoistureSystem:getMoistureAtPosition(x, z)

    local message = string.format(g_i18n:getText("moistureSystem_groundMoistureReading"), moisture * 100)
    g_currentMission:showBlinkingWarning(message, 3000)
end

---Draw UI overlay
-- function HandToolMoistureMeter:onDraw()
--     local spec = self[specName]

--     if spec.defaultCrosshair then
--         spec.defaultCrosshair:render()
--     end
-- end
