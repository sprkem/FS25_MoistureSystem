HarvestPropertyTracker = {}
local HarvestPropertyTracker_mt = Class(HarvestPropertyTracker)

HarvestPropertyTracker.GRID_SIZE = 5             -- 5m grid cells for consistent world grid
HarvestPropertyTracker.MIN_GRASS_MOISTURE = 0.05 -- 5% minimum moisture for grass
HarvestPropertyTracker.MAX_GRASS_MOISTURE = 0.40 -- 40% maximum moisture for grass

-- Calculate cooldown cycles: 2000ms / 500ms updateInterval = 4 cycles
HarvestPropertyTracker.TEDDED_COOLDOWN_CYCLES = 10

function HarvestPropertyTracker.new()
    local self = setmetatable({}, HarvestPropertyTracker_mt)

    self.mission = g_currentMission
    self.isServer = self.mission:getIsServer()

    -- Main storage: grid-based piles indexed by "gridX_gridZ_fillType"
    self.gridPiles = {}

    -- Separate storage for grass/grass windrow piles
    self.grassPiles = {}

    -- Track tedded grid cells (will apply additional moisture reduction)
    self.teddedGridCells = {}

    -- Track processed tedded cells with cooldown counter to prevent re-marking
    -- Value is number of update cycles remaining before cell can be marked again
    self.processedTeddedCells = {}

    -- Track cells that are designated as "hay cells" (recently converted to hay)
    -- Value is number of update cycles remaining (10 cycles = 5 seconds at 500ms/cycle)
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
function HarvestPropertyTracker:getGridPosition(x, z)
    local gridX = math.floor(x / HarvestPropertyTracker.GRID_SIZE) * HarvestPropertyTracker.GRID_SIZE +
        HarvestPropertyTracker.GRID_SIZE / 2
    local gridZ = math.floor(z / HarvestPropertyTracker.GRID_SIZE) * HarvestPropertyTracker.GRID_SIZE +
        HarvestPropertyTracker.GRID_SIZE / 2
    return gridX, gridZ
end

---
-- Get grid key for storage
-- @param gridX, gridZ: Grid-aligned coordinates
-- @param fillType: The filltype index
-- @return string key for storage
---
function HarvestPropertyTracker:getGridKey(gridX, gridZ, fillType)
    return string.format("%d_%d_%d", gridX, gridZ, fillType)
end

---
-- Get simple grid key without fillType (for tedded cells tracking)
-- @param gridX, gridZ: Grid-aligned coordinates
-- @return string key for storage
---
function HarvestPropertyTracker:getSimpleGridKey(gridX, gridZ)
    return string.format("%d_%d", gridX, gridZ)
end

---
-- Check if fillType is grass or grass windrow
-- @param fillType: The filltype index
-- @return true if grass type
---
function HarvestPropertyTracker:isGrassFillType(fillType)
    local grasses = {
        ["GRASS_WINDROW"] = true,
        ["GRASS"] = true,
        ["ALFALFA_WINDROW"] = true,
        ["ALFALFA"] = true,
        ["CLOVER_WINDROW"] = true,
        ["CLOVER"] = true
    }
    local fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillType)
    return grasses[fillTypeName] or false
end

---
-- Check if fillType should be tracked (defined in CropValueMap)
-- @param fillType: The filltype index
-- @return true if should be tracked
---
function HarvestPropertyTracker:shouldTrackFillType(fillType)
    if self:isGrassFillType(fillType) then
        return true
    end
    return CropValueMap.Data[fillType] ~= nil
end

function HarvestPropertyTracker:delete()
    self.gridPiles = {}
    self.grassPiles = {}
end

