HarvestPropertyTracker = {}
local HarvestPropertyTracker_mt = Class(HarvestPropertyTracker)

-- Configuration
HarvestPropertyTracker.GRID_SIZE = 10  -- 10m grid cells for consistent world grid

function HarvestPropertyTracker.new()
    local self = setmetatable({}, HarvestPropertyTracker_mt)
    
    self.mission = g_currentMission
    self.isServer = self.mission:getIsServer()
    
    -- Main storage: grid-based piles indexed by "gridX_gridZ_fillType"
    self.gridPiles = {}
    
    return self
end

---
-- Get grid-aligned position for a world coordinate
-- @param x, z: World coordinates
-- @return gridX, gridZ: Grid-aligned center coordinates
---
function HarvestPropertyTracker:getGridPosition(x, z)
    local gridX = math.floor(x / HarvestPropertyTracker.GRID_SIZE) * HarvestPropertyTracker.GRID_SIZE + HarvestPropertyTracker.GRID_SIZE / 2
    local gridZ = math.floor(z / HarvestPropertyTracker.GRID_SIZE) * HarvestPropertyTracker.GRID_SIZE + HarvestPropertyTracker.GRID_SIZE / 2
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

function HarvestPropertyTracker:delete()
    self.gridPiles = {}
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
            local gridX, gridZ = self:getGridPosition(gx + HarvestPropertyTracker.GRID_SIZE / 2, gz + HarvestPropertyTracker.GRID_SIZE / 2)
            local overlapArea = self:calculateCellOverlap(gridX, gridZ, minX, maxX, minZ, maxZ)
            
            if overlapArea > 0 then
                table.insert(cells, {gridX = gridX, gridZ = gridZ, overlapArea = overlapArea})
                totalOverlapArea = totalOverlapArea + overlapArea
            end
        end
    end
    
    return cells, totalOverlapArea
end

---
-- Add a new dropped pile to tracking
-- Distributes volume proportionally across grid cells based on overlap area
-- @param sx, sz, wx, wz, hx, hz: Area coordinates (start, width, height corners)
-- @param fillType: The filltype index being dropped
-- @param volume: Volume in liters of the dropped material
-- @param properties: Table of properties {moisture=0.18}
---
function HarvestPropertyTracker:addPile(sx, sz, wx, wz, hx, hz, fillType, volume, properties)
    if not self.isServer then return end
    
    -- Get all grid cells this drop affects with their overlap areas
    local affectedCells, totalOverlapArea = self:getAffectedGridCells(sx, sz, wx, wz, hx, hz)
    
    if #affectedCells == 0 or totalOverlapArea == 0 then return end
    
    -- Distribute volume proportionally based on overlap area
    for _, cell in ipairs(affectedCells) do
        local proportion = cell.overlapArea / totalOverlapArea
        local volumeForCell = volume * proportion
        
        local key = self:getGridKey(cell.gridX, cell.gridZ, fillType)
        local pile = self.gridPiles[key]
        
        if pile then
            -- Update existing pile with volume-weighted averaging
            local totalVolume = pile.volume + volumeForCell
            
            for propKey, propValue in pairs(properties or {}) do
                if pile.properties[propKey] then
                    -- Volume-weighted average
                    pile.properties[propKey] = (pile.properties[propKey] * pile.volume + propValue * volumeForCell) / totalVolume
                else
                    pile.properties[propKey] = propValue
                end
            end
            
            pile.volume = totalVolume
            pile.lastUpdateTime = self.mission.time
        else
            -- Create new pile at this grid cell
            self.gridPiles[key] = {
                gridX = cell.gridX,
                gridZ = cell.gridZ,
                fillType = fillType,
                fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillType),
                volume = volumeForCell,
                properties = properties or {},
                createdTime = self.mission.time,
                lastUpdateTime = self.mission.time
            }
        end
    end
end

---
-- Remove or reduce a pile when material is picked up
-- @param sx, sz, wx, wz, hx, hz: Area where material was removed
-- @param fillType: The filltype being picked up
---
function HarvestPropertyTracker:removePileAtArea(sx, sz, wx, wz, hx, hz, fillType)
    if not self.isServer then return end
    
    local affectedCells = self:getAffectedGridCells(sx, sz, wx, wz, hx, hz)
    
    for _, cell in ipairs(affectedCells) do
        local key = self:getGridKey(cell.gridX, cell.gridZ, fillType)
        local pile = self.gridPiles[key]
        
        if pile then
            -- Check if actual filltype still exists at this grid location
            local checkX, checkZ = cell.gridX, cell.gridZ
            local checkRadius = HarvestPropertyTracker.GRID_SIZE / 2
            
            local existingFillType = DensityMapHeightUtil.getFillTypeAtArea(
                checkX - checkRadius, checkZ - checkRadius,
                checkX + checkRadius, checkZ - checkRadius,
                checkX - checkRadius, checkZ + checkRadius
            )
            
            if existingFillType ~= fillType then
                -- Pile no longer exists at this grid cell
                self.gridPiles[key] = nil
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
    local gridX, gridZ = self:getGridPosition(x, z)
    local key = self:getGridKey(gridX, gridZ, fillType)
    local pile = self.gridPiles[key]
    
    if pile then
        return pile.properties
    end
    
    return nil
