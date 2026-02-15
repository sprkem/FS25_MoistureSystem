MoistureSystem = {}

MoistureSystem.dir = g_currentModDirectory
MoistureSystem.SaveKey = "MoistureSystem"

function MoistureSystem:loadMap()
    g_currentMission.MoistureSystem = self
    self.didLoadFromXML = false
    self.midHeight = 0
    self.currentMoisturePercent = 0
    self.timeSinceLastUpdate = 0
    self.updateInterval = 500
    self.missionStarted = false

    self.settings = {
        environment = MoistureClampEnvironments.NORMAL,
        moistureLossMultiplier = 3.0,
        moistureGainMultiplier = 3.0,
        teddingMoistureReduction = 0.02,
        baleRotEnabled = true,
        baleRotRate = 1.0,
        baleGracePeriod = 15,
        baleExposureDecayRate = 1.0
    }

    -- Initialize property tracker
    g_currentMission.groundPropertyTracker = GroundPropertyTracker.new()

    -- Initialize bale rotting system
    g_currentMission.baleRottingSystem = BaleRottingSystem.new()

    -- Initialize vehicle/object moisture tracking
    self.objectMoisture = {}

    -- Initialize LRU cache for getMoistureAtPosition
    self.moistureCache = {}
    self.moistureCacheOrder = {}
    self.moistureCacheMaxSize = 10

    -- Load from XML file (called directly during loadMap, not via hook)
    self:loadFromXMLFile()

    -- Inject menu after GUI is ready
    if g_gui then
        MoistureSettings.addSettingsToMenu()
    end

    self:loadGUI()

    if g_addCheatCommands and g_currentMission:getIsServer() then
        addConsoleCommand("msSetMoisture", "Set Moisture", "consoleCommandSetMoisture", self)
        addConsoleCommand("msSpawnMeter", "Spawn Moisture Meter", "consoleCommandSpawnMeter", self)
    end
end

-- Local values: height
function MoistureSystem:consoleCommandSetMoisture(newMoisture)
    if not g_currentMission:getIsServer() then return end
    local newMoistureNum = tonumber(newMoisture)
    if newMoisture == nil or newMoistureNum == nil then
        return "Usage: msSetMoisture value[1-100]"
    end
    newMoistureNum = math.max(1, math.min(100, newMoistureNum)) / 100
    g_client:getServerConnection():sendEvent(MoistureUpdateEvent.new(newMoistureNum))
    return string.format("New moisture is %.3f", newMoistureNum)
end

function MoistureSystem:consoleCommandSpawnMeter()
    if not g_currentMission:getIsServer() then return "Server only command" end
    
    local xmlFilename = MoistureSystem.dir .. "objects/moistureMeter/moistureMeter.xml"
    local typeName = g_currentModName .. ".moistureMeter"
    local handToolType = g_handToolTypeManager:getTypeByName(typeName)
    
    if handToolType == nil then
        return string.format("Hand tool type not found: %s", typeName)
    end
    
    local handTool = _G[handToolType.className].new(g_currentMission:getIsServer(), g_currentMission:getIsClient())
    handTool:setType(handToolType)
    
    -- Load the hand tool
    if handTool:load(xmlFilename) then
        g_currentMission.handToolSystem:addHandTool(handTool)
        print("[MoistureSystem] Moisture meter spawned successfully")
        return "Moisture meter spawned"
    else
        return "Failed to spawn moisture meter"
    end
end

function MoistureSystem:delete()
    if g_addCheatCommands then
        removeConsoleCommand("msSetMoisture")
        removeConsoleCommand("msSpawnMeter")
    end
end

function MoistureSystem:loadGUI()
    g_gui:loadProfiles(MoistureSystem.dir .. "src/gui/guiProfiles.xml")
    local gradesFrame = MoistureGuiGrades.new(g_i18n)
    g_gui:loadGui(MoistureSystem.dir .. "src/gui/MoistureGuiGrades.xml", "MoistureGuiGrades", gradesFrame, true)

    local calendarFrame = MoistureGuiCalendar.new(g_i18n)
    g_gui:loadGui(MoistureSystem.dir .. "src/gui/MoistureGuiCalendar.xml", "MoistureGuiCalendar", calendarFrame, true)

    self.moistureGui = MoistureGui:new(g_messageCenter, g_i18n, g_inputBinding)
    g_gui:loadGui(MoistureSystem.dir .. "src/gui/MoistureGui.xml", "MoistureGui", self.moistureGui)