---
-- Helper to count table entries
---
function HarvestPropertyTracker:countTable(t)
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
function HarvestPropertyTracker:calculateCellOverlap(cellX, cellZ, minX, maxX, minZ, maxZ)
    local halfSize = HarvestPropertyTracker.GRID_SIZE / 2
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
function HarvestPropertyTracker:getAffectedGridCells(sx, sz, wx, wz, hx, hz)
    local minX = math.min(sx, wx, hx)
    local maxX = math.max(sx, wx, hx)
    local minZ = math.min(sz, wz, hz)
    local maxZ = math.max(sz, wz, hz)

    local cells = {}
    local totalOverlapArea = 0

    -- Find all grid cells that intersect this bounding box
    local startGridX = math.floor(minX / HarvestPropertyTracker.GRID_SIZE) * HarvestPropertyTracker.GRID_SIZE
    local endGridX = math.floor(maxX / HarvestPropertyTracker.GRID_SIZE) * HarvestPropertyTracker.GRID_SIZE
    local startGridZ = math.floor(minZ / HarvestPropertyTracker.GRID_SIZE) * HarvestPropertyTracker.GRID_SIZE
    local endGridZ = math.floor(maxZ / HarvestPropertyTracker.GRID_SIZE) * HarvestPropertyTracker.GRID_SIZE

    for gx = startGridX, endGridX, HarvestPropertyTracker.GRID_SIZE do
        for gz = startGridZ, endGridZ, HarvestPropertyTracker.GRID_SIZE do
            local gridX, gridZ = self:getGridPosition(gx + HarvestPropertyTracker.GRID_SIZE / 2,
                gz + HarvestPropertyTracker.GRID_SIZE / 2)
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
function HarvestPropertyTracker:addPile(sx, sz, wx, wz, hx, hz, fillType, volume, properties)
    if not self.isServer then return end

    -- Only track fillTypes defined in CropValueMap or grass types
    if not self:shouldTrackFillType(fillType) then return end

    -- Get all grid cells this drop affects with their overlap areas
    local affectedCells, totalOverlapArea = self:getAffectedGridCells(sx, sz, wx, wz, hx, hz)

    if #affectedCells == 0 or totalOverlapArea == 0 then return end

    -- Choose storage based on fillType
    local storage = self:isGrassFillType(fillType) and self.grassPiles or self.gridPiles

    -- Distribute proportionally based on overlap area
    for _, cell in ipairs(affectedCells) do
        local proportion = cell.overlapArea / totalOverlapArea
        local volumeForCell = volume * proportion

        local key = self:getGridKey(cell.gridX, cell.gridZ, fillType)
        local pile = storage[key]

        if pile then
            -- Update existing pile with volume-weighted averaging
            -- Get actual volume from density map for accurate weighting
            local checkRadius = HarvestPropertyTracker.GRID_SIZE / 2
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
                    print(string.format(
                        "[TRACKER] Grid (%d,%d) %s: Original=%.3f (%.1fL) + Incoming=%.3f (%.1fL) = Result=%.3f (%.1fL total)",
                        cell.gridX, cell.gridZ, propKey, originalValue, existingVolume, propValue, volumeForCell,
                        newProperties[propKey], totalVolume))
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
                print(string.format("[TRACKER CREATE] Grid (%d,%d) %s: NEW PILE = %.3f (%.1fL from %.1fL drop)",
                    cell.gridX, cell.gridZ,
                    propKey, propValue, volumeForCell, volume))
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
function HarvestPropertyTracker:getPropertiesAtLocation(x, z, fillType)
    local storage = self:isGrassFillType(fillType) and self.grassPiles or self.gridPiles
    local gridX, gridZ = self:getGridPosition(x, z)
    local key = self:getGridKey(gridX, gridZ, fillType)
    local pile = storage[key]

    if pile then
        return pile.properties
    end

    return nil
end

