---
-- PlaceableInfoTriggerExtension
-- Extends PlaceableInfoTrigger to display moisture information for placeables
---

MSPlaceableInfoTriggerExtension = {}

---
-- Show moisture data for placeables being looked at
-- Appended to PlaceableInfoTrigger.updateInfo
---
function MSPlaceableInfoTriggerExtension:updateInfo(info)
    -- Check if this placeable has moisture data
    if self.uniqueId == nil then
        return
    end
    
    local moistureSystem = g_currentMission.MoistureSystem
    if moistureSystem == nil then
        return
    end
    
    local objectData = moistureSystem.objectMoisture[self.uniqueId]
    if objectData == nil then
        return
    end
    
    -- Add moisture data for each fillType stored in this placeable
    for fillTypeName, moisture in pairs(objectData) do
        local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
        if fillTypeIndex then
            local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
            if fillType then
                table.insert(info, {
                    title = fillType.title .. " " .. g_i18n:getText("moistureSystem_moisture"),
                    text = string.format("%.1f%%", moisture * 100),
                    accentuate = false
                })
            end
        end
    end
end

PlaceableInfoTrigger.updateInfo = Utils.appendedFunction(
    PlaceableInfoTrigger.updateInfo,
    MSPlaceableInfoTriggerExtension.updateInfo
)
