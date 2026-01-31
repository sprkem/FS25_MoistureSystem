---
-- MowerExtension
-- Tracks moisture when mowing grass
---

MSMowerExtension = {}

---
-- Extended to track moisture when grass is dropped to ground
-- @param superFunc: Original function
-- @param dropArea: The drop area
-- @param dt: Delta time
---
function MSMowerExtension:processDropArea(superFunc, dropArea, dt)
    -- Call original function
    local toDrop = dropArea.litersToDrop
    superFunc(self, dropArea, dt)
    local dropped = toDrop - dropArea.litersToDrop
    
    -- Only track on server and if grass was dropped
    if not self.isServer or dropped <= 0 then
        return
    end
    
    local spec = self.spec_mower
    if spec == nil or dropArea.fillType == nil then
        return
    end
    
    -- Get moisture system and tracker
    local moistureSystem = g_currentMission.MoistureSystem
    local tracker = g_currentMission.harvestPropertyTracker
    if moistureSystem == nil or tracker == nil then
        return
    end
    
    -- Get drop area coordinates
    local sx, _, sz = getWorldTranslation(dropArea.start)
    local wx, _, wz = getWorldTranslation(dropArea.width)
    local hx, _, hz = getWorldTranslation(dropArea.height)
    
    -- Calculate center of drop area for moisture sampling
    local centerX = (sx + wx + hx) / 3
    local centerZ = (sz + wz + hz) / 3
    
    -- Get moisture at this location (field moisture where grass was cut)
    local moisture = moistureSystem:getMoistureAtPosition(centerX, centerZ)
    if moisture == nil then
        moisture = moistureSystem.currentMoisturePercent
    end
    
    -- Track the dropped grass pile with moisture
    -- Note: litersToDrop is the amount that was attempted to drop
    -- The actual dropped amount was already deducted from litersToDrop by superFunc
    tracker:addPile(sx, sz, wx, wz, hx, hz, dropArea.fillType, dropped, {
        moisture = moisture
    })
end

Mower.processDropArea = Utils.overwrittenFunction(Mower.processDropArea, MSMowerExtension.processDropArea)
