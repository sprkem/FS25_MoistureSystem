---
-- BalerExtension
-- Cleans up pile tracking data when baler picks up from ground
-- Does NOT track moisture on bales themselves
---

MSBalerExtension = {}

---
-- Extended to clean up pile data after baler picks up from ground
-- @param superFunc: Original function
-- @param workArea: The work area
---
function MSBalerExtension:processBalerArea(superFunc, workArea)
    -- Call original function first
    local result = superFunc(self, workArea)
    
    -- Only process on server
    if not self.isServer then
        return result
    end
    
    local tracker = g_currentMission.harvestPropertyTracker
    if tracker == nil then
        return result
    end
    
    local spec = self.spec_baler
    if spec == nil then
        return result
    end
    
    -- Get the fillType being picked up
    local fillType = self:getFillUnitLastValidFillType(spec.fillUnitIndex)
    if fillType == nil or fillType == FillType.UNKNOWN then
        return result
    end
    
    -- Calculate center of work area
    local sx, _, sz = getWorldTranslation(workArea.start)
    local wx, _, wz = getWorldTranslation(workArea.width)
    local hx, _, hz = getWorldTranslation(workArea.height)
    
    local centerX = (sx + wx + hx) / 3
    local centerZ = (sz + wz + hz) / 3
    
    -- Check if this fillType still exists in the grid cell
    local gridX, gridZ = tracker:getGridPosition(centerX, centerZ)
    local key = tracker:getGridKey(gridX, gridZ, fillType)
    local pile = tracker.gridPiles[key]
    
    if pile then
        -- Check if fillType actually still exists at this location
        local checkRadius = HarvestPropertyTracker.GRID_SIZE / 2
        
        -- Use density map to check if fillType is still present
        local fillLevelAtLocation = DensityMapHeightUtil.getFillLevelAtArea(
            fillType,
            gridX - checkRadius, gridZ - checkRadius,
            gridX + checkRadius, gridZ - checkRadius,
            gridX - checkRadius, gridZ + checkRadius
        )
        
        -- If no fillType left, remove pile tracking data
        if fillLevelAtLocation == nil or fillLevelAtLocation <= 0 then
            tracker.gridPiles[key] = nil
        end
    end
    
    return result
end

-- Hook into Baler specialization
Baler.processBalerArea = Utils.overwrittenFunction(
    Baler.processBalerArea,
    MSBalerExtension.processBalerArea
)