end

function MoistureSystem:update(dt)
    if not g_currentMission:getIsServer() then return end

    self.timeSinceLastUpdate = self.timeSinceLastUpdate + dt

    -- Only update every updateInterval milliseconds
    if self.timeSinceLastUpdate >= self.updateInterval then
        self:updateMoistureLevel(self.timeSinceLastUpdate)
        self.timeSinceLastUpdate = 0
    end

    -- Update bale rotting system
    if g_currentMission.baleRottingSystem then
        g_currentMission.baleRottingSystem:update(dt)
    end
end

---
-- Update moisture level based on weather conditions
-- @param timescale: Time elapsed in milliseconds since last update
---
function MoistureSystem:updateMoistureLevel(delta)
    if not g_currentMission:getIsServer() then return end
    local scaledDelta = (delta * g_currentMission:getEffectiveTimeScale()) / 10000000
    local weather = g_currentMission.environment.weather

    -- Get current weather conditions
    local rainfall = weather:getRainFallScale()
    local snowfall = weather:getSnowFallScale()
    local hailfall = weather:getHailFallScale()
    local temperature = weather.temperatureUpdater.currentTemperature or 20
    local currentHour = g_currentMission.environment.currentHour

    -- Calculate moisture delta
    local moistureDelta = 0

    -- Gain moisture from rain/snow/hail
    if rainfall > 0 or snowfall > 0 or hailfall > 0 then
        moistureDelta = (rainfall + (snowfall * 0.55) + (hailfall * 0.5)) * 0.009945 * scaledDelta *
            self.settings.moistureGainMultiplier
        self:adjustMoisture(moistureDelta)
    else
        -- Lose moisture from temperature (warmer = more loss)
        -- Only lose during daytime (6am-8pm) or reduced loss at night
        local daylightStart = 6
        local daylightEnd = 20
        local sunFactor = (currentHour >= daylightStart and currentHour < daylightEnd) and 1 or 0.33

        local rateFactor = 0
        if temperature >= 45 then
            rateFactor = temperature * 0.001024
        elseif temperature >= 35 then
            rateFactor = temperature * 0.00075096
        elseif temperature >= 25 then
            rateFactor = temperature * 0.00032424
        elseif temperature >= 15 then
            rateFactor = temperature * 0.0001024
        else
            rateFactor = temperature * 0.00004264
        end

        moistureDelta = moistureDelta - (rateFactor * scaledDelta * sunFactor * self.settings.moistureLossMultiplier)

        -- Apply moisture change with clamping
        self:adjustMoisture(moistureDelta)
    end

    -- Update grass pile moisture
    if g_currentMission.groundPropertyTracker then
        g_currentMission.groundPropertyTracker:updateGrassMoisture(moistureDelta, delta)
        g_currentMission.groundPropertyTracker:updateHayMoisture(moistureDelta)
        g_currentMission.groundPropertyTracker:updateStrawMoisture(moistureDelta, delta)
    end
end

---
-- Adjust current moisture level while respecting min/max clamps
-- @param delta: Amount to change moisture (can be positive or negative)
---
function MoistureSystem:adjustMoisture(delta)
    if not g_currentMission:getIsServer() then return end
    -- Get current month and environment
    local month = MoistureSystem.periodToMonth(g_currentMission.environment.currentPeriod)
    local environment = self.settings.environment

    -- Get min/max for current month and environment
    local monthData = MoistureClamp.Environments[environment].Months[month]
    local minMoisture = monthData.Min / 100
    local maxMoisture = monthData.Max / 100

    -- Calculate 80% of range to leave headroom for terrain-based variation
    local rangeSize = maxMoisture - minMoisture
    local innerMin = minMoisture + (rangeSize * 0.1)
    local innerMax = maxMoisture - (rangeSize * 0.1)

    -- Apply delta and clamp to 80% of range
    local newMoisture = math.max(innerMin, math.min(innerMax, self.currentMoisturePercent + delta))

    -- Only send event if value changed
    if newMoisture ~= self.currentMoisturePercent then
        g_client:getServerConnection():sendEvent(MoistureUpdateEvent.new(newMoisture))
    end
end