---
-- Mark an area as tedded by setting all overlapping grid cells to true
-- Only marks cells that haven't been processed recently (2 second cooldown)
-- @param sx, sz, wx, wz, hx, hz: Area corner coordinates
---
function HarvestPropertyTracker:markAreaTedded(sx, sz, wx, wz, hx, hz)
    if not self.isServer then return end

    -- Get all grid cells this area overlaps
    local affectedCells = self:getAffectedGridCells(sx, sz, wx, wz, hx, hz)

    -- Mark each cell as tedded only if not recently processed
    for _, cell in ipairs(affectedCells) do
        local gridKey = self:getSimpleGridKey(cell.gridX, cell.gridZ)

        -- Only mark if not in cooldown
        if not self.processedTeddedCells[gridKey] then
            self.teddedGridCells[gridKey] = true
            print(string.format("[TEDDER MARK] Cell (%d,%d) MARKED for tedding", cell.gridX, cell.gridZ))
        else
            local counter = self.processedTeddedCells[gridKey]
            print(string.format("[TEDDER MARK] Cell (%d,%d) REJECTED - cooldown=%d cycles remaining",
                cell.gridX, cell.gridZ, counter))
        end
    end
end

---
-- Get adjacent grid cells (8-directional) that have been recently tedded and have moisture data
-- @param x, z: World coordinates
-- @param fillType: The filltype to check
-- @return table of {gridX, gridZ, properties} entries, or empty table if none found
---
function HarvestPropertyTracker:getAdjacentCellsWithMoisture(x, z, fillType)
    local storage = self:isGrassFillType(fillType) and self.grassPiles or self.gridPiles
    local gridX, gridZ = self:getGridPosition(x, z)
    local adjacentCells = {}

    -- Check 8 adjacent cells (N, S, E, W, NE, NW, SE, SW)
    local offsets = {
        { 0, HarvestPropertyTracker.GRID_SIZE },                                 -- North
        { 0, -HarvestPropertyTracker.GRID_SIZE },                                -- South
        { HarvestPropertyTracker.GRID_SIZE, 0 },                                 -- East
        { -HarvestPropertyTracker.GRID_SIZE, 0 },                                -- West
        { HarvestPropertyTracker.GRID_SIZE, HarvestPropertyTracker.GRID_SIZE },  -- NE
        { -HarvestPropertyTracker.GRID_SIZE, HarvestPropertyTracker.GRID_SIZE }, -- NW
        { HarvestPropertyTracker.GRID_SIZE, -HarvestPropertyTracker.GRID_SIZE }, -- SE
        { -HarvestPropertyTracker.GRID_SIZE, -HarvestPropertyTracker.GRID_SIZE } -- SW
    }

    for _, offset in ipairs(offsets) do
        local adjX = gridX + offset[1]
        local adjZ = gridZ + offset[2]

        local key = self:getGridKey(adjX, adjZ, fillType)
        local pile = storage[key]

        if pile and pile.properties and pile.properties.moisture then
            table.insert(adjacentCells, {
                gridX = adjX,
                gridZ = adjZ,
                properties = pile.properties
            })
        end
    end

    return adjacentCells
end

