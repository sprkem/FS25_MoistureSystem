---
-- CombineExtension
-- Manages moisture tracking lifecycle in combines
---

MSCombineExtension = {}

---
-- Extended to reset moisture tracking when tank is emptied
-- @param superFunc: Original function
-- @param fillUnitIndex: The fill unit that changed
-- @param fillLevelDelta: Change in fill level
-- @param fillTypeIndex: Type of fill
-- @param toolType: Tool type
-- @param fillPositionData: Position data
-- @param appliedDelta: Actually applied delta
---
function MSCombineExtension:onFillUnitFillLevelChanged(superFunc, fillUnitIndex, fillLevelDelta, fillTypeIndex, toolType, fillPositionData, appliedDelta)
    -- Call original function
    if superFunc ~= nil then
        superFunc(self, fillUnitIndex, fillLevelDelta, fillTypeIndex, toolType, fillPositionData, appliedDelta)
    end
    
    -- Only handle on server
    if not self.isServer then
        return
    end
    
    local spec = self.spec_combine
    if spec == nil then
        return
    end
    
    -- Check if this is the main fill unit or buffer
    if fillUnitIndex ~= spec.fillUnitIndex and fillUnitIndex ~= spec.bufferFillUnitIndex then
        return
    end
    
    -- If fill level is now zero or near zero, clear moisture tracking for this fillType
    local fillLevel = self:getFillUnitFillLevel(fillUnitIndex)
    if fillLevel <= 0.001 then
        local moistureSystem = g_currentMission.MoistureSystem
        if moistureSystem and self.uniqueId and fillTypeIndex then
            -- Clear moisture for this specific fillType
            moistureSystem:setObjectMoisture(self.uniqueId, fillTypeIndex, nil)
        end
    end
end

-- Hook into Combine specialization
Combine.onFillUnitFillLevelChanged = Utils.overwrittenFunction(
    Combine.onFillUnitFillLevelChanged,
    MSCombineExtension.onFillUnitFillLevelChanged
)
