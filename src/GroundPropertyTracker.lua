GroundPropertyTracker = {}
local GroundPropertyTracker_mt = Class(GroundPropertyTracker)

GroundPropertyTracker.GRID_SIZE = 2             -- 2m grid cells for consistent world grid
GroundPropertyTracker.MIN_GRASS_MOISTURE = 0.05 -- 5% minimum moisture for grass
GroundPropertyTracker.MAX_GRASS_MOISTURE = 0.40 -- 40% maximum moisture for grass

GroundPropertyTracker.TEDDED_COOLDOWN_CYCLES = 10
GroundPropertyTracker.DELAYED_PROCESSING_CYCLES = 4

GroundPropertyTracker.GRASS_CONVERSION_MAP = {
    ["GRASS_WINDROW"] = "DRYGRASS_WINDROW",
    ["ALFALFA_WINDROW"] = "DRYALFALFA_WINDROW",
    ["CLOVER_WINDROW"] = "DRYCLOVER_WINDROW"
}

function GroundPropertyTracker.new()
    local self = setmetatable({}, GroundPropertyTracker_mt)

    self.mission = g_currentMission
    self.isServer = self.mission:getIsServer()
    self.loadedGridSize = nil

    -- Main storage: grid-based piles indexed by "gridX_gridZ_fillType"
    self.gridPiles = {}

    -- Separate storage for grass piles
    self.grassPiles = {}

    -- Buffer for tedded grid cells (delays processing by 6 cycles)
    -- Value is number of update cycles remaining before moving to teddedGridCells
    self.teddedGridCellsBuffer = {}

    -- Track tedded grid cells (will apply additional moisture reduction)
    self.teddedGridCells = {}

    -- Track processed tedded cells with cooldown counter to prevent re-marking
    -- Value is number of update cycles remaining before cell can be marked again
    self.teddedGridCellsCooldown = {}

    -- Track processed mowed cells with cooldown counter to prevent re-marking
    -- Value is number of update cycles remaining before cell can be marked again
    self.recentMowedCells = {}

    -- Track cells that are designated as "hay cells" (recently converted to hay)
    -- Value is number of update cycles remaining
    self.hayCells = {}

    -- Track moisture of grass being moved by tedder
    -- Key: "gridX_gridZ", Value: moisture value
    self.teddedGrassMoisture = {}

    return self
end

---
-- Get grid-aligned position for a world coordinate
-- @param x, z: World coordinates
-- @return gridX, gridZ: Grid-aligned center coordinates
---
function GroundPropertyTracker:getGridPosition(x, z)
    local gridX = math.floor(x / GroundPropertyTracker.GRID_SIZE) * GroundPropertyTracker.GRID_SIZE +
        GroundPropertyTracker.GRID_SIZE / 2
    local gridZ = math.floor(z / GroundPropertyTracker.GRID_SIZE) * GroundPropertyTracker.GRID_SIZE +
        GroundPropertyTracker.GRID_SIZE / 2
    return gridX, gridZ
end

---
-- Get grid key for storage
-- @param gridX, gridZ: Grid-aligned coordinates
-- @param fillType: The filltype index
-- @return string key for storage
---
function GroundPropertyTracker:getGridKey(gridX, gridZ, fillType)
    return string.format("%d_%d_%d", gridX, gridZ, fillType)
end

---
-- Get simple grid key without fillType (for tedded cells tracking)
-- @param gridX, gridZ: Grid-aligned coordinates
-- @return string key for storage
---
function GroundPropertyTracker:getSimpleGridKey(gridX, gridZ)
    return string.format("%d_%d", gridX, gridZ)
end

function GroundPropertyTracker:delete()
    self.gridPiles = {}
    self.grassPiles = {}
end

