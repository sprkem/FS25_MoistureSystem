MSWindrowerExtension = {}

---
-- Hook processWindrowerArea to track pickups and mark cells for cleanup
---
function MSWindrowerExtension:processWindrowerArea(superFunc, workArea, dt)
    local droppedLiters, areaWidth = superFunc(self, workArea, dt)

    if not self.isServer or not g_currentMission.groundPropertyTracker then
        return droppedLiters, areaWidth
    end

    local tracker = g_currentMission.groundPropertyTracker
    local spec = self.spec_windrower

    -- Track pickups for moisture accumulation
    if workArea.lastPickupLiters > 0 and workArea.lastValidPickupFillType ~= FillType.UNKNOWN then
        local sx, sy, sz = getWorldTranslation(workArea.start)
        local wx, wy, wz = getWorldTranslation(workArea.width)
        local hx, hy, hz = getWorldTranslation(workArea.height)

        -- Get moisture from existing pile or field
        local centerX = (sx + wx + hx) / 3
        local centerZ = (sz + wz + hz) / 3

        local pickupMoisture
        local existingProps = tracker:getPilePropertiesAtPosition(centerX, centerZ, workArea.lastValidPickupFillType)
        if existingProps and existingProps.moisture then
            pickupMoisture = existingProps.moisture
        else
            pickupMoisture = g_currentMission.MoistureSystem:getMoistureAtPosition(centerX, centerZ)
        end

        -- Store moisture for this workArea (accumulates across pickups)
        if not workArea.accumulatedMoisture then
            workArea.accumulatedMoisture = pickupMoisture
            workArea.accumulatedVolume = 0
            workArea.lastPickupX = centerX
            workArea.lastPickupZ = centerZ
        end

        -- Volume-weighted accumulation
        local totalVolume = workArea.accumulatedVolume + workArea.lastPickupLiters
        if totalVolume > 0 then
            workArea.accumulatedMoisture = (workArea.accumulatedMoisture * workArea.accumulatedVolume +
                pickupMoisture * workArea.lastPickupLiters) / totalVolume
            workArea.accumulatedVolume = totalVolume
            workArea.lastPickupX = centerX
            workArea.lastPickupZ = centerZ
        end

        -- Mark picked cells for deferred cleanup
        tracker:markWindrowerPickup(sx, sz, wx, wz, hx, hz, workArea.lastValidPickupFillType)
    end

    return droppedLiters, areaWidth
end

---
-- Hook processDropArea to track drops with deferred pile creation
---
function MSWindrowerExtension:processDropArea(superFunc, dropArea, litersToDrop, fillType)
    local dropped, lineOffset = superFunc(self, dropArea, litersToDrop, fillType)

    if not self.isServer or dropped <= 0 or not g_currentMission.groundPropertyTracker then
        return dropped, lineOffset
    end

    local tracker = g_currentMission.groundPropertyTracker
    local spec = self.spec_windrower

    -- Find the source workArea to get accumulated moisture
    local workArea = nil
    local workAreaSpec = self.spec_workArea
    if workAreaSpec and workAreaSpec.workAreas then
        for _, wa in ipairs(workAreaSpec.workAreas) do
            -- Check if this workArea has a dropWindrowWorkAreaIndex (indicates it's a windrower pickup area)
            if wa.dropWindrowWorkAreaIndex and workAreaSpec.workAreas[wa.dropWindrowWorkAreaIndex] == dropArea then
                workArea = wa
                break
            end
        end
    end

    -- Get moisture from accumulated workArea data or fallback to field moisture
    local moisture
    if workArea and workArea.accumulatedMoisture and workArea.accumulatedVolume and workArea.accumulatedVolume > 0 then
        moisture = workArea.accumulatedMoisture

        workArea.accumulatedVolume = math.max(0, workArea.accumulatedVolume - dropped)

        if workArea.accumulatedVolume <= 0.001 then
            workArea.accumulatedMoisture = nil
            workArea.accumulatedVolume = 0
        end
    else
        local sx, sy, sz = getWorldTranslation(dropArea.start)
        local wx, wy, wz = getWorldTranslation(dropArea.width)
        local hx, hy, hz = getWorldTranslation(dropArea.height)
        local centerX = (sx + wx + hx) / 3
        local centerZ = (sz + wz + hz) / 3

        if workArea and workArea.lastPickupX and workArea.lastPickupZ then
            local pickupPileProps = tracker:getPilePropertiesAtPosition(workArea.lastPickupX, workArea.lastPickupZ,
                fillType)
            if pickupPileProps and pickupPileProps.moisture then
                moisture = pickupPileProps.moisture
            end
        end

        if not moisture then
            local nearbyPileProps = tracker:getPilePropertiesAtPosition(centerX, centerZ, fillType)
            if nearbyPileProps and nearbyPileProps.moisture then
                moisture = nearbyPileProps.moisture
            end
        end

        if not moisture then
            moisture = g_currentMission.MoistureSystem:getMoistureAtPosition(centerX, centerZ)
        end
    end

    -- Get drop area coordinates
    local sx, sy, sz = getWorldTranslation(dropArea.start)
    local wx, wy, wz = getWorldTranslation(dropArea.width)
    local hx, hy, hz = getWorldTranslation(dropArea.height)

    tracker:addWindrowerDrop(sx, sz, wx, wz, hx, hz, fillType, dropped, moisture)

    return dropped, lineOffset
end

Windrower.processWindrowerArea = Utils.overwrittenFunction(Windrower.processWindrowerArea,
    MSWindrowerExtension.processWindrowerArea)
Windrower.processDropArea = Utils.overwrittenFunction(Windrower.processDropArea, MSWindrowerExtension.processDropArea)
