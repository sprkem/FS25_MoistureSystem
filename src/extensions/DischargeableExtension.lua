---
-- DischargeableExtension
-- Tracks moisture when crops are discharged to ground
---

MSDischargeableExtension = {}

---
-- Extended to track moisture of discharged crops
-- @param superFunc: Original function
-- @param dischargeNode: The discharge node being used
-- @param emptyLiters: Amount to discharge
-- @return dischargedLiters, minDropReached, hasMinDropFillLevel
---
function MSDischargeableExtension:dischargeToGround(superFunc, dischargeNode, emptyLiters)
    -- Call original function
    local dischargedLiters, minDropReached, hasMinDropFillLevel = superFunc(self, dischargeNode, emptyLiters)
    
    -- Only track on server and if something was actually discharged
    if not self.isServer or dischargedLiters <= 0 then
        return dischargedLiters, minDropReached, hasMinDropFillLevel
    end
    
    -- Get the moisture system
    local tracker = g_currentMission.harvestPropertyTracker
    if tracker == nil then
        return dischargedLiters, minDropReached, hasMinDropFillLevel
    end
    
    -- Get filltype
    local fillType = self:getDischargeFillType(dischargeNode)
    if fillType == nil then
        return dischargedLiters, minDropReached, hasMinDropFillLevel
    end
    
    -- Get moisture from vehicle's fillType if available
    local moistureSystem = g_currentMission.MoistureSystem
    local moisture = nil
    
    if moistureSystem and self.uniqueId then
        moisture = moistureSystem:getObjectMoisture(self.uniqueId, fillType)
    end
    
    -- If no moisture data, use field moisture as fallback
    if moisture == nil then
        if moistureSystem == nil then
            return dischargedLiters, minDropReached, hasMinDropFillLevel
        end
        
        -- Get discharge position
        local info = dischargeNode.info
        local sx, _, sz = localToWorld(info.node, -info.width, 0, info.zOffset)
        local ex, _, ez = localToWorld(info.node, info.width, 0, info.zOffset)
        local centerX = (sx + ex) / 2
        local centerZ = (sz + ez) / 2
        
        moisture = moistureSystem:getMoistureAtPosition(centerX, centerZ)
        
        if moisture == nil then
            moisture = moistureSystem.currentMoisturePercent
        end
    end
    
    -- Get discharge area coordinates
    local info = dischargeNode.info
    local sx, sy, sz = localToWorld(info.node, -info.width, 0, info.zOffset)
    local ex, ey, ez = localToWorld(info.node, info.width, 0, info.zOffset)
    
    -- Adjust Y to terrain if needed
    if info.limitToGround then
        sy = getTerrainHeightAtWorldPos(g_terrainNode, sx, 0, sz) + 0.1
        ey = getTerrainHeightAtWorldPos(g_terrainNode, ex, 0, ez) + 0.1
    else
        sy = sy + info.yOffset
        ey = ey + info.yOffset
    end
    
    -- Calculate center point for tracking
    local centerX = (sx + ex) / 2
    local centerZ = (sz + ez) / 2
    
    -- Calculate bounding box corners for tracking
    local length = info.length or 0
    local width = math.sqrt((ex - sx)^2 + (ez - sz)^2)
    
    -- Create corner coordinates for pile tracking
    -- Using simplified rectangle aligned with discharge direction
    local halfWidth = width / 2
    local halfLength = length / 2
    
    local corner1X = centerX - halfWidth
    local corner1Z = centerZ - halfLength
    local corner2X = centerX + halfWidth
    local corner2Z = centerZ - halfLength
    local corner3X = centerX - halfWidth
    local corner3Z = centerZ + halfLength
    
    -- Track the pile with moisture
    tracker:addPile(
        corner1X, corner1Z,
        corner2X, corner2Z,
        corner3X, corner3Z,
        fillType,
        dischargedLiters,
        { moisture = moisture }
    )
    
    return dischargedLiters, minDropReached, hasMinDropFillLevel
end

-- Hook into Dischargeable specialization
Dischargeable.dischargeToGround = Utils.overwrittenFunction(
    Dischargeable.dischargeToGround,
    MSDischargeableExtension.dischargeToGround
)

---
-- Extended to track moisture when discharging to vehicles/objects
-- @param superFunc: Original function
-- @param dischargeNode: The discharge node being used
-- @param targetObject: The vehicle/object being filled
-- @param targetFillUnitIndex: Fill unit index on target
-- @param emptyLiters: Amount to discharge
-- @param extraAttributes: Additional attributes
-- @return dischargedLiters, minDropReached, hasMinDropFillLevel
---
function MSDischargeableExtension:dischargeToObject(superFunc, dischargeNode, targetObject, targetFillUnitIndex, emptyLiters, extraAttributes)
    -- Get target fill level BEFORE discharge
    local targetCurrentLiters = 0
    if targetObject ~= nil and targetObject.getFillUnitFillLevel ~= nil then
        targetCurrentLiters = targetObject:getFillUnitFillLevel(targetFillUnitIndex)
    end
    
    -- Call original function
    local dischargedLiters, minDropReached, hasMinDropFillLevel = superFunc(self, dischargeNode, targetObject, targetFillUnitIndex, emptyLiters, extraAttributes)
    
    -- Only track on server and if something was actually discharged
    if not self.isServer or dischargedLiters <= 0 then
        return dischargedLiters, minDropReached, hasMinDropFillLevel
    end
    
    -- Get the moisture system
    local moistureSystem = g_currentMission.MoistureSystem
    if moistureSystem == nil or targetObject == nil or targetObject.uniqueId == nil then
        return dischargedLiters, minDropReached, hasMinDropFillLevel
    end
    
    -- Get filltype
    local fillType = self:getDischargeFillType(dischargeNode)
    if fillType == nil then
        return dischargedLiters, minDropReached, hasMinDropFillLevel
    end
    
    -- Get source moisture (from this vehicle)
    local sourceMoisture = moistureSystem:getObjectMoisture(self.uniqueId, fillType)
    
    -- If no moisture data, use field moisture at discharge position
    if sourceMoisture == nil then
        local info = dischargeNode.info
        local sx, _, sz = localToWorld(info.node, -info.width, 0, info.zOffset)
        local ex, _, ez = localToWorld(info.node, info.width, 0, info.zOffset)
        local centerX = (sx + ex) / 2
        local centerZ = (sz + ez) / 2
        
        sourceMoisture = moistureSystem:getMoistureAtPosition(centerX, centerZ)
    end
    
    -- Transfer moisture to target using volume-weighted averaging
    moistureSystem:transferMoisture(
        self.uniqueId,
        targetObject.uniqueId,
        dischargedLiters,
        targetCurrentLiters,
        fillType
    )
    
    return dischargedLiters, minDropReached, hasMinDropFillLevel
end

Dischargeable.dischargeToObject = Utils.overwrittenFunction(
    Dischargeable.dischargeToObject,
    MSDischargeableExtension.dischargeToObject
)
