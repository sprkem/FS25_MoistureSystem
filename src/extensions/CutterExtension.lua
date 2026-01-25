---
-- CutterExtension
-- Tracks moisture content of harvested crops
---

MSCutterExtension = {}

---
-- Extended to track moisture of harvested crops
-- @param superFunc: Original function
-- @param dt: Delta time
-- @param hasProcessed: Whether work areas were processed
---
function MSCutterExtension:onEndWorkAreaProcessing(superFunc, dt, hasProcessed)
    -- Call original function first
    local result = superFunc(self, dt, hasProcessed)
    
    -- Only track on server
    if not self.isServer then
        return result
    end
    
    local spec = self.spec_cutter
    if spec == nil then
        return result
    end
    
    -- Check if we actually harvested something
    local lastArea = spec.workAreaParameters.lastArea or 0
    local lastLiters = spec.workAreaParameters.lastLiters or 0
    
    if lastArea <= 0 and lastLiters <= 0 then
        return result
    end
    
    -- Get the combine vehicle
    local combineVehicle = spec.workAreaParameters.combineVehicle
    if combineVehicle == nil then
        return result
    end
    
    -- Calculate total liters harvested
    local fruitType = spec.workAreaParameters.lastFruitType
    if fruitType == nil then
        return result
    end
    
    local liters = g_fruitTypeManager:getFruitTypeAreaLiters(
        fruitType,
        spec.workAreaParameters.lastMultiplierArea,
        false
    ) + lastLiters
    
    if liters <= 0 then
        return result
    end
    
    -- Determine moisture at harvest location
    local moisture = MSCutterExtension.getMoistureAtWorkArea(self, spec)
    
    if moisture == nil then
        return result
    end
    
    -- Get fillType for the harvested crop
    local fillType = g_fruitTypeManager:getFruitTypeByIndex(fruitType).fillTypeIndex
    if fillType == nil then
        return result
    end
    
    -- Update combine's rolling moisture average
    MSCutterExtension.updateCombineMoisture(combineVehicle, liters, moisture, fillType)
    
    return result
end

---
-- Get moisture level at the work area location
-- @param cutter: The cutter vehicle
-- @param spec: The cutter spec
-- @return moisture: Moisture level (0-1 scale) or nil
---
function MSCutterExtension.getMoistureAtWorkArea(cutter, spec)
    local moistureSystem = g_currentMission.MoistureSystem
    if moistureSystem == nil then
        return nil
    end
    
    -- Check if picking up windrows
    if spec.useWindrow then
        -- For windrow pickup, check if we have tracked piles
        local tracker = g_currentMission.harvestPropertyTracker
        if tracker == nil then
            return nil
        end
        
        -- Get first work area to determine location
        local workArea = cutter:getWorkAreaByIndex(1)
        if workArea == nil then
            return nil
        end
        
        -- Calculate center of work area
        local sx, _, sz = getWorldTranslation(workArea.start)
        local wx, _, wz = getWorldTranslation(workArea.width)
        local hx, _, hz = getWorldTranslation(workArea.height)
        
        local centerX = (sx + wx + hx) / 3
        local centerZ = (sz + wz + hz) / 3
        
        -- Try to get moisture from tracked pile
        local fillType = spec.currentInputFillType
        if fillType == nil then
            return nil
        end
        
        local properties = tracker:getPilePropertiesAtPosition(centerX, centerZ, fillType)
        if properties and properties.moisture then
            return properties.moisture
        end
        
        -- Fall back to field moisture if no pile tracked
        return moistureSystem:getMoistureAtPosition(centerX, centerZ)
    else
        -- For field harvest, get moisture from field location
        -- Get first work area to determine location
        local workArea = cutter:getWorkAreaByIndex(1)
        if workArea == nil then
            return nil
        end
        
        -- Calculate center of work area
        local sx, _, sz = getWorldTranslation(workArea.start)
        local wx, _, wz = getWorldTranslation(workArea.width)
        local hx, _, hz = getWorldTranslation(workArea.height)
        
        local centerX = (sx + wx + hx) / 3
        local centerZ = (sz + wz + hz) / 3
        
        return moistureSystem:getMoistureAtPosition(centerX, centerZ)
    end
end

---
-- Update combine's moisture based on harvested crop
-- Uses volume-weighted averaging when combining with existing moisture
-- @param combineVehicle: The combine vehicle
-- @param newLiters: Amount of crop picked up
-- @param newMoisture: Moisture level of picked up crop (0-1 scale)
-- @param fillType: FillType index being harvested
---
function MSCutterExtension.updateCombineMoisture(combineVehicle, newLiters, newMoisture, fillType)
    local moistureSystem = g_currentMission.MoistureSystem
    if moistureSystem == nil then
        return
    end
    
    local uniqueId = combineVehicle.uniqueId
    if uniqueId == nil then
        return
    end
    
    -- Get current fill level (before adding new crop)
    local spec = combineVehicle.spec_combine
    if spec == nil then
        return
    end
    
    local currentLiters = combineVehicle:getFillUnitFillLevel(spec.fillUnitIndex)
    local currentMoisture = moistureSystem:getObjectMoisture(uniqueId, fillType)
    
    if currentMoisture == nil or currentLiters <= 0 then
        -- First harvest or empty tank - use source moisture
        moistureSystem:setObjectMoisture(uniqueId, fillType, newMoisture)
    else
        -- Volume-weighted average: (currentLiters * currentMoisture + newLiters * newMoisture) / totalLiters
        local totalLiters = currentLiters + newLiters
        local averageMoisture = (currentLiters * currentMoisture + newLiters * newMoisture) / totalLiters
        moistureSystem:setObjectMoisture(uniqueId, fillType, averageMoisture)
    end
end

---
-- Get current average moisture in combine for specific fillType
-- @param combineVehicle: The combine vehicle
-- @param fillType: FillType index
-- @return average moisture (0-1 scale) or nil
---
function MSCutterExtension.getCombineMoisture(combineVehicle, fillType)
    local moistureSystem = g_currentMission.MoistureSystem
    if moistureSystem == nil then
        return nil
    end
    
    local uniqueId = combineVehicle.uniqueId
    if uniqueId == nil then
        return nil
    end
    
    return moistureSystem:getObjectMoisture(uniqueId, fillType)
end

---
-- Reset combine moisture tracking (called when tank is emptied)
-- @param combineVehicle: The combine vehicle
-- @param fillType: FillType index to reset (or nil to clear all)
---
function MSCutterExtension.resetCombineMoisture(combineVehicle, fillType)
    local moistureSystem = g_currentMission.MoistureSystem
    if moistureSystem == nil then
        return
    end
    
    local uniqueId = combineVehicle.uniqueId
    if uniqueId == nil then
        return
    end
    
    if fillType == nil then
        -- Clear all fillTypes for this vehicle
        moistureSystem.objectMoisture[uniqueId] = nil
    else
        -- Clear specific fillType
        moistureSystem:setObjectMoisture(uniqueId, fillType, nil)
    end
end

-- Hook into Cutter specialization
Cutter.onEndWorkAreaProcessing = Utils.overwrittenFunction(
    Cutter.onEndWorkAreaProcessing,
    MSCutterExtension.onEndWorkAreaProcessing
)