---
-- Helper to count table entries
---
function GroundPropertyTracker:countTable(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

---
-- Calculate overlap area between a grid cell and a bounding box
-- @param cellX, cellZ: Grid cell center coordinates
-- @param minX, maxX, minZ, maxZ: Bounding box extents
-- @return overlap area in square meters
---
function GroundPropertyTracker:calculateCellOverlap(cellX, cellZ, minX, maxX, minZ, maxZ)
    local halfSize = GroundPropertyTracker.GRID_SIZE / 2
    local cellMinX = cellX - halfSize
    local cellMaxX = cellX + halfSize
    local cellMinZ = cellZ - halfSize
    local cellMaxZ = cellZ + halfSize

    -- Calculate intersection rectangle
    local overlapMinX = math.max(cellMinX, minX)
    local overlapMaxX = math.min(cellMaxX, maxX)
    local overlapMinZ = math.max(cellMinZ, minZ)
    local overlapMaxZ = math.min(cellMaxZ, maxZ)

    -- Calculate overlap area
    if overlapMinX < overlapMaxX and overlapMinZ < overlapMaxZ then
        return (overlapMaxX - overlapMinX) * (overlapMaxZ - overlapMinZ)
    end

    return 0
end

---
-- Find which grid cells an area intersects with proportional overlap areas
-- @param sx, sz, wx, wz, hx, hz: Area corner coordinates
-- @return table of {gridX, gridZ, overlapArea} entries, totalArea
---
function GroundPropertyTracker:getAffectedGridCells(sx, sz, wx, wz, hx, hz)
    local minX = math.min(sx, wx, hx)
    local maxX = math.max(sx, wx, hx)
    local minZ = math.min(sz, wz, hz)
    local maxZ = math.max(sz, wz, hz)

    local cells = {}
    local totalOverlapArea = 0

    -- Find all grid cells that intersect this bounding box
    local startGridX = math.floor(minX / GroundPropertyTracker.GRID_SIZE) * GroundPropertyTracker.GRID_SIZE
    local endGridX = math.floor(maxX / GroundPropertyTracker.GRID_SIZE) * GroundPropertyTracker.GRID_SIZE
    local startGridZ = math.floor(minZ / GroundPropertyTracker.GRID_SIZE) * GroundPropertyTracker.GRID_SIZE
    local endGridZ = math.floor(maxZ / GroundPropertyTracker.GRID_SIZE) * GroundPropertyTracker.GRID_SIZE

    for gx = startGridX, endGridX, GroundPropertyTracker.GRID_SIZE do
        for gz = startGridZ, endGridZ, GroundPropertyTracker.GRID_SIZE do
            local gridX, gridZ = self:getGridPosition(gx + GroundPropertyTracker.GRID_SIZE / 2,
                gz + GroundPropertyTracker.GRID_SIZE / 2)
            local overlapArea = self:calculateCellOverlap(gridX, gridZ, minX, maxX, minZ, maxZ)

            if overlapArea > 0 then
                table.insert(cells, { gridX = gridX, gridZ = gridZ, overlapArea = overlapArea })
                totalOverlapArea = totalOverlapArea + overlapArea
            end
        end
    end

    return cells, totalOverlapArea
end

---
-- Add a new dropped pile to tracking
-- Distributes properties across grid cells based on overlap area
-- @param sx, sz, wx, wz, hx, hz: Area coordinates (start, width, height corners)
-- @param fillType: The filltype index being dropped
-- @param volume: Volume in liters (used only for weighted averaging, not stored)
-- @param properties: Table of properties {moisture=0.18}
---
function GroundPropertyTracker:addPile(sx, sz, wx, wz, hx, hz, fillType, volume, properties)
    if not self.isServer then return end

    local moistureSystem = g_currentMission.MoistureSystem

    -- Only track fillTypes defined in CropValueMap or grass types
    if not moistureSystem:shouldTrackFillType(fillType) then return end

    -- Get all grid cells this drop affects with their overlap areas
    local affectedCells, totalOverlapArea = self:getAffectedGridCells(sx, sz, wx, wz, hx, hz)

    if #affectedCells == 0 or totalOverlapArea == 0 then return end

    -- Choose storage based on fillType
    local storage = moistureSystem:isGrassFillType(fillType) and self.grassPiles or self.gridPiles

    -- Distribute proportionally based on overlap area
    for _, cell in ipairs(affectedCells) do
        local proportion = cell.overlapArea / totalOverlapArea
        local volumeForCell = volume * proportion

        local key = self:getGridKey(cell.gridX, cell.gridZ, fillType)
        local pile = storage[key]

        if pile then
            -- Update existing pile with volume-weighted averaging
            -- Get actual volume from density map for accurate weighting
            local checkRadius = GroundPropertyTracker.GRID_SIZE / 2
            local existingVolume = DensityMapHeightUtil.getFillLevelAtArea(
                fillType,
                cell.gridX - checkRadius, cell.gridZ - checkRadius,
                cell.gridX + checkRadius, cell.gridZ - checkRadius,
                cell.gridX - checkRadius, cell.gridZ + checkRadius
            )

            local totalVolume = existingVolume + volumeForCell

            -- Calculate new properties with volume-weighted averaging
            local newProperties = {}
            for propKey, propValue in pairs(properties or {}) do
                local originalValue = pile.properties[propKey]
                if originalValue and totalVolume > 0 then
                    -- Volume-weighted average
                    newProperties[propKey] = (originalValue * existingVolume + propValue * volumeForCell) / totalVolume
                    -- print(string.format(
                    --     "[TRACKER] Grid (%d,%d) %s: Original=%.3f (%.1fL) + Incoming=%.3f (%.1fL) = Result=%.3f (%.1fL total)",
                    --     cell.gridX, cell.gridZ, propKey, originalValue, existingVolume, propValue, volumeForCell,
                    --     newProperties[propKey], totalVolume))
                else
                    newProperties[propKey] = propValue
                end
            end

            -- Send event to update pile
            g_client:getServerConnection():sendEvent(PilePropertyUpdateEvent.new(
                key, newProperties, fillType, cell.gridX, cell.gridZ
            ))
        else
            -- Create new pile via event
            g_client:getServerConnection():sendEvent(PilePropertyUpdateEvent.new(
                key, properties or {}, fillType, cell.gridX, cell.gridZ
            ))

            for propKey, propValue in pairs(properties or {}) do
                -- print(string.format("[TRACKER CREATE] Grid (%d,%d) %s: NEW PILE = %.3f (%.1fL from %.1fL drop)",
                --     cell.gridX, cell.gridZ,
                --     propKey, propValue, volumeForCell, volume))
            end
        end
    end
end

---
-- Get properties for material at a specific location
-- @param x, z: World coordinates
-- @param fillType: The filltype to check
-- @return properties table or nil
---
function GroundPropertyTracker:getPropertiesAtLocation(x, z, fillType)
    local storage = g_currentMission.MoistureSystem:isGrassFillType(fillType) and self.grassPiles or self.gridPiles
    local gridX, gridZ = self:getGridPosition(x, z)
    local key = self:getGridKey(gridX, gridZ, fillType)
    local pile = storage[key]

    if pile then
        return pile.properties
    end

    return nil
end

---
-- Mark an area as tedded by adding to buffer with 6-cycle delay
-- Only marks cells that haven't been processed recently (5 second cooldown)
-- Only marks cells where >50% of the cell is within the tedded area
-- @param sx, sz, wx, wz, hx, hz: Area corner coordinates
---
function GroundPropertyTracker:markAreaTedded(sx, sz, wx, wz, hx, hz)
    if not self.isServer then return end

    -- Get all grid cells this area overlaps
    local affectedCells = self:getAffectedGridCells(sx, sz, wx, wz, hx, hz)

    -- Calculate cell area for overlap threshold check
    local cellArea = GroundPropertyTracker.GRID_SIZE * GroundPropertyTracker.GRID_SIZE
    local overlapThreshold = cellArea * 0.5

    -- Add each cell to buffer with 6-cycle delay, only if not recently processed
    for _, cell in ipairs(affectedCells) do
        -- Only mark cells where more than 50% is within the tedded area
        if cell.overlapArea > overlapThreshold then
            local gridKey = self:getSimpleGridKey(cell.gridX, cell.gridZ)

            -- Only mark if not in cooldown and not already in buffer
            if not self.teddedGridCellsCooldown[gridKey] and not self.teddedGridCellsBuffer[gridKey] then
                self.teddedGridCellsBuffer[gridKey] = GroundPropertyTracker.DELAYED_PROCESSING_CYCLES
            end
        end
    end
end

---
-- Mark an area as mowed by setting all overlapping grid cells to true
-- Only marks cells that haven't been processed recently (2 second cooldown)
-- Only marks cells where >50% of the cell is within the mowed area
-- @param sx, sz, wx, wz, hx, hz: Area corner coordinates
---
function GroundPropertyTracker:markAreaMowed(sx, sz, wx, wz, hx, hz)
    if not self.isServer then return end

    -- Get all grid cells this area overlaps
    local affectedCells = self:getAffectedGridCells(sx, sz, wx, wz, hx, hz)

    -- Calculate cell area for overlap threshold check
    local cellArea = GroundPropertyTracker.GRID_SIZE * GroundPropertyTracker.GRID_SIZE
    local overlapThreshold = cellArea * 0.5

    -- Mark each cell as mowed with cooldown (skip drying for 4 seconds)
    for _, cell in ipairs(affectedCells) do
        -- Only mark cells where more than 50% is within the mowed area
        if cell.overlapArea > overlapThreshold then
            local gridKey = self:getSimpleGridKey(cell.gridX, cell.gridZ)

            -- Set cooldown to prevent drying for newly mowed grass
            if not self.recentMowedCells[gridKey] then
                self.recentMowedCells[gridKey] = GroundPropertyTracker.DELAYED_PROCESSING_CYCLES
            end
        end
    end
end

---
-- Convert grass to hay in a specific cell if grass is present
-- @param gridX, gridZ: Grid coordinates
-- @param grassFillType: The grass fillType index
-- @param hayFillType: The hay fillType index
---
function GroundPropertyTracker:convertGrassToHayInCell(gridX, gridZ, grassFillType, hayFillType)
    local checkRadius = GroundPropertyTracker.GRID_SIZE / 2

    -- Check if there's grass in this cell
    local grassVolume = DensityMapHeightUtil.getFillLevelAtArea(
        grassFillType,
        gridX - checkRadius, gridZ - checkRadius,
        gridX + checkRadius, gridZ - checkRadius,
        gridX - checkRadius, gridZ + checkRadius
    )

    if grassVolume > 0 then
        -- Convert grass to hay with buffer
        local halfSize = GroundPropertyTracker.GRID_SIZE / 2
        local buffer = halfSize * 0.2
        local sx = gridX - halfSize - buffer
        local sz = gridZ - halfSize - buffer
        local wx = gridX + halfSize + buffer
        local wz = gridZ - halfSize - buffer
        local hx = gridX - halfSize - buffer
        local hz = gridZ + halfSize + buffer

        DensityMapHeightUtil.changeFillTypeAtArea(sx, sz, wx, wz, hx, hz, grassFillType, hayFillType)

        -- Clean up tracked grass pile in this cell
        local key = self:getGridKey(gridX, gridZ, grassFillType)
        if self.grassPiles[key] then
            self.grassPiles[key] = nil
        end

        -- Check for remaining content and cleanup
        self:checkPileHasContent(gridX, gridZ, hayFillType)
    end
end

---
-- Update moisture levels for all grass piles
-- @param moistureDelta: Amount to change moisture (can be positive or negative)
---
function GroundPropertyTracker:updateGrassMoisture(moistureDelta)
    if not self.isServer then return end
    if moistureDelta == 0 then return end

    -- Copy tedded cells for this cycle and clear the table for next cycle
    local teddedCellsThisCycle = {}
    for gridKey, _ in pairs(self.teddedGridCells) do
        teddedCellsThisCycle[gridKey] = true
    end
    self.teddedGridCells = {}

    local processedThisCycle = {} -- Track cells we've already processed to avoid double-reduction

    -- First: Force convert any grass in hay cells to hay
    -- Check all grass types defined in conversion map
    for grassTypeName, hayTypeName in pairs(GroundPropertyTracker.GRASS_CONVERSION_MAP) do
        local grassFillType = g_fillTypeManager:getFillTypeIndexByName(grassTypeName)
        local hayFillType = g_fillTypeManager:getFillTypeIndexByName(hayTypeName)

        if grassFillType and hayFillType then
            for gridKey, _ in pairs(self.hayCells) do
                local gridX, gridZ = gridKey:match("([^_]+)_([^_]+)")
                gridX = tonumber(gridX)
                gridZ = tonumber(gridZ)

                self:convertGrassToHayInCell(gridX, gridZ, grassFillType, hayFillType)
            end
        end
    end

    -- Process tedded cells that don't have piles yet (newly dropped grass from tedder)
    local moistureSystem = g_currentMission.MoistureSystem
    local checkRadius = GroundPropertyTracker.GRID_SIZE / 2

    for gridKey, _ in pairs(teddedCellsThisCycle) do
        local gridX, gridZ = gridKey:match("([^_]+)_([^_]+)")
        gridX = tonumber(gridX)
        gridZ = tonumber(gridZ)

        -- Skip drying for recently mowed cells
        if self.recentMowedCells[gridKey] then
            continue
        end
        -- Check each grass type from conversion map
        for grassTypeName, _ in pairs(GroundPropertyTracker.GRASS_CONVERSION_MAP) do
            local grassFillType = g_fillTypeManager:getFillTypeIndexByName(grassTypeName)
            if grassFillType then
                local key = self:getGridKey(gridX, gridZ, grassFillType)

                -- Check if this cell already has a tracked pile
                if not self.grassPiles[key] then
                    -- Check if there's actually grass on the ground at this location
                    local existingVolume = DensityMapHeightUtil.getFillLevelAtArea(
                        grassFillType,
                        gridX - checkRadius, gridZ - checkRadius,
                        gridX + checkRadius, gridZ - checkRadius,
                        gridX - checkRadius, gridZ + checkRadius
                    )

                    if existingVolume > 0 then
                        -- Normal tedded grass processing
                        local baseMoisture
                        if self.teddedGrassMoisture[gridKey] then
                            baseMoisture = self.teddedGrassMoisture[gridKey]
                            self.teddedGrassMoisture[gridKey] = nil
                        else
                            baseMoisture = moistureSystem:getMoistureAtPosition(gridX, gridZ)
                        end

                        local teddedMoisture = baseMoisture -
                            g_currentMission.MoistureSystem.settings.teddingMoistureReduction
                        teddedMoisture = math.max(GroundPropertyTracker.MIN_GRASS_MOISTURE,
                            math.min(GroundPropertyTracker.MAX_GRASS_MOISTURE, teddedMoisture))

                        self.grassPiles[key] = {
                            gridX = gridX,
                            gridZ = gridZ,
                            fillType = grassFillType,
                            properties = {
                                moisture = teddedMoisture
                            }
                        }

                        g_client:getServerConnection():sendEvent(PilePropertyUpdateEvent.new(
                            key, self.grassPiles[key].properties, grassFillType, gridX, gridZ, true
                        ))

                        -- Mark this cell as processed so we don't reduce it again in the second loop
                        processedThisCycle[gridKey] = true
                        -- Start cooldown to prevent immediate re-tedding
                        self.teddedGridCellsCooldown[gridKey] = GroundPropertyTracker.TEDDED_COOLDOWN_CYCLES
                    end
                end
            end
        end
    end

    -- Update all grass piles with fixed min/max clamping
    for key, pile in pairs(self.grassPiles) do
        if pile.properties.moisture then
            local gridKey = self:getSimpleGridKey(pile.gridX, pile.gridZ)

            -- Skip drying for recently mowed cells
            if self.recentMowedCells[gridKey] then
                continue
            end
            local totalDelta = moistureDelta

            -- Check if this grid cell was tedded - apply additional reduction
            if teddedCellsThisCycle[gridKey] and not processedThisCycle[gridKey] then
                -- Apply tedding reduction
                totalDelta = totalDelta - g_currentMission.MoistureSystem.settings.teddingMoistureReduction

                local newMoisture = pile.properties.moisture + totalDelta
                pile.properties.moisture = math.max(GroundPropertyTracker.MIN_GRASS_MOISTURE,
                    math.min(GroundPropertyTracker.MAX_GRASS_MOISTURE, newMoisture))
                g_client:getServerConnection():sendEvent(PilePropertyUpdateEvent.new(
                    key, pile.properties, pile.fillType, pile.gridX, pile.gridZ, true
                ))

                -- Start cooldown for existing pile that was tedded
                self.teddedGridCellsCooldown[gridKey] = GroundPropertyTracker.TEDDED_COOLDOWN_CYCLES
            else
                -- No tedding, just apply natural moisture change
                local newMoisture = pile.properties.moisture + totalDelta
                pile.properties.moisture = math.max(GroundPropertyTracker.MIN_GRASS_MOISTURE,
                    math.min(GroundPropertyTracker.MAX_GRASS_MOISTURE, newMoisture))
                g_client:getServerConnection():sendEvent(PilePropertyUpdateEvent.new(
                    key, pile.properties, pile.fillType, pile.gridX, pile.gridZ, true
                ))
            end
        end
    end

    -- Decrement cooldown counters for processed tedded cells
    for gridKey, counter in pairs(self.teddedGridCellsCooldown) do
        self.teddedGridCellsCooldown[gridKey] = counter - 1
        if self.teddedGridCellsCooldown[gridKey] <= 0 then
            self.teddedGridCellsCooldown[gridKey] = nil
        end
    end

    -- Decrement cooldown counters for mowed cells
    for gridKey, counter in pairs(self.recentMowedCells) do
        self.recentMowedCells[gridKey] = counter - 1
        if self.recentMowedCells[gridKey] <= 0 then
            self.recentMowedCells[gridKey] = nil
        end
    end

    -- Decrement hay cell counters
    for gridKey, counter in pairs(self.hayCells) do
        self.hayCells[gridKey] = counter - 1
        if self.hayCells[gridKey] <= 0 then
            self.hayCells[gridKey] = nil
        end
    end

    -- Process tedded cells buffer: decrement and move to teddedGridCells when ready
    for gridKey, counter in pairs(self.teddedGridCellsBuffer) do
        self.teddedGridCellsBuffer[gridKey] = counter - 1
        if self.teddedGridCellsBuffer[gridKey] <= 0 then
            self.teddedGridCellsBuffer[gridKey] = nil
            self.teddedGridCells[gridKey] = true
        end
    end
end

---
-- Check if pile has content and remove tracking if empty
-- @param gridX, gridZ: Grid coordinates
-- @param fillType: The filltype to check
---
function GroundPropertyTracker:checkPileHasContent(gridX, gridZ, fillType)
    local moistureSystem = g_currentMission.MoistureSystem
    local checkRadius = GroundPropertyTracker.GRID_SIZE / 2
    local volume = DensityMapHeightUtil.getFillLevelAtArea(
        fillType,
        gridX - checkRadius, gridZ - checkRadius,
        gridX + checkRadius, gridZ - checkRadius,
        gridX - checkRadius, gridZ + checkRadius
    )

    if volume <= 0 then
        local key = self:getGridKey(gridX, gridZ, fillType)
        local storage = moistureSystem:isGrassFillType(fillType) and self.grassPiles or self.gridPiles
        if storage[key] then
            storage[key] = nil
            -- print(string.format("[CLEANUP] Removed empty pile at (%d,%d)", gridX, gridZ))
        end
    end
end

---
-- Get properties for pile at specific position
-- @param x, z: World coordinates
-- @param fillType: The filltype to check
-- @return properties table or nil
---
function GroundPropertyTracker:getPilePropertiesAtPosition(x, z, fillType)
    local moistureSystem = g_currentMission.MoistureSystem
    local storage = moistureSystem:isGrassFillType(fillType) and self.grassPiles or self.gridPiles
    local gridX, gridZ = self:getGridPosition(x, z)
    local key = self:getGridKey(gridX, gridZ, fillType)
    local pile = storage[key]

    if pile then
        return pile.properties
    end

    return nil
end

---
-- Convert grid cells from one size to another
-- Handles remapping when GRID_SIZE changes between save and load
-- @param fromSize: Original grid size from saved data
-- @param toSize: New grid size (current GRID_SIZE)
---
function GroundPropertyTracker:convertGridCells(fromSize, toSize)
    if not self.isServer then return end
    if fromSize == toSize then return end

    -- Temporary storage for new cells with volume tracking
    local newCells = {} -- [key] = { gridX, gridZ, fillType, isGrass, contributions[] }

    -- Collect all existing piles
    local oldPiles = {}

    for key, pile in pairs(self.gridPiles) do
        table.insert(oldPiles, {
            gridX = pile.gridX,
            gridZ = pile.gridZ,
            fillType = pile.fillType,
            properties = pile.properties,
            isGrass = false
        })
    end

    for key, pile in pairs(self.grassPiles) do
        table.insert(oldPiles, {
            gridX = pile.gridX,
            gridZ = pile.gridZ,
            fillType = pile.fillType,
            properties = pile.properties,
            isGrass = true
        })
    end

    -- Clear existing storage
    self.gridPiles = {}
    self.grassPiles = {}

    -- Process each old pile
    for _, oldPile in ipairs(oldPiles) do
        -- Calculate the area covered by the old grid cell
        local halfOldSize = fromSize / 2
        local minX = oldPile.gridX - halfOldSize
        local maxX = oldPile.gridX + halfOldSize
        local minZ = oldPile.gridZ - halfOldSize
        local maxZ = oldPile.gridZ + halfOldSize

        -- Find all new grid cells that overlap this old area
        local startGridX = math.floor(minX / toSize) * toSize
        local endGridX = math.floor(maxX / toSize) * toSize
        local startGridZ = math.floor(minZ / toSize) * toSize
        local endGridZ = math.floor(maxZ / toSize) * toSize

        for gx = startGridX, endGridX, toSize do
            for gz = startGridZ, endGridZ, toSize do
                -- Get new grid center (aligned to new grid size)
                local newGridX = gx + toSize / 2
                local newGridZ = gz + toSize / 2

                -- Check if there's actually material here
                local checkRadius = toSize / 2
                local volume = DensityMapHeightUtil.getFillLevelAtArea(
                    oldPile.fillType,
                    newGridX - checkRadius, newGridZ - checkRadius,
                    newGridX + checkRadius, newGridZ - checkRadius,
                    newGridX - checkRadius, newGridZ + checkRadius
                )

                if volume > 0 then
                    local newKey = self:getGridKey(newGridX, newGridZ, oldPile.fillType)

                    if not newCells[newKey] then
                        newCells[newKey] = {
                            gridX = newGridX,
                            gridZ = newGridZ,
                            fillType = oldPile.fillType,
                            isGrass = oldPile.isGrass,
                            contributions = {}
                        }
                    end

                    -- Add this old pile's contribution
                    table.insert(newCells[newKey].contributions, {
                        volume = volume,
                        properties = oldPile.properties
                    })
                end
            end
        end
    end

    -- Create final piles from accumulated contributions
    for key, cell in pairs(newCells) do
        local storage = cell.isGrass and self.grassPiles or self.gridPiles

        storage[key] = {
            gridX = cell.gridX,
            gridZ = cell.gridZ,
            fillType = cell.fillType,
            properties = {}
        }

        -- Calculate volume-weighted average of properties from all contributions
        local totalVolume = 0
        local weightedProperties = {}

        for _, contribution in ipairs(cell.contributions) do
            totalVolume = totalVolume + contribution.volume
            for propKey, propValue in pairs(contribution.properties) do
                if not weightedProperties[propKey] then
                    weightedProperties[propKey] = 0
                end
                weightedProperties[propKey] = weightedProperties[propKey] + (propValue * contribution.volume)
            end
        end

        -- Calculate final averaged properties
        if totalVolume > 0 then
            for propKey, weightedValue in pairs(weightedProperties) do
                storage[key].properties[propKey] = weightedValue / totalVolume
            end
        end
    end

    print(string.format("[TRACKER] Converted grid cells from size %dm to %dm. Old piles: %d, New cells: %d",
        fromSize, toSize, #oldPiles, self:countTable(newCells)))
end

function GroundPropertyTracker:saveToXMLFile(xmlFile, key)
    if not self.isServer then return end

    setXMLInt(xmlFile, key .. "#gridSize", GroundPropertyTracker.GRID_SIZE)

    local i = 0
    -- Save crop piles
    for gridKey, pile in pairs(self.gridPiles) do
        local pileKey = string.format("%s.cropPiles.pile(%d)", key, i)

        setXMLInt(xmlFile, pileKey .. "#fillType", pile.fillType)
        setXMLFloat(xmlFile, pileKey .. "#gridX", pile.gridX)
        setXMLFloat(xmlFile, pileKey .. "#gridZ", pile.gridZ)

        -- Save moisture
        if pile.properties.moisture then
            setXMLFloat(xmlFile, pileKey .. "#moisture", pile.properties.moisture)
        end

        i = i + 1
    end

    local cropCount = i

    -- Save grass piles
    i = 0
    for gridKey, pile in pairs(self.grassPiles) do
        local pileKey = string.format("%s.grassPiles.pile(%d)", key, i)

        setXMLInt(xmlFile, pileKey .. "#fillType", pile.fillType)
        setXMLFloat(xmlFile, pileKey .. "#gridX", pile.gridX)
        setXMLFloat(xmlFile, pileKey .. "#gridZ", pile.gridZ)

        -- Save moisture
        if pile.properties.moisture then
            setXMLFloat(xmlFile, pileKey .. "#moisture", pile.properties.moisture)
        end

        i = i + 1
    end

    -- print(string.format("GroundPropertyTracker: Saved %d crop piles, %d grass piles", cropCount, i))
end

function GroundPropertyTracker:loadFromXMLFile(xmlFile, key)
    if not self.isServer then return end

    self.loadedGridSize = getXMLInt(xmlFile, key .. "#gridSize") or 5

    local i = 0
    local loadedCount = 0

    -- Load crop piles
    while true do
        local pileKey = string.format("%s.cropPiles.pile(%d)", key, i)

        if not hasXMLProperty(xmlFile, pileKey) then
            break
        end

        local fillType = getXMLInt(xmlFile, pileKey .. "#fillType")
        local gridX = getXMLFloat(xmlFile, pileKey .. "#gridX")
        local gridZ = getXMLFloat(xmlFile, pileKey .. "#gridZ")

        local pile = {
            fillType = fillType,
            fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillType),
            gridX = gridX,
            gridZ = gridZ,
            properties = {}
        }

        -- Load moisture
        local moisture = getXMLFloat(xmlFile, pileKey .. "#moisture")
        if moisture then
            pile.properties.moisture = moisture
        end

        local gridKey = self:getGridKey(gridX, gridZ, fillType)
        self.gridPiles[gridKey] = pile
        loadedCount = loadedCount + 1

        i = i + 1
    end

    -- local cropCount = loadedCount

    -- Load grass piles
    i = 0
    loadedCount = 0
    while true do
        local pileKey = string.format("%s.grassPiles.pile(%d)", key, i)

        if not hasXMLProperty(xmlFile, pileKey) then
            break
        end

        local fillType = getXMLInt(xmlFile, pileKey .. "#fillType")
        local gridX = getXMLFloat(xmlFile, pileKey .. "#gridX")
        local gridZ = getXMLFloat(xmlFile, pileKey .. "#gridZ")

        local pile = {
            fillType = fillType,
            fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillType),
            gridX = gridX,
            gridZ = gridZ,
            properties = {}
        }

        -- Load moisture
        local moisture = getXMLFloat(xmlFile, pileKey .. "#moisture")
        if moisture then
            pile.properties.moisture = moisture
        end

        local gridKey = self:getGridKey(gridX, gridZ, fillType)
        self.grassPiles[gridKey] = pile
        loadedCount = loadedCount + 1

        i = i + 1
    end

    -- print(string.format("GroundPropertyTracker: Loaded %d crop piles, %d grass piles", cropCount, loadedCount))
end
