MSTedderExtension = {}

-- Configuration
MSTedderExtension.MOISTURE_REDUCTION_PER_PASS = 0.05
MSTedderExtension.DRY_THRESHOLD = 0.07

function MSTedderExtension:processDropArea(superFunc, dropArea, fillType, amount)
    if g_fillTypeManager:getFillTypeNameByIndex(fillType) ~= "GRASS_WINDROW" then
        return superFunc(self, dropArea, fillType, amount)
    end

    -- Check if dropping grass into a recent hay cell - if so, convert to hay
    local tracker = g_currentMission.harvestPropertyTracker
    local moistureSystem = g_currentMission.MoistureSystem
    local sx, sy, sz = getWorldTranslation(dropArea.start)
    local wx, wy, wz = getWorldTranslation(dropArea.width)
    local hx, hy, hz = getWorldTranslation(dropArea.height)
    local centerX = (sx + wx + hx) / 3
    local centerZ = (sz + wz + hz) / 3

    -- if tracker:isRecentHayCell(centerX, centerZ) then
    --     print(string.format("[TEDDER] Dropping grass at (%.0f,%.0f) into recent hay cell - converting to hay", centerX,
    --         centerZ))
    --     local hayFillType = g_fillTypeManager:getFillTypeIndexByName("DRYGRASS_WINDROW")
    --     return superFunc(self, dropArea, hayFillType, amount)
    -- end

    local startX, startY, startZ, endX, endY, endZ, radius = DensityMapHeightUtil.getLineByArea(dropArea.start,
        dropArea.width, dropArea.height, true)
    local dropped, lineOffset = DensityMapHeightUtil.tipToGroundAroundLine(self, amount, fillType, startX, startY, startZ,
        endX, endY, endZ, radius, nil, dropArea.lineOffset, false, nil, false)
    dropArea.lineOffset = lineOffset


    if dropped > 0 then
        -- Don't call addPile here - let updateGrassMoisture handle pile creation/update
        -- But store the pickup moisture so it can be used when recreating the pile
        
        -- Store the pickup moisture for affected grid cells
        if dropArea.outputMoisture then
            local affectedCells = tracker:getAffectedGridCells(sx, sz, wx, wz, hx, hz)
            for _, cell in ipairs(affectedCells) do
                local gridKey = tracker:getSimpleGridKey(cell.gridX, cell.gridZ)
                tracker.teddedGrassMoisture[gridKey] = dropArea.outputMoisture
            end
        end
        
        -- Mark area as tedded so updateGrassMoisture will process it
        tracker:markAreaTedded(sx, sz, wx, wz, hx, hz)
    end
    return dropped
end

Tedder.processDropArea = Utils.overwrittenFunction(Tedder.processDropArea, MSTedderExtension.processDropArea)