function MoistureSystem:getMoistureAtPosition(x, z)
    -- Check cache first (round to 5m grid for better hit rate)
    local cacheKey = string.format("%d_%d", math.floor(x / 5) * 5, math.floor(z / 5) * 5)
    if self.moistureCache[cacheKey] ~= nil then
        return self.moistureCache[cacheKey]
    end

    local height = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)

    -- Get current month and environment for clamping
    local month = MoistureSystem.periodToMonth(g_currentMission.environment.currentPeriod)
    local environment = self.settings.environment
    local monthData = MoistureClamp.Environments[environment].Months[month]
    local minMoisture = monthData.Min / 100
    local maxMoisture = monthData.Max / 100

    local moistureLevel
    -- Higher elevation = lower moisture, lower elevation = higher moisture
    local heightRange = self.maxHeight - self.minHeight
    if heightRange > 0 then
        local heightDiff = height - self.midHeight

        local headroomAbove = maxMoisture - self.currentMoisturePercent
        local headroomBelow = self.currentMoisturePercent - minMoisture
        local maxAdjustmentUp = math.min(0.02, 0.8 * headroomAbove)
        local maxAdjustmentDown = math.min(0.02, 0.8 * headroomBelow)

        local heightFactor
        if heightDiff < 0 then
            -- Below midHeight: use distance to minHeight as range
            local rangeToMin = self.midHeight - self.minHeight
            heightFactor = rangeToMin > 0 and (heightDiff / rangeToMin) or 0
            moistureLevel = self.currentMoisturePercent - (heightFactor * maxAdjustmentUp)
        else
            -- Above midHeight: use distance to maxHeight as range
            local rangeToMax = self.maxHeight - self.midHeight
            heightFactor = rangeToMax > 0 and (heightDiff / rangeToMax) or 0
            moistureLevel = self.currentMoisturePercent - (heightFactor * maxAdjustmentDown)
        end

        moistureLevel = math.max(minMoisture, math.min(maxMoisture, moistureLevel))
    else
        moistureLevel = self.currentMoisturePercent
    end

    -- Store in cache with LRU eviction
    if #self.moistureCacheOrder >= self.moistureCacheMaxSize then
        local oldestKey = table.remove(self.moistureCacheOrder, 1)
        self.moistureCache[oldestKey] = nil
    end
    self.moistureCache[cacheKey] = moistureLevel
    table.insert(self.moistureCacheOrder, cacheKey)

    return moistureLevel
end

function MoistureSystem:firstLoad()
    -- Get current month and environment
    local month = MoistureSystem.periodToMonth(g_currentMission.environment.currentPeriod)
    local environment = self.settings.environment

    -- Get min/max for current month and environment
    local monthData = MoistureClamp.Environments[environment].Months[month]
    local minMoisture = monthData.Min
    local maxMoisture = monthData.Max

    -- Set current moisture to 85% of maximum, converted to 0-1 scale
    local startMoisture = maxMoisture * 0.85
    self.currentMoisturePercent = startMoisture / 100
end

