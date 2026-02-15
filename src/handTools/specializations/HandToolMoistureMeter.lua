----------------------------------------------------------------------------------------------------
-- HandToolMoistureMeter
----------------------------------------------------------------------------------------------------
-- Purpose:  Specialization for Moisture Meter hand tool
--           Prints player location and field moisture when activated
--
-- Copyright (c) 2025
----------------------------------------------------------------------------------------------------

HandToolMoistureMeter = {}

local specName = "spec_FS25_MoistureSystem.moistureMeter"

---Register functions
function HandToolMoistureMeter.registerFunctions(handTool)
    SpecializationUtil.registerFunction(handTool, "performMeasurement", HandToolMoistureMeter.performMeasurement)
end

---Register event listeners
function HandToolMoistureMeter.registerEventListeners(handTool)
    SpecializationUtil.registerEventListener(handTool, "onPostLoad", HandToolMoistureMeter)
    SpecializationUtil.registerEventListener(handTool, "onDelete", HandToolMoistureMeter)
    SpecializationUtil.registerEventListener(handTool, "onUpdate", HandToolMoistureMeter)
    SpecializationUtil.registerEventListener(handTool, "onDraw", HandToolMoistureMeter)
    SpecializationUtil.registerEventListener(handTool, "onHeldStart", HandToolMoistureMeter)
    SpecializationUtil.registerEventListener(handTool, "onHeldEnd", HandToolMoistureMeter)
    SpecializationUtil.registerEventListener(handTool, "onRegisterActionEvents", HandToolMoistureMeter)
end

---Check if prerequisites are present
function HandToolMoistureMeter.prerequisitesPresent()
    print("[MoistureSystem] Loaded handTool: HandToolMoistureMeter")
    return true
end

---Initialize on load
function HandToolMoistureMeter:onPostLoad(savegame)
    local spec = self[specName]

    if self.isClient then
        spec.defaultCrosshair = self:createCrosshairOverlay("gui.crosshairDefault")
    end

    spec.activateText = g_i18n:getText("moistureSystem_measureLocation")
    spec.isActive = false
    spec.isHolding = false
    spec.holdStartTime = 0
    spec.holdDuration = 4000  -- 4 seconds in milliseconds

    print("[MoistureSystem] Moisture meter initialized")
end

---Cleanup
function HandToolMoistureMeter:onDelete()
    local spec = self[specName]

    if spec.defaultCrosshair ~= nil then
        spec.defaultCrosshair:delete()
        spec.defaultCrosshair = nil
    end
end

---Called when player picks up the tool
function HandToolMoistureMeter:onHeldStart()
    if g_localPlayer == nil or self:getCarryingPlayer() ~= g_localPlayer then return end

    local spec = self[specName]
    spec.isActive = true

    print("[MoistureSystem] Moisture meter picked up")
end

---Called when player drops/holsters the tool
function HandToolMoistureMeter:onHeldEnd()
    if g_localPlayer == nil then return end

    local spec = self[specName]
    spec.isActive = false

    print("[MoistureSystem] Moisture meter put away")
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
            print("[MoistureSystem] Measurement started - hold button for 4 seconds...")
        end
    else
        -- Button released
        if spec.isHolding then
            local elapsedTime = g_currentMission.time - spec.holdStartTime
            if elapsedTime < spec.holdDuration then
                print("[MoistureSystem] Measurement cancelled - button released")
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
        if elapsedTime >= spec.holdDuration then
            -- Perform measurement
            spec.isHolding = false
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

    -- Print location
    print(string.format("[MoistureSystem] ========== MEASUREMENT =========="))
    print(string.format("[MoistureSystem] Player Location: X=%.2f, Y=%.2f, Z=%.2f", x, y, z))

    -- Get terrain height
    local terrainHeight = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z)
    print(string.format("[MoistureSystem] Terrain Height: %.2f", terrainHeight))

    -- Get moisture at position (if MoistureSystem available)
    if g_currentMission.MoistureSystem then
        local moisture = g_currentMission.MoistureSystem:getMoistureAtPosition(x, z)
        print(string.format("[MoistureSystem] Field Moisture: %.2f%%", moisture * 100))

        -- Get system moisture info
        local system = g_currentMission.MoistureSystem
        print(string.format("[MoistureSystem] Current System Moisture: %.2f%%", system.currentMoisturePercent * 100))
    else
        print("[MoistureSystem] MoistureSystem not available")
    end

    print(string.format("[MoistureSystem] ==================================="))
end

---Draw UI overlay
function HandToolMoistureMeter:onDraw()
    local spec = self[specName]

    if spec.defaultCrosshair then
        spec.defaultCrosshair:render()
    end
end
