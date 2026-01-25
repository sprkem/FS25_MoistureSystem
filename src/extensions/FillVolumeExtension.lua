---
-- FillVolumeExtension
-- Tracks moisture when loading with buckets/shovels from ground piles
---

MSFillVolumeExtension = {}

---
-- Extended to track moisture when filling from ground piles
-- @param superFunc: Original function
-- @param fillUnitIndex: Fill unit being filled
-- @param fillLevelDelta: Amount filled
-- @param fillType: FillType being loaded
-- @param toolType: Tool type
-- @param fillPositionData: Position data
---
function MSFillVolumeExtension:onFillUnitFillLevelChanged(superFunc, fillUnitIndex, fillLevelDelta, fillType, toolType, fillPositionData, appliedDelta)
    -- Call original function first
    if superFunc ~= nil then
        superFunc(self, fillUnitIndex, fillLevelDelta, fillType, toolType, fillPositionData, appliedDelta)
    end
    
    -- Only track on server and if we're adding material
    if not self.isServer or fillLevelDelta <= 0 then
        return
    end
    
    -- Check if this was a pickup from ground (fillPositionData contains position)
    if fillPositionData == nil or fillPositionData.x == nil or fillPositionData.z == nil then
        return
    end
    
    local moistureSystem = g_currentMission.MoistureSystem
    local tracker = g_currentMission.harvestPropertyTracker
    if moistureSystem == nil or tracker == nil then
        return
    end
    
    -- Get vehicle uniqueId
    local uniqueId = self.uniqueId
    if uniqueId == nil then
        return
    end
    
    -- Try to get moisture from tracked pile at pickup location
    local properties = tracker:getPilePropertiesAtPosition(fillPositionData.x, fillPositionData.z, fillType)
    local moisture = nil
    
    if properties and properties.moisture then
        moisture = properties.moisture
    else
        -- No pile tracked, use field moisture as fallback
        moisture = moistureSystem:getMoistureAtPosition(fillPositionData.x, fillPositionData.z)
    end
    
    if moisture == nil then
        moisture = moistureSystem.currentMoisturePercent
    end
    
    -- Get current fill level (before this addition)
    local currentLiters = self:getFillUnitFillLevel(fillUnitIndex) - fillLevelDelta
    
    -- Get existing moisture for this fillType
    local currentMoisture = moistureSystem:getObjectMoisture(uniqueId, fillType)
    
    if currentMoisture == nil or currentLiters <= 0 then
        -- First pickup or empty - use source moisture
        moistureSystem:setObjectMoisture(uniqueId, fillType, moisture)
    else
        -- Volume-weighted average
        local totalLiters = currentLiters + fillLevelDelta
        local averageMoisture = (currentLiters * currentMoisture + fillLevelDelta * moisture) / totalLiters
        moistureSystem:setObjectMoisture(uniqueId, fillType, averageMoisture)
    end
    
    -- Remove volume from pile tracking
    tracker:removePileAtPosition(fillPositionData.x, fillPositionData.z, fillType, fillLevelDelta)
end

-- Hook into FillVolume specialization (used by buckets, shovels, augers, etc.)
if FillVolume ~= nil then
    FillVolume.onFillUnitFillLevelChanged = Utils.overwrittenFunction(
        FillVolume.onFillUnitFillLevelChanged,
        MSFillVolumeExtension.onFillUnitFillLevelChanged
    )
end