---
-- Update moisture levels for all grass piles
-- @param moistureDelta: Amount to change moisture (can be positive or negative)
---
function HarvestPropertyTracker:updateGrassMoisture(moistureDelta)
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
    local grassFillType = FillType.GRASS_WINDROW
    local hayFillType = g_fillTypeManager:getFillTypeIndexByName("DRYGRASS_WINDROW")
    local checkRadius = HarvestPropertyTracker.GRID_SIZE / 2

    for gridKey, _ in pairs(self.hayCells) do
        local gridX, gridZ = gridKey:match("([^_]+)_([^_]+)")
        gridX = tonumber(gridX)
        gridZ = tonumber(gridZ)

        -- Check if there's grass in this hay cell
        local grassVolume = DensityMapHeightUtil.getFillLevelAtArea(
            grassFillType,
            gridX - checkRadius, gridZ - checkRadius,
            gridX + checkRadius, gridZ - checkRadius,
            gridX - checkRadius, gridZ + checkRadius
        )

        if grassVolume > 0 then
            print(string.format("[UPDATE] HAY CELL (%d,%d) forcing %.1fL grass to hay", gridX, gridZ, grassVolume))

            local halfSize = HarvestPropertyTracker.GRID_SIZE / 2
            local buffer = halfSize * 0.2
            local sx = gridX - halfSize - buffer
            local sz = gridZ - halfSize - buffer
            local wx = gridX + halfSize + buffer
            local wz = gridZ - halfSize - buffer
            local hx = gridX - halfSize - buffer
            local hz = gridZ + halfSize + buffer

            DensityMapHeightUtil.changeFillTypeAtArea(sx, sz, wx, wz, hx, hz, grassFillType, hayFillType)

            -- Clean up any tracked grass pile in this cell
            local key = self:getGridKey(gridX, gridZ, grassFillType)
            if self.grassPiles[key] then
                self.grassPiles[key] = nil
            end

            -- Check for remaining content and cleanup
            self:checkPileHasContent(gridX, gridZ, hayFillType)
        end
    end

    -- Process tedded cells that don't have piles yet (newly dropped grass from tedder)
    local moistureSystem = g_currentMission.MoistureSystem

    for gridKey, _ in pairs(teddedCellsThisCycle) do
        local gridX, gridZ = gridKey:match("([^_]+)_([^_]+)")
        gridX = tonumber(gridX)
        gridZ = tonumber(gridZ)

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
                    print(string.format("[UPDATE] Cell (%d,%d) NEW TEDDED GRASS: %.1fL at pickup %.1f%%",
                        gridX, gridZ, existingVolume, baseMoisture * 100))
                    self.teddedGrassMoisture[gridKey] = nil
                else
                    baseMoisture = moistureSystem:getMoistureAtPosition(gridX, gridZ)
                    print(string.format("[UPDATE] Cell (%d,%d) NEW TEDDED GRASS: %.1fL at field %.1f%%",
                        gridX, gridZ, existingVolume, baseMoisture * 100))
                end

                local teddedMoisture = baseMoisture - g_currentMission.MoistureSystem.settings.teddingMoistureReduction
                teddedMoisture = math.max(HarvestPropertyTracker.MIN_GRASS_MOISTURE,
                    math.min(HarvestPropertyTracker.MAX_GRASS_MOISTURE, teddedMoisture))

                print(string.format("[UPDATE] Cell (%d,%d) -> tedded %.1f%% (reduced by 5%%)",
                    gridX, gridZ, teddedMoisture * 100))

                self.grassPiles[key] = {
                    gridX = gridX,
                    gridZ = gridZ,
                    fillType = grassFillType,
                    properties = {
                        moisture = teddedMoisture
                    }
                }

                g_client:getServerConnection():sendEvent(PilePropertyUpdateEvent.new(
                    key, self.grassPiles[key].properties, grassFillType, gridX, gridZ
                ))

                -- Mark this cell as processed so we don't reduce it again in the second loop
                processedThisCycle[gridKey] = true
                -- Start cooldown to prevent immediate re-tedding
                self.processedTeddedCells[gridKey] = HarvestPropertyTracker.TEDDED_COOLDOWN_CYCLES
            end
        end
    end

    -- Update all grass piles with fixed min/max clamping
    for key, pile in pairs(self.grassPiles) do
        if pile.properties.moisture then
            local totalDelta = moistureDelta

            -- Check if this grid cell was tedded - apply additional reduction
            local gridKey = self:getSimpleGridKey(pile.gridX, pile.gridZ)
            if teddedCellsThisCycle[gridKey] and not processedThisCycle[gridKey] then
                -- Apply tedding reduction
                local oldMoisture = pile.properties.moisture
                totalDelta = totalDelta - g_currentMission.MoistureSystem.settings.teddingMoistureReduction
                print(string.format("[UPDATE] Cell (%d,%d) REDUCTION APPLIED: %.1f%% -> %.1f%%",
                    pile.gridX, pile.gridZ, oldMoisture * 100,
                    (oldMoisture + totalDelta) * 100))

                local newMoisture = pile.properties.moisture + totalDelta
                pile.properties.moisture = math.max(HarvestPropertyTracker.MIN_GRASS_MOISTURE,
                    math.min(HarvestPropertyTracker.MAX_GRASS_MOISTURE, newMoisture))
                g_client:getServerConnection():sendEvent(PilePropertyUpdateEvent.new(
                    key, pile.properties, pile.fillType, pile.gridX, pile.gridZ
                ))

                -- Start cooldown for existing pile that was tedded
                self.processedTeddedCells[gridKey] = HarvestPropertyTracker.TEDDED_COOLDOWN_CYCLES
            else
                -- No tedding, just apply natural moisture change
                local newMoisture = pile.properties.moisture + totalDelta
                pile.properties.moisture = math.max(HarvestPropertyTracker.MIN_GRASS_MOISTURE,
                    math.min(HarvestPropertyTracker.MAX_GRASS_MOISTURE, newMoisture))
                g_client:getServerConnection():sendEvent(PilePropertyUpdateEvent.new(
                    key, pile.properties, pile.fillType, pile.gridX, pile.gridZ
                ))
            end
        end
    end

    -- Decrement cooldown counters for processed tedded cells
    for gridKey, counter in pairs(self.processedTeddedCells) do
        self.processedTeddedCells[gridKey] = counter - 1
        if self.processedTeddedCells[gridKey] <= 0 then
            self.processedTeddedCells[gridKey] = nil
        end
    end

    -- Decrement hay cell counters
    for gridKey, counter in pairs(self.hayCells) do
        self.hayCells[gridKey] = counter - 1
        if self.hayCells[gridKey] <= 0 then
            self.hayCells[gridKey] = nil
        end
    end
