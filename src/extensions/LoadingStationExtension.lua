---
-- LoadingStationExtension
-- Tracks moisture when loading from storage/silos
---

MSLoadingStationExtension = {}

---
-- Extended to transfer moisture from storage to vehicle
-- @param superFunc: Original function
-- @param fillableObject: The object being filled (vehicle)
-- @param fillUnitIndex: Fill unit index on vehicle
-- @param fillTypeIndex: FillType being loaded
-- @param fillDelta: Amount to load
-- @param fillInfo: Fill info
-- @param toolType: Tool type
-- @return actually filled amount
---
function MSLoadingStationExtension:addFillLevelToFillableObject(superFunc, fillableObject, fillUnitIndex, fillTypeIndex, fillDelta, fillInfo, toolType)
    -- Only track on server
    if not self.isServer then
        return superFunc(self, fillableObject, fillUnitIndex, fillTypeIndex, fillDelta, fillInfo, toolType)
    end

    local moistureSystem = g_currentMission.MoistureSystem
    if not moistureSystem:shouldTrackFillType(fillTypeIndex) then
        return superFunc(self, fillableObject, fillUnitIndex, fillTypeIndex, fillDelta, fillInfo, toolType)
    end

    local targetUniqueId = fillableObject.uniqueId
    if targetUniqueId == nil then
        return superFunc(self, fillableObject, fillUnitIndex, fillTypeIndex, fillDelta, fillInfo, toolType)
    end

    -- Get target's current fill level and moisture before loading
    local targetCurrentLiters = 0
    if fillableObject.getFillUnitFillLevel ~= nil then
        targetCurrentLiters = fillableObject:getFillUnitFillLevel(fillUnitIndex)
    end

    -- Handle conveyor belt targets (special case for vehicles loading into other vehicles)
    if fillableObject.getConveyorBeltTargetObject ~= nil then
        local conveyorTarget, conveyorFillUnitIndex = fillableObject:getConveyorBeltTargetObject()
        if conveyorTarget ~= nil then
            targetCurrentLiters = conveyorTarget:getFillUnitFillLevel(conveyorFillUnitIndex)
        end
    end

    local actualFilledAmount = superFunc(self, fillableObject, fillUnitIndex, fillTypeIndex, fillDelta, fillInfo, toolType)

    if actualFilledAmount <= 0 then
        return actualFilledAmount
    end

    -- Get moisture from storage (owning placeable)
    local storageMoisture = nil

    -- Try to get moisture from the owning placeable (silo, warehouse, etc.)
    if self.owningPlaceable ~= nil and self.owningPlaceable.uniqueId ~= nil then
        storageMoisture = moistureSystem:getObjectMoisture(self.owningPlaceable.uniqueId, fillTypeIndex)
    end

    -- If no storage moisture, use default field moisture
    if storageMoisture == nil then
        storageMoisture = moistureSystem:getDefaultMoisture()
    end

    -- Transfer moisture using volume-weighted averaging
    moistureSystem:transferObjectMoisture(
        self.owningPlaceable and self.owningPlaceable.uniqueId or "loadingStation",
        targetUniqueId,
        actualFilledAmount,
        targetCurrentLiters,
        fillTypeIndex
    )

    return actualFilledAmount
end

LoadingStation.addFillLevelToFillableObject = Utils.overwrittenFunction(
    LoadingStation.addFillLevelToFillableObject,
    MSLoadingStationExtension.addFillLevelToFillableObject
)