function MoistureSystem:setHeights()
    local heights = {}
    for _, farmland in pairs(g_farmlandManager.farmlands) do
        if farmland.showOnFarmlandsScreen and farmland.field ~= nil then
            local field = farmland.field
            local x, z = field:getCenterOfFieldWorldPosition()
            local height = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
            table.insert(heights, height)
        end
    end

    if #heights > 0 then
        table.sort(heights)

        -- Use median for midHeight
        local midIndex = math.ceil(#heights / 2)
        self.midHeight = heights[midIndex]

        -- Use full range (min and max) so heightFactor stays within [-1, 1]
        self.minHeight = heights[1]
        self.maxHeight = heights[#heights]
    else
        self.minHeight = 0
        self.maxHeight = 0
        self.midHeight = 0
    end
end

function MoistureSystem.periodToMonth(period)
    period = period + 2
    if period > 12 then
        period = period - 12
    end
    return period
end

---
-- Get moisture level for an object/vehicle's specific fillType
-- @param uniqueId: The uniqueId of the object
-- @param fillType: FillType index
-- @return moisture level (0-1 scale) or nil if not set
---
function MoistureSystem:getObjectMoisture(uniqueId, fillType)
    if uniqueId == nil or fillType == nil then
        return nil
    end

    if not self:shouldTrackFillType(fillType) then
        return nil
    end

    local fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillType)
    if fillTypeName == nil then
        return nil
    end

    local objectData = self.objectMoisture[uniqueId]
    if objectData == nil then
        return nil
    end

    return objectData[fillTypeName]
end

---
-- Check if an object still has any of a specific fillType
-- @param uniqueId: The uniqueId of the object
-- @param fillType: FillType index to check
-- @return true if object has this fillType with fill level > 0
---
function MoistureSystem:hasFillType(uniqueId, fillType)
    if uniqueId == nil or fillType == nil then
        return false
    end

    if not self:shouldTrackFillType(fillType) then
        return false
    end

    -- Get the object from the mission
    local object = g_currentMission:getObjectByUniqueId(uniqueId)
    if object == nil then
        return false
    end

    if object.spec_silo then
        if object.spec_silo.storages then
            for _, storage in ipairs(object.spec_silo.storages) do
                local fillLevel = storage:getFillLevel(fillType)
                if fillLevel and fillLevel > 0 then
                    return true
                end
            end
        end
        return false
    end

    if object.spec_fillUnit == nil or object.spec_fillUnit.fillUnits == nil then
        return false
    end

    -- Check all fill units to see if any contain this fillType
    for _, fillUnit in pairs(object.spec_fillUnit.fillUnits) do
        if fillUnit.fillType == fillType and fillUnit.fillLevel > 0 then
            return true
        end
    end

    return false
end

---
-- Set moisture level for an object/vehicle's specific fillType
-- @param uniqueId: The uniqueId of the object
-- @param fillType: FillType index
-- @param moisture: The moisture level (0-1 scale) or nil to clear
---
function MoistureSystem:setObjectMoisture(uniqueId, fillType, moisture)
    if uniqueId == nil or fillType == nil then
        return
    end

    if not self:shouldTrackFillType(fillType) then
        return
    end

    local fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillType)
    if fillTypeName == nil then
        return
    end

    if self.objectMoisture[uniqueId] == nil then
        self.objectMoisture[uniqueId] = {}
    end

    self.objectMoisture[uniqueId][fillTypeName] = moisture
end

---
-- Transfer moisture from source to target with volume-weighted averaging
-- @param sourceId: uniqueId of source object
-- @param targetId: uniqueId of target object
-- @param sourceLiters: Amount being transferred from source
-- @param targetCurrentLiters: Current amount in target before transfer
-- @param fillType: FillType index being transferred
---
function MoistureSystem:transferObjectMoisture(sourceId, targetId, sourceLiters, targetCurrentLiters, fillType)
    if sourceId == nil or targetId == nil or sourceLiters <= 0 or fillType == nil then
        return
    end

    if not self:shouldTrackFillType(fillType) then
        return
    end

    local sourceMoisture = self:getObjectMoisture(sourceId, fillType)
    local targetMoisture = self:getObjectMoisture(targetId, fillType)

    -- If neither source nor target have moisture, use current field moisture
    if sourceMoisture == nil and targetMoisture == nil then
        sourceMoisture = self.currentMoisturePercent
    elseif sourceMoisture == nil then
        -- Do nothing, target moisture will remain the same
        return
    end

    if targetMoisture == nil or targetCurrentLiters <= 0 then
        self:setObjectMoisture(targetId, fillType, sourceMoisture)
    else
        -- Volume-weighted average
        local totalLiters = targetCurrentLiters + sourceLiters
        local weightedMoisture = (targetCurrentLiters * targetMoisture) + (sourceLiters * sourceMoisture)
        self:setObjectMoisture(targetId, fillType, weightedMoisture / totalLiters)
    end

    -- Clean up source moisture tracking if source no longer has this fillType
    if not self:hasFillType(sourceId, fillType) then
        self:setObjectMoisture(sourceId, fillType, nil)
    end
end