end

---
-- Check if pile has content and remove tracking if empty
-- @param gridX, gridZ: Grid coordinates
-- @param fillType: The filltype to check
---
function HarvestPropertyTracker:checkPileHasContent(gridX, gridZ, fillType)
    local checkRadius = HarvestPropertyTracker.GRID_SIZE / 2
    local volume = DensityMapHeightUtil.getFillLevelAtArea(
        fillType,
        gridX - checkRadius, gridZ - checkRadius,
        gridX + checkRadius, gridZ - checkRadius,
        gridX - checkRadius, gridZ + checkRadius
    )

    if volume <= 0 then
        local key = self:getGridKey(gridX, gridZ, fillType)
        local storage = self:isGrassFillType(fillType) and self.grassPiles or self.gridPiles
        if storage[key] then
            storage[key] = nil
            print(string.format("[CLEANUP] Removed empty pile at (%d,%d)", gridX, gridZ))
        end
    end
end

---
-- Get properties for pile at specific position
-- @param x, z: World coordinates
-- @param fillType: The filltype to check
-- @return properties table or nil
---
function HarvestPropertyTracker:getPilePropertiesAtPosition(x, z, fillType)
    local storage = self:isGrassFillType(fillType) and self.grassPiles or self.gridPiles
    local gridX, gridZ = self:getGridPosition(x, z)
    local key = self:getGridKey(gridX, gridZ, fillType)
    local pile = storage[key]

    if pile then
        return pile.properties
    end

    return nil
end

---
-- Save/Load functionality
---
function HarvestPropertyTracker:saveToXMLFile(xmlFile, key)
    if not self.isServer then return end

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

    print(string.format("HarvestPropertyTracker: Saved %d crop piles, %d grass piles", cropCount, i))
end

function HarvestPropertyTracker:loadFromXMLFile(xmlFile, key)
    if not self.isServer then return end

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

    local cropCount = loadedCount

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

    print(string.format("HarvestPropertyTracker: Loaded %d crop piles, %d grass piles", cropCount, loadedCount))
end
