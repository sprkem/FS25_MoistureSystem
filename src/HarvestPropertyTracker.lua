HarvestPropertyTracker = {}
local HarvestPropertyTracker_mt = Class(HarvestPropertyTracker)

HarvestPropertyTracker.GRID_SIZE = 10 -- 10m grid cells for consistent world grid

function HarvestPropertyTracker.new()
    local self = setmetatable({}, HarvestPropertyTracker_mt)

    self.mission = g_currentMission
    self.isServer = self.mission:getIsServer()

    -- Main storage: grid-based piles indexed by "gridX_gridZ_fillType"
    self.gridPiles = {}

    -- Separate storage for grass/grass windrow piles
    self.grassPiles = {}

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
-- Check if fillType is grass or grass windrow
-- @param fillType: The filltype index
-- @return true if grass type
---
function HarvestPropertyTracker:isGrassFillType(fillType)
    return fillType == FillType.GRASS or fillType == FillType.GRASS_WINDROW
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

            -- for propKey, propValue in pairs(properties or {}) do
            --     print(string.format("[TRACKER addPile] Grid (%d,%d) %s: CREATE = %.3f (%.1fL)",
            --         cell.gridX, cell.gridZ,
            --         propKey, propValue, volumeForCell))
            -- end
        end
    end
end

---
-- Remove a pile tracking when material is picked up
-- Uses DensityMapHeightUtil to check if material still exists
-- @param sx, sz, wx, wz, hx, hz: Area where material was removed
-- @param fillType: The filltype being picked up
---
-- function HarvestPropertyTracker:removePileAtArea(sx, sz, wx, wz, hx, hz, fillType)
--     if not self.isServer then return end

--     local storage = self:isGrassFillType(fillType) and self.grassPiles or self.gridPiles

--     local affectedCells = self:getAffectedGridCells(sx, sz, wx, wz, hx, hz)

--     for _, cell in ipairs(affectedCells) do
--         local key = self:getGridKey(cell.gridX, cell.gridZ, fillType)
--         local pile = storage[key]

--         if pile then
--             -- Check if actual filltype still exists at this grid location
--             local checkRadius = HarvestPropertyTracker.GRID_SIZE / 2
--             local existingFillType = DensityMapHeightUtil.getFillTypeAtArea(
--                 cell.gridX - checkRadius, cell.gridZ - checkRadius,
--                 cell.gridX + checkRadius, cell.gridZ - checkRadius,
--                 cell.gridX - checkRadius, cell.gridZ + checkRadius
--             )

--             if existingFillType ~= fillType then
--                 -- Pile no longer exists at this grid cell
--                 storage[key] = nil
--             end
--         end
--     end
-- end

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
-- Update moisture levels for all grass piles
-- @param moistureDelta: Amount to change moisture (can be positive or negative)
---
function HarvestPropertyTracker:updateGrassMoisture(moistureDelta)
    if not self.isServer then return end
    if moistureDelta == 0 then return end

    -- Get current month and environment for clamping
    local month = MoistureSystem.periodToMonth(g_currentMission.environment.currentPeriod)
    local environment = g_currentMission.MoistureSystem.settings.environment
    local monthData = MoistureClamp.Environments[environment].Months[month]
    local minMoisture = monthData.Min / 100
    local maxMoisture = monthData.Max / 100

    -- Update all grass piles
    for key, pile in pairs(self.grassPiles) do
        if pile.properties.moisture then
            local newMoisture = pile.properties.moisture + moistureDelta
            pile.properties.moisture = math.max(minMoisture, math.min(maxMoisture, newMoisture))
            g_client:getServerConnection():sendEvent(PilePropertyUpdateEvent.new(
                key, pile.properties, pile.fillType, pile.gridX, pile.gridZ
            ))
        end
    end
end

---
-- Cleanup old piles that no longer exist
---
function HarvestPropertyTracker:validateTrackedPiles()
    if not self.isServer then return end

    local toRemove = {}
    local checkRadius = HarvestPropertyTracker.GRID_SIZE / 2

    -- Validate crop piles
    for key, pile in pairs(self.gridPiles) do
        -- Check if filltype still exists at this grid location
        local existingFillType = DensityMapHeightUtil.getFillTypeAtArea(
            pile.gridX - checkRadius, pile.gridZ - checkRadius,
            pile.gridX + checkRadius, pile.gridZ - checkRadius,
            pile.gridX - checkRadius, pile.gridZ + checkRadius
        )

        if existingFillType ~= pile.fillType then
            table.insert(toRemove, key)
        end
    end

    for _, key in ipairs(toRemove) do
        self.gridPiles[key] = nil
    end

    local cropRemoved = #toRemove

    -- Validate grass piles
    toRemove = {}
    for key, pile in pairs(self.grassPiles) do
        -- Check if filltype still exists at this grid location
        local existingFillType = DensityMapHeightUtil.getFillTypeAtArea(
            pile.gridX - checkRadius, pile.gridZ - checkRadius,
            pile.gridX + checkRadius, pile.gridZ - checkRadius,
            pile.gridX - checkRadius, pile.gridZ + checkRadius
        )

        if existingFillType ~= pile.fillType then
            table.insert(toRemove, key)
        end
    end

    for _, key in ipairs(toRemove) do
        self.grassPiles[key] = nil
    end

    if cropRemoved > 0 or #toRemove > 0 then
        print(string.format("HarvestPropertyTracker: Cleaned up %d crop piles, %d grass piles", cropRemoved, #toRemove))
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
-- Remove pile tracking at position if nothing remains (used when pickup happens)
-- Uses DensityMapHeightUtil to check if filltype still exists at this location
-- @param x, z: World coordinates of pickup
-- @param fillType: The filltype being picked up
---
function HarvestPropertyTracker:checkPileHasContent(x, z, fillType)
    if not self.isServer then return end

    local storage = self:isGrassFillType(fillType) and self.grassPiles or self.gridPiles

    local gridX, gridZ = self:getGridPosition(x, z)
    local key = self:getGridKey(gridX, gridZ, fillType)
    local pile = storage[key]

    if pile then
        -- Check if filltype still exists at this grid location
        local checkRadius = HarvestPropertyTracker.GRID_SIZE / 2
        local existingFillType = DensityMapHeightUtil.getFillTypeAtArea(
            gridX - checkRadius, gridZ - checkRadius,
            gridX + checkRadius, gridZ - checkRadius,
            gridX - checkRadius, gridZ + checkRadius
        )

        if existingFillType ~= fillType then
            -- Pile no longer exists, remove tracking
            storage[key] = nil
        end
    end
end

---
-- Save/Load functionality
---
function HarvestPropertyTracker:saveToXMLFile(xmlFile, key)
    if not self.isServer then return end

    local i = 0
    -- Save crop piles
    for gridKey, pile in pairs(self.gridPiles) do
        local pileKey = string.format("%s.cropPile(%d)", key, i)

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
        local pileKey = string.format("%s.grassPile(%d)", key, i)

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
        local pileKey = string.format("%s.cropPile(%d)", key, i)

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
        local pileKey = string.format("%s.grassPile(%d)", key, i)

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