---
-- Check if fillType is grass or grass windrow
-- @param fillType: The filltype index
-- @return true if grass type
---
function MoistureSystem:isGrassOnGroundFillType(fillType)
    -- local grasses = {
    --     ["GRASS_WINDROW"] = true,
    --     ["GRASS"] = true,
    --     ["ALFALFA_WINDROW"] = true,
    --     ["ALFALFA"] = true,
    --     ["CLOVER_WINDROW"] = true,
    --     ["CLOVER"] = true
    -- }
    -- local fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillType)

    -- if fillTypeName ~= "GRASS_WINDROW" and fillTypeName ~= "ALFALFA_WINDROW" and fillTypeName ~= "CLOVER_WINDROW" then
    --     print("Checking if fillType is grass: " .. tostring(fillTypeName))
    -- end
    -- return grasses[fillTypeName] or false
    local converter = g_fillTypeManager:getConverterDataByName("TEDDER")
    for fromFillType, to in pairs(converter) do
        local targetFillType = to.targetFillTypeIndex
        if fromFillType == targetFillType then
            continue
        end

        if fillType == fromFillType then
            return true
        end
    end

    -- TODO REMOVE WHEN HAPPY THIS WORKS
    local debugCheck = {
        ["GRASS"] = true,
        ["ALFALFA"] = true,
        ["CLOVER"] = true
    }
    if debugCheck[g_fillTypeManager:getFillTypeNameByIndex(fillType)] then
        print("isGrassOnGroundFillType: WARNING: grass fillType is not accounted for: " ..
        tostring(g_fillTypeManager:getFillTypeNameByIndex(fillType)))
    end
    return false
end

---
-- Check if fillType is a hay/dry grass type (converted grass)
-- @param fillType: The filltype index
-- @return true if hay/dry type
---
function MoistureSystem:isHayFillType(fillType)
    -- local fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillType)
    -- if not fillTypeName then return false end

    -- local GRASS_CONVERSION_MAP = {
    --     ["GRASS_WINDROW"] = "DRYGRASS_WINDROW",
    --     ["ALFALFA_WINDROW"] = "DRYALFALFA_WINDROW",
    --     ["CLOVER_WINDROW"] = "DRYCLOVER_WINDROW"
    -- }

    -- -- Check if this fillType is one of the hay conversion targets
    -- for _, hayType in pairs(GRASS_CONVERSION_MAP) do
    --     if fillTypeName == hayType then
    --         return true
    --     end
    -- end
    -- return false
    local converter = g_fillTypeManager:getConverterDataByName("TEDDER")
    for fromFillType, to in pairs(converter) do
        local targetFillType = to.targetFillTypeIndex
        if fromFillType == targetFillType then
            continue
        end

        if fillType == targetFillType then
            return true
        end
    end
    return false
end

---
-- Check if fillType is straw
-- @param fillType: The filltype index
-- @return true if straw type
---
function MoistureSystem:isStrawFillType(fillType)
    return fillType == FillType.STRAW
end

---
-- Check if fillType should be tracked (defined in CropValueMap or special types)
-- @param fillType: The filltype index
-- @return true if should be tracked
---
function MoistureSystem:shouldTrackFillType(fillType)
    if self:isGrassOnGroundFillType(fillType) then
        return true
    end
    
    -- Track straw
    if self:isStrawFillType(fillType) then
        return true
    end
    
    return CropValueMap.Data[fillType] ~= nil
end

---
-- Get the default moisture for silo-loaded crops
-- Uses current field moisture as baseline
-- @return moisture level (0-1 scale)
---
function MoistureSystem:getDefaultMoisture()
    return self.currentMoisturePercent
end

-- function MoistureSystem:loadGrassTypes()
--     local converter = g_fillTypeManager:getConverterDataByName("TEDDER")
--     for fromFillType, to in pairs(converter) do
--         local targetFillType = to.targetFillTypeIndex
--         if fromFillType == targetFillType then
--             continue
--         end
--     end
-- end

function MoistureSystem:onStartMission()
    CropValueMap.initialize()
    local ms = g_currentMission.MoistureSystem
    ms:setHeights()
    -- ms:loadGrassTypes()
    ms.missionStarted = true

    if g_currentMission:getIsServer() then
        -- Initialize mod on new game
        if not ms.didLoadFromXML then
            ms:firstLoad()
        else
            local loadedGridSize = g_currentMission.groundPropertyTracker.loadedGridSize
            if loadedGridSize ~= GroundPropertyTracker.GRID_SIZE then
                print(string.format(
                    "GroundPropertyTracker: Grid size changed from %d to %d, converting saved data...",
                    loadedGridSize, GroundPropertyTracker.GRID_SIZE
                ))
                g_currentMission.groundPropertyTracker:convertGridCells(loadedGridSize, GroundPropertyTracker.GRID_SIZE)
            end
        end
    end
