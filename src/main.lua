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

    -- Initialize settings
    self.settings = {
        environment = MoistureClampEnvironments.NORMAL, -- Default to NORMAL
        moistureLossMultiplier = 3.0,
        moistureGainMultiplier = 3.0
    }

    -- Initialize property tracker
    g_currentMission.harvestPropertyTracker = HarvestPropertyTracker.new()

    -- Initialize vehicle/object moisture tracking
    -- Structure: { [uniqueId] = { [fillTypeName] = moisture } }
    -- fillTypeName is the string name to support save/load
    self.objectMoisture = {}

    -- Load from XML file (called directly during loadMap, not via hook)
    self:loadFromXMLFile()

    -- Inject menu after GUI is ready
    if g_gui then
        MoistureSettings.injectMenu()
    end
end

function MoistureSystem:update(dt)
    if not g_currentMission:getIsServer() then return end

    self.timeSinceLastUpdate = self.timeSinceLastUpdate + dt

    -- Only update every updateInterval milliseconds
    if self.timeSinceLastUpdate >= self.updateInterval then
        self:updateMoistureLevel(self.timeSinceLastUpdate)
        self.timeSinceLastUpdate = 0
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
    local temperature = weather.temperatureUpdater.currentTemperature or 20
    local currentHour = g_currentMission.environment.currentHour

    -- Calculate moisture delta
    local moistureDelta = 0

    -- Gain moisture from rain/snow
    if rainfall > 0 or snowfall > 0 then
        moistureDelta = (rainfall + snowfall * 0.75) * 0.009 * scaledDelta *
        self.settings.moistureGainMultiplier
        self:adjustMoisture(moistureDelta)
        return
    end

    -- Lose moisture from temperature (warmer = more loss)
    -- Only lose during daytime (6am-8pm) or reduced loss at night
    local daylightStart = 6
    local daylightEnd = 20
    local sunFactor = (currentHour >= daylightStart and currentHour < daylightEnd) and 1 or 0.33

    local rateFactor = 0
    if temperature >= 45 then
        rateFactor = temperature * 0.00128
    elseif temperature >= 35 then
        rateFactor = temperature * 0.0009387
    elseif temperature >= 25 then
        rateFactor = temperature * 0.0004053
    elseif temperature >= 15 then
        rateFactor = temperature * 0.000128
    else
        rateFactor = temperature * 0.0000533
    end

    moistureDelta = moistureDelta - (rateFactor * scaledDelta * sunFactor * self.settings.moistureLossMultiplier)

    -- Apply moisture change with clamping
    self:adjustMoisture(moistureDelta)
    
    -- Update grass pile moisture
    if g_currentMission.harvestPropertyTracker then
        g_currentMission.harvestPropertyTracker:updateGrassMoisture(moistureDelta)
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
    local minMoisture = monthData.Min / 100 -- Convert to 0-1 scale
    local maxMoisture = monthData.Max / 100 -- Convert to 0-1 scale

    -- Apply delta and clamp to min/max range
    local newMoisture = math.max(minMoisture, math.min(maxMoisture, self.currentMoisturePercent + delta))

    -- Only send event if value changed
    if newMoisture ~= self.currentMoisturePercent then
        g_client:getServerConnection():sendEvent(MoistureUpdateEvent.new(newMoisture))
    end
end

function MoistureSystem:getMoistureAtPosition(x, z)
    local height = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)

    -- Get current month and environment for clamping
    local month = MoistureSystem.periodToMonth(g_currentMission.environment.currentPeriod)
    local environment = self.settings.environment
    local monthData = MoistureClamp.Environments[environment].Months[month]
    local minMoisture = monthData.Min / 100
    local maxMoisture = monthData.Max / 100

    -- At midHeight, return currentMoisturePercent
    -- Higher elevation = lower moisture, lower elevation = higher moisture
    local heightRange = self.maxHeight - self.minHeight
    if heightRange > 0 then
        -- Calculate proportional difference from midHeight (-1 to +1 range)
        local heightDiff = height - self.midHeight
        local heightFactor = heightDiff / (heightRange / 2)

        -- Adjust moisture: higher elevation reduces moisture, lower increases it
        local moistureLevel = self.currentMoisturePercent - (heightFactor * 0.05)
        return math.max(minMoisture, math.min(maxMoisture, moistureLevel))
    else
        return self.currentMoisturePercent
    end
end