function MSTedderExtension:processTedderArea(_, workArea, dt)
    local spec = self.spec_tedder
    local workAreaSpec = self.spec_workArea


    local tracker = g_currentMission.harvestPropertyTracker
    local grassFillTypeIndex = g_fillTypeManager:getFillTypeIndexByName("GRASS_WINDROW")
    local hayFillTypeIndex = g_fillTypeManager:getFillTypeIndexByName("DRYGRASS_WINDROW")

    local sx, sy, sz = getWorldTranslation(workArea.start)
    local wx, wy, wz = getWorldTranslation(workArea.width)
    local hx, hy, hz = getWorldTranslation(workArea.height)
    local centerX = (sx + wx + hx) / 3
    local centerZ = (sz + wz + hz) / 3

    local positionMoisture
    local existingProps = tracker:getPropertiesAtLocation(centerX, centerZ, grassFillTypeIndex)

    if existingProps and existingProps.moisture then
        -- Grass already here with metadata - use it
        positionMoisture = existingProps.moisture
        print(string.format("[TEDDER] Pickup at (%.0f,%.0f): Found pile moisture %.1f%%", centerX, centerZ,
            positionMoisture * 100))
    else
        -- -- No pile at current location - check adjacent cells for lowest moisture
        -- local adjacentCells = tracker:getAdjacentCellsWithMoisture(centerX, centerZ, grassFillTypeIndex)

        -- if #adjacentCells > 0 then
        --     -- Find the lowest moisture from adjacent cells
        --     local lowestMoisture = math.huge
        --     for _, cell in ipairs(adjacentCells) do
        --         if cell.properties.moisture < lowestMoisture then
        --             lowestMoisture = cell.properties.moisture
        --         end
        --     end
        --     positionMoisture = lowestMoisture
        --     print(string.format("[TEDDER] Pickup at (%.0f,%.0f): Using adjacent tedded lowest moisture %.1f%% from %d cells",
        --         centerX, centerZ, positionMoisture * 100, #adjacentCells))
        -- else
        -- No adjacent data - fall back to field moisture
        -- positionMoisture = moistureSystem:getMoistureAtPosition(centerX, centerZ)
        -- print(string.format("[TEDDER] Pickup at (%.0f,%.0f): No adjacent data, using field moisture %.1f%%",
        --     centerX, centerZ, positionMoisture * 100))
        positionMoisture = nil
        -- end
    end

    -- pick up
    local lsx, lsy, lsz, lex, ley, lez, lineRadius = DensityMapHeightUtil.getLineByAreaDimensions(sx, sy, sz, wx, wy, wz,
        hx, hy, hz, true)

    for targetFillType, inputFillTypes in pairs(spec.fillTypeConvertersReverse) do
        local pickedUpLiters = 0
        local pickedUpHay = 0
        for _, inputFillType in ipairs(inputFillTypes) do
            local pickup = DensityMapHeightUtil.tipToGroundAroundLine(self, -math.huge, inputFillType, lsx, lsy, lsz, lex,
                ley, lez,
                lineRadius, nil, nil, false, nil)
            if pickup ~= 0 then
                pickedUpLiters = pickedUpLiters + pickup
                if inputFillType == hayFillTypeIndex then
                    pickedUpHay = pickedUpHay + pickup
                end
            end
        end

        if pickedUpLiters == 0 and workArea.lastDropFillType ~= FillType.UNKNOWN then
            targetFillType = workArea.lastDropFillType
        end

        -- local pickedUpNonHay = math.abs(pickedUpLiters) > math.abs(pickedUpHay)
        local gridCells = tracker:getAffectedGridCells(sx, sz, wx, wz, hx, hz)
        if pickedUpLiters ~= 0 and targetFillType == hayFillTypeIndex then
            for _, cell in pairs(gridCells) do
                tracker:checkPileHasContent(cell.gridX, cell.gridZ, grassFillTypeIndex)
            end
        end

        workArea.lastPickupLiters = -pickedUpLiters
        workArea.litersToDrop = workArea.litersToDrop + workArea.lastPickupLiters

        -- drop
        local dropArea = workAreaSpec.workAreas[workArea.dropWindrowWorkAreaIndex]
        if dropArea ~= nil and workArea.litersToDrop > 0 then
            local dropped

            if g_fillTypeManager:getFillTypeNameByIndex(targetFillType) == "DRYGRASS_WINDROW" and pickedUpHay == 0 then
                -- override default hay drop
                dropArea.outputMoisture = positionMoisture
                dropped = self:processDropArea(dropArea, grassFillTypeIndex, workArea.litersToDrop)
                dropArea.outputMoisture = nil
            else
                dropped = self:processDropArea(dropArea, targetFillType, workArea.litersToDrop)
            end

            workArea.lastDropFillType = targetFillType
            workArea.lastDroppedLiters = dropped
            spec.lastDroppedLiters = spec.lastDroppedLiters + dropped
            workArea.litersToDrop = workArea.litersToDrop - dropped

            if self.isServer then
                local lastSpeed = self:getLastSpeed(true)
                if dropped > 0 and lastSpeed > 0.5 then
                    local changedFillType = false
                    if spec.tedderWorkAreaFillTypes[workArea.tedderWorkAreaIndex] ~= targetFillType then
                        spec.tedderWorkAreaFillTypes[workArea.tedderWorkAreaIndex] = targetFillType
                        self:raiseDirtyFlags(spec.fillTypesDirtyFlag)
                        changedFillType = true
                    end

                    local effects = spec.workAreaToEffects[workArea.index]
                    if effects ~= nil then
                        for _, effect in ipairs(effects) do
                            effect.activeTime = g_currentMission.time + effect.activeTimeDuration

                            if not effect.isActiveSent then
                                effect.isActiveSent = true
                                self:raiseDirtyFlags(spec.effectDirtyFlag)
                            end

                            if changedFillType then
                                g_effectManager:setEffectTypeInfo(effect.effects, targetFillType)
                            end

                            if not effect.isActive then
                                g_effectManager:setEffectTypeInfo(effect.effects, targetFillType)
                                g_effectManager:startEffects(effect.effects)
                            end

                            g_effectManager:setDensity(effect.effects, math.max(lastSpeed / self:getSpeedLimit(), 0.6))

                            effect.isActive = true
                        end
                    end
                end
            end
        end
    end

    if self:getLastSpeed() > 0.5 then
        spec.stoneLastState = FSDensityMapUtil.getStoneArea(sx, sz, wx, wz, hx, hz)
    else
        spec.stoneLastState = 0
    end

    local areaWidth = MathUtil.vector3Length(lsx - lex, lsy - ley, lsz - lez)
    local area = areaWidth * self.lastMovedDistance

    return area, area
end

Tedder.processTedderArea = Utils.overwrittenFunction(Tedder.processTedderArea, MSTedderExtension.processTedderArea)
