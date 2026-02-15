---
-- BaleExtension
-- Hooks into bale fermentation to reduce volume based on moisture content
---

MSBaleExtension = {}

-- Moisture-based volume reduction tiers (0-1 scale)
MSBaleExtension.VOLUME_REDUCTION_TIERS = {
    { maxMoisture = 0.15, reduction = 0.00 }, -- 0-15%: No reduction (optimal)
    { maxMoisture = 0.18, reduction = 0.02 }, -- 15-18%: 2% reduction
    { maxMoisture = 0.22, reduction = 0.05 }, -- 18-22%: 5% reduction
    { maxMoisture = 0.26, reduction = 0.10 }, -- 22-26%: 10% reduction
    { maxMoisture = 0.30, reduction = 0.15 }, -- 26-30%: 15% reduction
    { maxMoisture = 1.00, reduction = 0.20 }, -- 30%+: 20% reduction
}

---
-- Get the volume reduction percentage for a given moisture level
-- @param moisture: Moisture level (0-1 scale)
-- @return reduction percentage (0-1 scale)
---
function MSBaleExtension.getVolumeReduction(moisture)
    for _, tier in ipairs(MSBaleExtension.VOLUME_REDUCTION_TIERS) do
        if moisture <= tier.maxMoisture then
            return tier.reduction
        end
    end

    -- Default to maximum reduction if somehow exceeded
    return 0.20
end

---
-- Extended to adjust bale volume based on moisture after fermentation
-- @param superFunc: Original function
---
function MSBaleExtension:onFermentationEnd(superFunc)
    local originalFillType = self.fillType
    local originalFillLevel = self.fillLevel

    superFunc(self)

    if not self.isServer then
        return
    end

    local moistureSystem = g_currentMission.MoistureSystem

    -- Get the moisture that was stored when bale was created
    -- Note: Check both original and new fillType in case moisture was stored under either
    local baleMoisture = moistureSystem:getObjectMoisture(self.uniqueId, originalFillType)
    if baleMoisture == nil then
        baleMoisture = moistureSystem:getObjectMoisture(self.uniqueId, self.fillType)
    end

    if baleMoisture == nil then
        return
    end

    local reductionPercent = MSBaleExtension.getVolumeReduction(baleMoisture)

    if reductionPercent > 0 then
        local newFillLevel = originalFillLevel * (1.0 - reductionPercent)
        self:setFillLevel(newFillLevel)
    end

    if originalFillType ~= self.fillType then
        moistureSystem:setObjectMoisture(self.uniqueId, originalFillType, nil)
    end
end

---
-- Extended to clean up moisture tracking when bale is deleted
-- @param superFunc: Original function
---
function MSBaleExtension:delete(superFunc)
    if self.isServer then
        local moistureSystem = g_currentMission.MoistureSystem
        if moistureSystem and self.uniqueId then
            moistureSystem:setObjectMoisture(self.uniqueId, self.fillType, nil)
        end
    end

    superFunc(self)
end

---
-- Extended to stop tracking bale exposure when wrapped (if not rotting)
-- Once wrapped, bale won't get wetter, so remove from rotting system if not already rotting
-- @param superFunc: Original function
-- @param wrappingState: Wrapping progress (0-1, >= 1 means fully wrapped)
-- @param updateFermentation: Whether to update fermentation state
---
function MSBaleExtension:setWrappingState(superFunc, wrappingState, updateFermentation)
    superFunc(self, wrappingState, updateFermentation)

    if not self.isServer then
        return
    end

    -- When bale becomes wrapped (wrappingState >= 1), remove from rotting tracking if not rotting
    if wrappingState >= 1 then
        local baleRottingSystem = g_currentMission.baleRottingSystem
        if baleRottingSystem and self.uniqueId then
            baleRottingSystem:removeBaleIfNotRotting(self.uniqueId)
        end
    end
end

---
-- Check if bale is currently rotting (needed for PlaceableObjectStorage to keep bale alive)
-- @return Boolean - true if bale is in a rotting state
---
function MSBaleExtension:getIsRotting()
    if not g_currentMission or not g_currentMission.baleRottingSystem then
        return false
    end

    local baleData = g_currentMission.baleRottingSystem.baleRainExposureTimes[self.uniqueId]
    if not baleData then
        return false
    end

    local BaleRottingSystem = g_currentMission.baleRottingSystem

    -- Consider bale as "rotting" if it's in any rotting state
    local isRotting = baleData.status == BaleRottingSystem.BALE_STATUS.ROTTING_SLOWLY or
        baleData.status == BaleRottingSystem.BALE_STATUS.ROTTING or
        baleData.status == BaleRottingSystem.BALE_STATUS.ROTTING_QUICKLY or
        -- Also consider "getting wet" state to ensure tracking continues
        baleData.status == BaleRottingSystem.BALE_STATUS.GETTING_WET

    return isRotting
end

Bale.onFermentationEnd = Utils.overwrittenFunction(
    Bale.onFermentationEnd,
    MSBaleExtension.onFermentationEnd
)

Bale.delete = Utils.overwrittenFunction(
    Bale.delete,
    MSBaleExtension.delete
)

---
-- Override getBaleAttributes to include uniqueId for storage save/load
-- @param superFunc: Original function
-- @return table of bale attributes including uniqueId
---
function MSBaleExtension:getBaleAttributes(superFunc)
    local attributes = superFunc(self)

    -- Add uniqueId to attributes so we can restore rotting state after load
    attributes.uniqueId = self.uniqueId

    return attributes
end

---
-- Override applyBaleAttributes to restore uniqueId from storage
-- @param superFunc: Original function
-- @param attributes: Table of bale attributes
---
function MSBaleExtension:applyBaleAttributes(superFunc, attributes)
    superFunc(self, attributes)

    -- Restore uniqueId if it was saved
    if attributes.uniqueId then
        self.uniqueId = attributes.uniqueId
    end
end

Bale.setWrappingState = Utils.overwrittenFunction(
    Bale.setWrappingState,
    MSBaleExtension.setWrappingState
)

Bale.getBaleAttributes = Utils.overwrittenFunction(
    Bale.getBaleAttributes,
    MSBaleExtension.getBaleAttributes
)

Bale.applyBaleAttributes = Utils.overwrittenFunction(
    Bale.applyBaleAttributes,
    MSBaleExtension.applyBaleAttributes
)

-- Add getIsRotting as a method
Bale.getIsRotting = MSBaleExtension.getIsRotting