end

---
-- Cleanup old piles that no longer exist
---
function HarvestPropertyTracker:validateTrackedPiles()
    if not self.isServer then return end
    
    local toRemove = {}
    local checkRadius = HarvestPropertyTracker.GRID_SIZE / 2
    
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
    
    if #toRemove > 0 then
        print(string.format("HarvestPropertyTracker: Cleaned up %d invalid piles", #toRemove))
    end
end

---
-- Get properties for pile at specific position
-- @param x, z: World coordinates
-- @param fillType: The filltype to check
-- @return properties table or nil
---
function HarvestPropertyTracker:getPilePropertiesAtPosition(x, z, fillType)
    local gridX, gridZ = self:getGridPosition(x, z)
    local key = self:getGridKey(gridX, gridZ, fillType)
    local pile = self.gridPiles[key]
    
    if pile and pile.volume > 0 then
        return pile.properties
    end
    
    return nil
end

---
-- Remove volume from a pile at position (used when pickup happens)
-- @param x, z: World coordinates of pickup
-- @param fillType: The filltype being picked up
-- @param volumeRemoved: Volume removed in liters
---
function HarvestPropertyTracker:removePileAtPosition(x, z, fillType, volumeRemoved)
    if not self.isServer then return end
    
    local gridX, gridZ = self:getGridPosition(x, z)
    local key = self:getGridKey(gridX, gridZ, fillType)
    local pile = self.gridPiles[key]
    
    if pile then
        pile.volume = pile.volume - volumeRemoved
        
        -- If pile is empty or nearly empty, remove it
        if pile.volume <= 0.1 then
            self.gridPiles[key] = nil
        else
            pile.lastUpdateTime = self.mission.time
        end
    end
end

---
-- Save/Load functionality
---
function HarvestPropertyTracker:saveToXMLFile(xmlFile, key)
    if not self.isServer then return end
    
    local i = 0
    for gridKey, pile in pairs(self.gridPiles) do
        local pileKey = string.format("%s.pile(%d)", key, i)
        
        setXMLInt(xmlFile, pileKey .. "#fillType", pile.fillType)
        setXMLFloat(xmlFile, pileKey .. "#volume", pile.volume)
        setXMLFloat(xmlFile, pileKey .. "#gridX", pile.gridX)
        setXMLFloat(xmlFile, pileKey .. "#gridZ", pile.gridZ)
        setXMLInt(xmlFile, pileKey .. "#createdTime", pile.createdTime)
        setXMLInt(xmlFile, pileKey .. "#lastUpdateTime", pile.lastUpdateTime)
        
        -- Save moisture
        if pile.properties.moisture then
            setXMLFloat(xmlFile, pileKey .. "#moisture", pile.properties.moisture)
        end
        
        i = i + 1
    end
    
    print(string.format("HarvestPropertyTracker: Saved %d piles", i))
end

function HarvestPropertyTracker:loadFromXMLFile(xmlFile, key)
    if not self.isServer then return end
    
    local i = 0
    local loadedCount = 0
    
    while true do
        local pileKey = string.format("%s.pile(%d)", key, i)
        
        if not hasXMLProperty(xmlFile, pileKey) then
            break
        end
        
        local fillType = getXMLInt(xmlFile, pileKey .. "#fillType")
        local gridX = getXMLFloat(xmlFile, pileKey .. "#gridX")
        local gridZ = getXMLFloat(xmlFile, pileKey .. "#gridZ")
        
        local pile = {
            fillType = fillType,
            fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillType),
            volume = getXMLFloat(xmlFile, pileKey .. "#volume"),
            gridX = gridX,
            gridZ = gridZ,
            createdTime = getXMLInt(xmlFile, pileKey .. "#createdTime"),
            lastUpdateTime = getXMLInt(xmlFile, pileKey .. "#lastUpdateTime"),
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
    
    print(string.format("HarvestPropertyTracker: Loaded %d piles", loadedCount))
end

return HarvestPropertyTracker
