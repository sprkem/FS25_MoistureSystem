---
-- ForageWagonExtension
-- Tracks moisture when picking up fillType from ground
-- and cleans up pile data after pickup
---

MSForageWagonExtension = {}

---
-- Extended to track moisture from ground piles and clean up pile data
-- @param superFunc: Original function
-- @param dt: Delta time
-- @param hasProcessed: Whether work areas were processed
---
function MSForageWagonExtension:onEndWorkAreaProcessing(superFunc, dt, hasProcessed)
    -- Call original function first
    local result = superFunc(self, dt)
    
    -- Only track on server
    if not self.isServer then
        return result
    end
    
    local spec = self.spec_forageWagon
    if spec == nil then
        return result
    end
    
    -- Check if we actually picked up something
    local pickupLiters = spec.workAreaParameters.lastPickupLiters or 0
    if pickupLiters <= 0 then
        return result
    end
    
    -- Get the fillType that was picked up
    local fillType = spec.workAreaParameters.forcedFillType
    if fillType == nil or fillType == FillType.UNKNOWN then
        return result
    end
    
    -- Get moisture system and tracker
    local moistureSystem = g_currentMission.MoistureSystem
    local tracker = g_currentMission.harvestPropertyTracker
    if moistureSystem == nil or tracker == nil then
        return result
    end
    
    -- Get work area to determine pickup location
    local workArea = self:getWorkAreaByIndex(spec.workAreaIndex)
    if workArea == nil then
        return result
    end
    
    -- Calculate center of work area
    local sx, _, sz = getWorldTranslation(workArea.start)
    local wx, _, wz = getWorldTranslation(workArea.width)
    local hx, _, hz = getWorldTranslation(workArea.height)
    
    local centerX = (sx + wx + hx) / 3
    local centerZ = (sz + wz + hz) / 3
    
    -- Try to get moisture from tracked pile
    local properties = tracker:getPilePropertiesAtPosition(centerX, centerZ, fillType)
    local moisture = nil
    
    if properties and properties.moisture then
        moisture = properties.moisture
    else
        -- No pile tracked, use field moisture as fallback
        moisture = moistureSystem:getMoistureAtPosition(centerX, centerZ)
    end
    
    if moisture == nil then
        return result
    end
    
    -- Get current fill level before adding (need to subtract what was just added)
    local currentLiters = self:getFillUnitFillLevel(spec.fillUnitIndex) - pickupLiters
    
    -- Get vehicle uniqueId
    local uniqueId = self.uniqueId
    if uniqueId == nil then
        return result
    end
    
    -- Get existing moisture for this fillType
    local currentMoisture = moistureSystem:getObjectMoisture(uniqueId, fillType)
    
    if currentMoisture == nil or currentLiters <= 0 then
        -- First pickup or empty tank - use pile moisture
        moistureSystem:setObjectMoisture(uniqueId, fillType, moisture)
    else
        -- Volume-weighted average
        local totalLiters = currentLiters + pickupLiters
        local averageMoisture = (currentLiters * currentMoisture + pickupLiters * moisture) / totalLiters
        moistureSystem:setObjectMoisture(uniqueId, fillType, averageMoisture)
    end
    
    -- Remove pile from tracker (picked up from ground)
    -- The tracker will handle partial removals automatically via volume reduction
    tracker:removePileAtPosition(centerX, centerZ, fillType, pickupLiters)
    
    return result
end

-- Hook into ForageWagon specialization
ForageWagon.onEndWorkAreaProcessing = Utils.overwrittenFunction(
    ForageWagon.onEndWorkAreaProcessing,
    MSForageWagonExtension.onEndWorkAreaProcessing
)