end

function MoistureSystem:loadFromXMLFile()
    if not g_currentMission:getIsServer() then return end

    local savegameFolderPath = g_currentMission.missionInfo.savegameDirectory
    if savegameFolderPath == nil then
        savegameFolderPath = ('%ssavegame%d'):format(getUserProfileAppPath(), g_currentMission.missionInfo.savegameIndex)
    end
    savegameFolderPath = savegameFolderPath .. "/"

    if fileExists(savegameFolderPath .. MoistureSystem.SaveKey .. ".xml") then
        local xmlFile = loadXMLFile(MoistureSystem.SaveKey, savegameFolderPath .. MoistureSystem.SaveKey .. ".xml")

        -- Load current moisture level
        local currentMoisture = getXMLFloat(xmlFile, MoistureSystem.SaveKey .. "#currentMoisturePercent")
        if currentMoisture then
            self.currentMoisturePercent = currentMoisture
        end

        -- Load settings
        local environment = getXMLInt(xmlFile, MoistureSystem.SaveKey .. ".settings#environment")
        if environment then
            self.settings.environment = environment
        end

        local lossMultiplier = getXMLFloat(xmlFile, MoistureSystem.SaveKey .. ".settings#moistureLossMultiplier")
        if lossMultiplier then
            self.settings.moistureLossMultiplier = lossMultiplier
        end

        local gainMultiplier = getXMLFloat(xmlFile, MoistureSystem.SaveKey .. ".settings#moistureGainMultiplier")
        if gainMultiplier then
            self.settings.moistureGainMultiplier = gainMultiplier
        end

        local teddingReduction = getXMLFloat(xmlFile, MoistureSystem.SaveKey .. ".settings#teddingMoistureReduction")
        if teddingReduction then
            self.settings.teddingMoistureReduction = teddingReduction
        end

        local baleRotEnabled = getXMLBool(xmlFile, MoistureSystem.SaveKey .. ".settings#baleRotEnabled")
        if baleRotEnabled ~= nil then
            self.settings.baleRotEnabled = baleRotEnabled
        end

        local baleRotRate = getXMLFloat(xmlFile, MoistureSystem.SaveKey .. ".settings#baleRotRate")
        if baleRotRate then
            self.settings.baleRotRate = baleRotRate
        end

        local baleGracePeriod = getXMLInt(xmlFile, MoistureSystem.SaveKey .. ".settings#baleGracePeriod")
        if baleGracePeriod then
            self.settings.baleGracePeriod = baleGracePeriod
        end

        local baleExposureDecayRate = getXMLFloat(xmlFile, MoistureSystem.SaveKey .. ".settings#baleExposureDecayRate")
        if baleExposureDecayRate then
            self.settings.baleExposureDecayRate = baleExposureDecayRate
        end

        if g_currentMission.groundPropertyTracker then
            g_currentMission.groundPropertyTracker:loadFromXMLFile(xmlFile, MoistureSystem.SaveKey)
        end

        if g_currentMission.baleRottingSystem then
            g_currentMission.baleRottingSystem:loadFromXMLFile(xmlFile, MoistureSystem.SaveKey)
        end

        -- Load object moisture data
        local i = 0
        while true do
            local objectKey = string.format("%s.objectMoisture.object(%d)", MoistureSystem.SaveKey, i)
            if not hasXMLProperty(xmlFile, objectKey) then
                break
            end

            local uniqueId = getXMLString(xmlFile, objectKey .. "#uniqueId")

            if uniqueId then
                -- Load all fillTypes for this object
                local j = 0
                while true do
                    local fillTypeKey = string.format("%s.fillType(%d)", objectKey, j)

                    if not hasXMLProperty(xmlFile, fillTypeKey) then
                        break
                    end

                    local fillTypeName = getXMLString(xmlFile, fillTypeKey .. "#name")
                    local moisture = getXMLFloat(xmlFile, fillTypeKey .. "#moisture")

                    if fillTypeName and moisture then
                        if self.objectMoisture[uniqueId] == nil then
                            self.objectMoisture[uniqueId] = {}
                        end
                        self.objectMoisture[uniqueId][fillTypeName] = moisture
                    end

                    j = j + 1
                end
            end

            i = i + 1
        end

        self.didLoadFromXML = true
        delete(xmlFile)
    end