function MoistureSystem:firstLoad()
    -- Get current month and environment
    local month = MoistureSystem.periodToMonth(g_currentMission.environment.currentPeriod)
    local environment = self.settings.environment

    -- Get min/max for current month and environment
    local monthData = MoistureClamp.Environments[environment].Months[month]
    local minMoisture = monthData.Min
    local maxMoisture = monthData.Max

    -- Set current moisture to 25% above minimum, converted to 0-1 scale
    local moistureRange = maxMoisture - minMoisture
    local startMoisture = minMoisture + (moistureRange * 0.25)
    self.currentMoisturePercent = startMoisture / 100
end

function MoistureSystem:findMidHeight()
    local minHeight = math.huge
    local maxHeight = -math.huge
    local count = 0
    for _, farmland in pairs(g_farmlandManager.farmlands) do
        if farmland.showOnFarmlandsScreen and farmland.field ~= nil then
            local field = farmland.field
            local x, z = field:getCenterOfFieldWorldPosition()
            local height = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
            minHeight = math.min(minHeight, height)
            maxHeight = math.max(maxHeight, height)
            count = count + 1
        end
    end
    if count > 0 then
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.midHeight = (minHeight + maxHeight) / 2
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
-- Set moisture level for an object/vehicle's specific fillType
-- @param uniqueId: The uniqueId of the object
-- @param fillType: FillType index
-- @param moisture: The moisture level (0-1 scale) or nil to clear
---
function MoistureSystem:setObjectMoisture(uniqueId, fillType, moisture)
    if uniqueId == nil or fillType == nil then
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
function MoistureSystem:transferMoisture(sourceId, targetId, sourceLiters, targetCurrentLiters, fillType)
    if sourceId == nil or targetId == nil or sourceLiters <= 0 or fillType == nil then
        return
    end

    local sourceMoisture = self:getObjectMoisture(sourceId, fillType)
    local targetMoisture = self:getObjectMoisture(targetId, fillType)

    -- If neither source nor target have moisture, use current field moisture
    if sourceMoisture == nil and targetMoisture == nil then
        sourceMoisture = self.currentMoisturePercent
    elseif sourceMoisture == nil then
        -- Source has no moisture but target does - shouldn't happen in normal flow
        -- Use target moisture as fallback
        return
    end

    if targetMoisture == nil or targetCurrentLiters <= 0 then
        -- Target is empty or has no moisture set, use source moisture
        self:setObjectMoisture(targetId, fillType, sourceMoisture)
    else
        -- Volume-weighted average
        -- (targetLiters * targetMoisture + sourceLiters * sourceMoisture) / (targetLiters + sourceLiters)
        local totalLiters = targetCurrentLiters + sourceLiters
        local weightedMoisture = (targetCurrentLiters * targetMoisture) + (sourceLiters * sourceMoisture)
        self:setObjectMoisture(targetId, fillType, weightedMoisture / totalLiters)
    end
end

---
-- Get the default moisture for silo-loaded crops
-- Uses current field moisture as baseline
-- @return moisture level (0-1 scale)
---
function MoistureSystem:getDefaultMoisture()
    return self.currentMoisturePercent
end

function MoistureSystem:onStartMission()
    CropValueMap.initialize()
    local ms = g_currentMission.MoistureSystem
    ms:findMidHeight()

    if g_currentMission:getIsServer() then
        -- Initialize mod on new game
        if not ms.didLoadFromXML then
            ms:firstLoad()
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

        if g_currentMission.harvestPropertyTracker then
            g_currentMission.harvestPropertyTracker:loadFromXMLFile(xmlFile, MoistureSystem.SaveKey)
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

    -- Save settings
    setXMLInt(xmlFile, MoistureSystem.SaveKey .. ".settings#environment", ms.settings.environment)
    setXMLFloat(xmlFile, MoistureSystem.SaveKey .. ".settings#moistureLossMultiplier", ms.settings
    .moistureLossMultiplier)
    setXMLFloat(xmlFile, MoistureSystem.SaveKey .. ".settings#moistureGainMultiplier", ms.settings
    .moistureGainMultiplier)

    if g_currentMission.harvestPropertyTracker then
        g_currentMission.harvestPropertyTracker:saveToXMLFile(xmlFile, MoistureSystem.SaveKey)
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

FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, MoistureSystem.saveToXmlFile)
FSBaseMission.onStartMission = Utils.appendedFunction(FSBaseMission.onStartMission, MoistureSystem.onStartMission)
addModEventListener(MoistureSystem)