end

function MoistureSystem:saveToXmlFile()
    if not g_currentMission:getIsServer() then return end

    local savegameFolderPath = g_currentMission.missionInfo.savegameDirectory .. "/"
    if savegameFolderPath == nil then
        savegameFolderPath = ('%ssavegame%d'):format(getUserProfileAppPath(),
            g_currentMission.missionInfo.savegameIndex .. "/")
    end

    local xmlFile = createXMLFile(MoistureSystem.SaveKey, savegameFolderPath .. MoistureSystem.SaveKey .. ".xml",
        MoistureSystem.SaveKey)

    local ms = g_currentMission.MoistureSystem

    -- Save current moisture level
    setXMLFloat(xmlFile, MoistureSystem.SaveKey .. "#currentMoisturePercent", ms.currentMoisturePercent)

    -- Save settings
    setXMLInt(xmlFile, MoistureSystem.SaveKey .. ".settings#environment", ms.settings.environment)
    setXMLFloat(xmlFile, MoistureSystem.SaveKey .. ".settings#moistureLossMultiplier", ms.settings
        .moistureLossMultiplier)
    setXMLFloat(xmlFile, MoistureSystem.SaveKey .. ".settings#moistureGainMultiplier", ms.settings
        .moistureGainMultiplier)
    setXMLFloat(xmlFile, MoistureSystem.SaveKey .. ".settings#teddingMoistureReduction", ms.settings
        .teddingMoistureReduction)
    setXMLBool(xmlFile, MoistureSystem.SaveKey .. ".settings#baleRotEnabled", ms.settings.baleRotEnabled)
    setXMLFloat(xmlFile, MoistureSystem.SaveKey .. ".settings#baleRotRate", ms.settings.baleRotRate)
    setXMLInt(xmlFile, MoistureSystem.SaveKey .. ".settings#baleGracePeriod", ms.settings.baleGracePeriod)
    setXMLFloat(xmlFile, MoistureSystem.SaveKey .. ".settings#baleExposureDecayRate", ms.settings.baleExposureDecayRate)

    if g_currentMission.groundPropertyTracker then
        g_currentMission.groundPropertyTracker:saveToXMLFile(xmlFile, MoistureSystem.SaveKey)
    end

    if g_currentMission.baleRottingSystem then
        g_currentMission.baleRottingSystem:saveToXMLFile(xmlFile, MoistureSystem.SaveKey)
    end

    -- Save object moisture data
    local i = 0
    for uniqueId, fillTypes in pairs(ms.objectMoisture) do
        local objectKey = string.format("%s.objectMoisture.object(%d)", MoistureSystem.SaveKey, i)
        setXMLString(xmlFile, objectKey .. "#uniqueId", uniqueId)

        -- Save all fillTypes for this object
        local j = 0
        for fillTypeName, moisture in pairs(fillTypes) do
            local fillTypeKey = string.format("%s.fillType(%d)", objectKey, j)

            setXMLString(xmlFile, fillTypeKey .. "#name", fillTypeName)
            setXMLFloat(xmlFile, fillTypeKey .. "#moisture", moisture)

            j = j + 1
        end

        i = i + 1
    end

    saveXMLFile(xmlFile)
    delete(xmlFile)
end

---
-- Action callback to open moisture GUI
---
function MoistureSystem.ShowMoistureGUI()
    if g_gui.currentGui == nil then
        g_currentMission.MoistureSystem:loadGUI() -- Useful when developing UI
        g_gui:showGui("MoistureGui")
    end
end

local function addPlayerActionEvents(self, superFunc, ...)
    superFunc(self, ...)
    local _, id = g_inputBinding:registerActionEvent(InputAction.MOISTURE_MENU, self,
        MoistureSystem.ShowMoistureGUI, false, true, false,
        true)
    g_inputBinding:setActionEventTextVisibility(id, false)
end

FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, MoistureSystem.saveToXmlFile)
FSBaseMission.onStartMission = Utils.appendedFunction(FSBaseMission.onStartMission, MoistureSystem.onStartMission)
PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.overwrittenFunction(
    PlayerInputComponent.registerGlobalPlayerActionEvents, addPlayerActionEvents)
addModEventListener(MoistureSystem)
