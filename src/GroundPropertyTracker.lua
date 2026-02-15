GroundPropertyTracker = {}
local GroundPropertyTracker_mt = Class(GroundPropertyTracker)

GroundPropertyTracker.GRID_SIZE = 2
GroundPropertyTracker.MIN_GRASS_MOISTURE = 0.05 -- 5% minimum moisture for grass
GroundPropertyTracker.MAX_GRASS_MOISTURE = 0.40 -- 40% maximum moisture for grass
GroundPropertyTracker.MIN_HAY_MOISTURE = 0.04   -- 4% minimum moisture for hay
GroundPropertyTracker.DRY_THRESHOLD = 0.07      -- 7% moisture converts grass to hay / hay to grass

GroundPropertyTracker.TEDDED_COOLDOWN_CYCLES = 10
GroundPropertyTracker.DELAYED_PROCESSING_CYCLES = 2

-- Rain exposure rotting system constants (similar to BaleRottingSystem)
GroundPropertyTracker.SLOW_ROT_EXPOSURE_TIME = 30 * 60 * 1000   -- 30 minutes in milliseconds
GroundPropertyTracker.NORMAL_ROT_EXPOSURE_TIME = 50 * 60 * 1000 -- 50 minutes in milliseconds
GroundPropertyTracker.DRYING_DECAY_RATE = 0.375                 -- Decay rate when dry
GroundPropertyTracker.ROT_REMOVAL_THRESHOLD = 10.0              -- Remove 10 liters when threshold reached
GroundPropertyTracker.ROT_ACCUMULATION_MIN = 0.2                -- Minimum liters per update cycle
GroundPropertyTracker.ROT_ACCUMULATION_MAX = 0.5                -- Maximum liters per update cycle

function GroundPropertyTracker.new()
    local self = setmetatable({}, GroundPropertyTracker_mt)

    self.mission = g_currentMission
    self.isServer = self.mission:getIsServer()
    self.loadedGridSize = nil

    -- Main storage: grid-based piles indexed by "gridX_gridZ_fillType"
    self.gridPiles = {}

    -- Separate storage for grass piles
    self.grassPiles = {}

    -- Separate storage for hay piles
    self.hayPiles = {}

    -- Separate storage for straw piles
    self.strawPiles = {}

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

    -- Track cells that are designated as "grass cells" (recently converted back to grass from hay)
    -- Value is number of update cycles remaining
    self.grassCells = {}

    -- Track moisture of grass being moved by tedder
    -- Key: "gridX_gridZ", Value: moisture value
    self.teddedGrassMoisture = {}

    -- Track grass rotting accumulators
    -- Key: "gridX_gridZ_fillType", Value: accumulated liters waiting for removal
    self.grassRotAccumulators = {}

    -- Track straw rotting accumulators
    -- Key: "gridX_gridZ_fillType", Value: accumulated liters waiting for removal
    self.strawRotAccumulators = {}

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
    self.hayPiles = {}
    self.strawPiles = {}
    self.grassRotAccumulators = {}
    self.strawRotAccumulators = {}
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
    local storage
    if moistureSystem:isGrassOnGroundFillType(fillType) then
        storage = self.grassPiles
    elseif moistureSystem:isStrawFillType(fillType) then
        storage = self.strawPiles
    else
        storage = self.gridPiles
    end

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
    local moistureSystem = g_currentMission.MoistureSystem
    local storage
    if moistureSystem:isGrassOnGroundFillType(fillType) then
        storage = self.grassPiles
    elseif moistureSystem:isStrawFillType(fillType) then
        storage = self.strawPiles
    else
        storage = self.gridPiles
    end
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
        -- Get the moisture from the grass pile to transfer to hay
        local grassKey = self:getGridKey(gridX, gridZ, grassFillType)
        local grassMoisture = nil
        if self.grassPiles[grassKey] and self.grassPiles[grassKey].properties.moisture then
            grassMoisture = self.grassPiles[grassKey].properties.moisture
        end

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

        -- Create hay pile with grass's moisture
        if grassMoisture then
            local hayKey = self:getGridKey(gridX, gridZ, hayFillType)
            self.hayPiles[hayKey] = {
                gridX = gridX,
                gridZ = gridZ,
                fillType = hayFillType,
                properties = {
                    moisture = grassMoisture
                }
            }

            -- Sync to clients
            g_client:getServerConnection():sendEvent(PilePropertyUpdateEvent.new(
                hayKey, self.hayPiles[hayKey].properties, hayFillType, gridX, gridZ
            ))
        end

        -- Check for remaining grass content and cleanup
        self:checkPileHasContent(gridX, gridZ, grassFillType)
    end
end

---
-- Convert hay to grass in a specific cell if hay is present
-- @param gridX, gridZ: Grid coordinates
-- @param hayFillType: The hay fillType index
-- @param grassFillType: The grass fillType index
---
function GroundPropertyTracker:convertHayToGrassInCell(gridX, gridZ, hayFillType, grassFillType)
    local checkRadius = GroundPropertyTracker.GRID_SIZE / 2

    -- Check if there's hay in this cell
    local hayVolume = DensityMapHeightUtil.getFillLevelAtArea(
        hayFillType,
        gridX - checkRadius, gridZ - checkRadius,
        gridX + checkRadius, gridZ - checkRadius,
        gridX - checkRadius, gridZ + checkRadius
    )

    if hayVolume > 0 then
        -- Get the moisture from the hay pile to transfer to grass
        local hayKey = self:getGridKey(gridX, gridZ, hayFillType)
        local hayMoisture = nil
        if self.hayPiles[hayKey] and self.hayPiles[hayKey].properties.moisture then
            hayMoisture = self.hayPiles[hayKey].properties.moisture
        end

        -- Convert hay to grass with buffer
        local halfSize = GroundPropertyTracker.GRID_SIZE / 2
        local buffer = halfSize * 0.2
        local sx = gridX - halfSize - buffer
        local sz = gridZ - halfSize - buffer
        local wx = gridX + halfSize + buffer
        local wz = gridZ - halfSize - buffer
        local hx = gridX - halfSize - buffer
        local hz = gridZ + halfSize + buffer

        DensityMapHeightUtil.changeFillTypeAtArea(sx, sz, wx, wz, hx, hz, hayFillType, grassFillType)

        -- Create grass pile with hay's moisture
        if hayMoisture then
            local grassKey = self:getGridKey(gridX, gridZ, grassFillType)
            self.grassPiles[grassKey] = {
                gridX = gridX,
                gridZ = gridZ,
                fillType = grassFillType,
                properties = {
                    moisture = hayMoisture
                }
            }

            -- Sync to clients
            g_client:getServerConnection():sendEvent(PilePropertyUpdateEvent.new(
                grassKey, self.grassPiles[grassKey].properties, grassFillType, gridX, gridZ
            ))
        end

        -- Check for remaining hay content and cleanup
        self:checkPileHasContent(gridX, gridZ, hayFillType)
    end
end

---
-- Update moisture levels for all grass piles
-- @param moistureDelta: Amount to change moisture (can be positive or negative)
-- @param dt: Delta time in milliseconds since last update
---
function GroundPropertyTracker:updateGrassMoisture(moistureDelta, dt)
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
    local converter = g_fillTypeManager:getConverterDataByName("TEDDER")
    for fromFillType, to in pairs(converter) do
        local targetFillType = to.targetFillTypeIndex
        if fromFillType == targetFillType then
            continue
        end

        for gridKey, _ in pairs(self.hayCells) do
            local gridX, gridZ = gridKey:match("([^_]+)_([^_]+)")
            gridX = tonumber(gridX)
            gridZ = tonumber(gridZ)

            self:convertGrassToHayInCell(gridX, gridZ, fromFillType, targetFillType)
        end
    end


    -- for grassTypeName, hayTypeName in pairs(GroundPropertyTracker.GRASS_CONVERSION_MAP) do
    --     local grassFillType = g_fillTypeManager:getFillTypeIndexByName(grassTypeName)
    --     local hayFillType = g_fillTypeManager:getFillTypeIndexByName(hayTypeName)

    --     if grassFillType and hayFillType then
    --         for gridKey, _ in pairs(self.hayCells) do
    --             local gridX, gridZ = gridKey:match("([^_]+)_([^_]+)")
    --             gridX = tonumber(gridX)
    --             gridZ = tonumber(gridZ)

    --             self:convertGrassToHayInCell(gridX, gridZ, grassFillType, hayFillType)
    --         end
    --     end
    -- end

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
        -- for grassTypeName, _ in pairs(GroundPropertyTracker.GRASS_CONVERSION_MAP) do
        local converter = g_fillTypeManager:getConverterDataByName("TEDDER")
        for fromFillType, to in pairs(converter) do
            -- local grassFillType = g_fillTypeManager:getFillTypeIndexByName(grassTypeName)
            local targetFillType = to.targetFillTypeIndex
            if fromFillType == targetFillType then
                continue
            end
            if fromFillType then
                local key = self:getGridKey(gridX, gridZ, fromFillType)

                -- Check if this cell already has a tracked pile
                if not self.grassPiles[key] then
                    -- Check if there's actually grass on the ground at this location
                    local existingVolume = DensityMapHeightUtil.getFillLevelAtArea(
                        fromFillType,
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
                            fillType = fromFillType,
                            properties = {
                                moisture = teddedMoisture
                            }
                        }

                        g_client:getServerConnection():sendEvent(PilePropertyUpdateEvent.new(
                            key, self.grassPiles[key].properties, fromFillType, gridX, gridZ))

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

                -- Start cooldown for existing pile that was tedded
                self.teddedGridCellsCooldown[gridKey] = GroundPropertyTracker.TEDDED_COOLDOWN_CYCLES
            else
                -- No tedding, just apply natural moisture change
                local newMoisture = pile.properties.moisture + totalDelta
                pile.properties.moisture = math.max(GroundPropertyTracker.MIN_GRASS_MOISTURE,
                    math.min(GroundPropertyTracker.MAX_GRASS_MOISTURE, newMoisture))
            end

            -- Check if grass should convert to hay (dry enough)
            if pile.properties.moisture <= GroundPropertyTracker.DRY_THRESHOLD then
                -- Mark cell for grass->hay conversion
                self.hayCells[gridKey] = 10
            end

            -- Sync pile update to clients
            g_client:getServerConnection():sendEvent(PilePropertyUpdateEvent.new(
                key, pile.properties, pile.fillType, pile.gridX, pile.gridZ
            ))
        end
    end

    -- Update rain exposure and process grass rotting
    local weather = g_currentMission.environment.weather
    local isRaining = weather:getRainFallScale() > 0.1
    local updateDelta = dt * g_currentMission:getEffectiveTimeScale()

    for key, pile in pairs(self.grassPiles) do
        -- Initialize exposure tracking if needed
        if not pile.properties.rainExposure then
            pile.properties.rainExposure = 0
        end
        if not pile.properties.peakRainExposure then
            pile.properties.peakRainExposure = 0
        end

        -- Update rain exposure
        if isRaining then
            pile.properties.rainExposure = pile.properties.rainExposure + updateDelta
            -- Track peak exposure
            if pile.properties.rainExposure > pile.properties.peakRainExposure then
                pile.properties.peakRainExposure = pile.properties.rainExposure
            end
        else
            -- Drying: exposure decrements slowly
            pile.properties.rainExposure = math.max(0,
                pile.properties.rainExposure - (updateDelta * GroundPropertyTracker.DRYING_DECAY_RATE))

            -- If we've dried below slow rot threshold and haven't started rotting, reset peak
            if pile.properties.rainExposure < GroundPropertyTracker.SLOW_ROT_EXPOSURE_TIME and
                pile.properties.peakRainExposure < GroundPropertyTracker.SLOW_ROT_EXPOSURE_TIME then
                pile.properties.peakRainExposure = pile.properties.rainExposure
            end
        end

        -- Determine rot level based on peak exposure
        local rotLevel = 0 -- 0 = none, 1 = slow, 2 = normal
        if pile.properties.peakRainExposure >= GroundPropertyTracker.NORMAL_ROT_EXPOSURE_TIME then
            rotLevel = 2
        elseif pile.properties.peakRainExposure >= GroundPropertyTracker.SLOW_ROT_EXPOSURE_TIME then
            rotLevel = 1
        end

        -- Apply rot if threshold reached
        if rotLevel > 0 then
            -- Initialize accumulator if not exists
            if not self.grassRotAccumulators[key] then
                self.grassRotAccumulators[key] = 0
            end

            -- Add randomized accumulation amount based on rot level
            local baseAmount = GroundPropertyTracker.ROT_ACCUMULATION_MIN +
                math.random() * (GroundPropertyTracker.ROT_ACCUMULATION_MAX - GroundPropertyTracker.ROT_ACCUMULATION_MIN)

            -- Scale by rot level (slow = 1x, normal = 2x)
            local scaledAmount = baseAmount * rotLevel
            self.grassRotAccumulators[key] = self.grassRotAccumulators[key] + scaledAmount

            -- Check if threshold reached for removal
            if self.grassRotAccumulators[key] >= GroundPropertyTracker.ROT_REMOVAL_THRESHOLD then
                local removalAmount = GroundPropertyTracker.ROT_REMOVAL_THRESHOLD

                -- Get grid cell corners for removal area
                local gridX = pile.gridX
                local gridZ = pile.gridZ
                local halfSize = GroundPropertyTracker.GRID_SIZE / 2

                if not self:checkPileHasContent(gridX, gridZ, pile.fillType) then
                    -- No material found, cleanup tracker and accumulator
                    self.grassRotAccumulators[key] = nil
                    continue
                end

                -- Define the three corners of the grid cell area
                local sx = gridX - halfSize
                local sz = gridZ - halfSize
                local sy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, sx, 0, sz)

                local wx = gridX + halfSize
                local wz = gridZ - halfSize
                local wy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, wx, 0, wz)

                local hx = gridX - halfSize
                local hz = gridZ + halfSize
                local hy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, hx, 0, hz)

                -- Calculate proper line coordinates for the area (like tedder does)
                local lsx, lsy, lsz, lex, ley, lez, lineRadius = DensityMapHeightUtil.getLineByAreaDimensions(
                    sx, sy, sz, wx, wy, wz, hx, hy, hz, true
                )

                -- Remove grass from density map (negative amount = pickup)
                local removed = DensityMapHeightUtil.tipToGroundAroundLine(
                    nil,            -- object (nil for no object)
                    -removalAmount, -- negative = pickup
                    pile.fillType,  -- grass fillType
                    lsx, lsy, lsz,  -- start position
                    lex, ley, lez,  -- end position
                    2,              -- radius
                    nil,            -- line offset
                    nil,            -- last line offset
                    false,          -- create piles
                    nil             -- function callback
                )

                if removed ~= 0 then
                    self.grassRotAccumulators[key] = 0

                    -- Check if pile still has content, cleanup if empty
                    self:checkPileHasContent(gridX, gridZ, pile.fillType)
                end
            end
        else
            -- Clear accumulator when not rotting
            if self.grassRotAccumulators[key] then
                self.grassRotAccumulators[key] = nil
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
-- Update moisture levels for all hay piles
-- @param moistureDelta: Amount to change moisture (can be positive or negative)
---
function GroundPropertyTracker:updateHayMoisture(moistureDelta)
    if not self.isServer then return end
    if moistureDelta == 0 then return end

    local moistureSystem = g_currentMission.MoistureSystem
    local checkRadius = GroundPropertyTracker.GRID_SIZE / 2

    -- Update all hay piles with minimum clamping only
    for key, pile in pairs(self.hayPiles) do
        if pile.properties.moisture then
            -- Apply natural moisture change
            local newMoisture = pile.properties.moisture + moistureDelta
            pile.properties.moisture = math.max(GroundPropertyTracker.MIN_HAY_MOISTURE, newMoisture)

            local gridKey = self:getSimpleGridKey(pile.gridX, pile.gridZ)

            -- Check if hay should convert back to grass (too wet)
            if pile.properties.moisture > GroundPropertyTracker.DRY_THRESHOLD then
                -- Mark cell for hay->grass conversion
                self.grassCells[gridKey] = 10
            end

            -- Sync pile update to clients
            g_client:getServerConnection():sendEvent(PilePropertyUpdateEvent.new(
                key, pile.properties, pile.fillType, pile.gridX, pile.gridZ
            ))
        end
    end

    -- Process grass cells (hay->grass conversions)
    local converter = g_fillTypeManager:getConverterDataByName("TEDDER")
    for fromFillType, to in pairs(converter) do
        local targetFillType = to.targetFillTypeIndex
        if fromFillType == targetFillType then
            continue
        end

        for gridKey, _ in pairs(self.grassCells) do
            local gridX, gridZ = gridKey:match("([^_]+)_([^_]+)")
            gridX = tonumber(gridX)
            gridZ = tonumber(gridZ)

            self:convertHayToGrassInCell(gridX, gridZ, targetFillType, fromFillType)
        end
    end

    -- Decrement grass cell counters
    for gridKey, counter in pairs(self.grassCells) do
        self.grassCells[gridKey] = counter - 1
        if self.grassCells[gridKey] <= 0 then
            self.grassCells[gridKey] = nil
        end
    end
end

---
-- Update moisture levels for all straw piles
-- Straw rots away when moisture > 15% (similar to grass)
-- @param moistureDelta: Amount to change moisture (can be positive or negative)
-- @param dt: Delta time in milliseconds since last update
---
function GroundPropertyTracker:updateStrawMoisture(moistureDelta, dt)
    if not self.isServer then return end
    if moistureDelta == 0 then return end

    -- Update all straw piles
    for key, pile in pairs(self.strawPiles) do
        if pile.properties.moisture then
            -- Apply natural moisture change (no max clamp, straw can get very wet)
            local newMoisture = pile.properties.moisture + moistureDelta
            pile.properties.moisture = math.max(0, newMoisture)

            -- Sync pile update to clients
            g_client:getServerConnection():sendEvent(PilePropertyUpdateEvent.new(
                key, pile.properties, pile.fillType, pile.gridX, pile.gridZ
            ))
        end
    end

    -- Update rain exposure and process straw rotting
    local weather = g_currentMission.environment.weather
    local isRaining = weather:getRainFallScale() > 0.1
    local updateDelta = dt * g_currentMission:getEffectiveTimeScale()

    for key, pile in pairs(self.strawPiles) do
        -- Initialize exposure tracking if needed
        if not pile.properties.rainExposure then
            pile.properties.rainExposure = 0
        end
        if not pile.properties.peakRainExposure then
            pile.properties.peakRainExposure = 0
        end

        -- Update rain exposure
        if isRaining then
            pile.properties.rainExposure = pile.properties.rainExposure + updateDelta
            -- Track peak exposure
            if pile.properties.rainExposure > pile.properties.peakRainExposure then
                pile.properties.peakRainExposure = pile.properties.rainExposure
            end
        else
            -- Drying: exposure decrements slowly
            pile.properties.rainExposure = math.max(0,
                pile.properties.rainExposure - (updateDelta * GroundPropertyTracker.DRYING_DECAY_RATE))

            -- If we've dried below slow rot threshold and haven't started rotting, reset peak
            if pile.properties.rainExposure < GroundPropertyTracker.SLOW_ROT_EXPOSURE_TIME and
                pile.properties.peakRainExposure < GroundPropertyTracker.SLOW_ROT_EXPOSURE_TIME then
                pile.properties.peakRainExposure = pile.properties.rainExposure
            end
        end

        -- Determine rot level based on peak exposure
        local rotLevel = 0 -- 0 = none, 1 = slow, 2 = normal
        if pile.properties.peakRainExposure >= GroundPropertyTracker.NORMAL_ROT_EXPOSURE_TIME then
            rotLevel = 2
        elseif pile.properties.peakRainExposure >= GroundPropertyTracker.SLOW_ROT_EXPOSURE_TIME then
            rotLevel = 1
        end

        -- Apply rot if threshold reached
        if rotLevel > 0 then
            -- Initialize accumulator if not exists
            if not self.strawRotAccumulators[key] then
                self.strawRotAccumulators[key] = 0
            end

            -- Add randomized accumulation amount based on rot level
            local baseAmount = GroundPropertyTracker.ROT_ACCUMULATION_MIN +
                math.random() * (GroundPropertyTracker.ROT_ACCUMULATION_MAX - GroundPropertyTracker.ROT_ACCUMULATION_MIN)

            -- Scale by rot level (slow = 1x, normal = 2x)
            local scaledAmount = baseAmount * rotLevel
            self.strawRotAccumulators[key] = self.strawRotAccumulators[key] + scaledAmount

            -- Check if threshold reached for removal
            if self.strawRotAccumulators[key] >= GroundPropertyTracker.ROT_REMOVAL_THRESHOLD then
                local removalAmount = GroundPropertyTracker.ROT_REMOVAL_THRESHOLD

                -- Get grid cell corners for removal area
                local gridX = pile.gridX
                local gridZ = pile.gridZ
                local halfSize = GroundPropertyTracker.GRID_SIZE / 2

                local hasContent = self:checkPileHasContent(gridX, gridZ, pile.fillType)
                if not hasContent then
                    self.strawRotAccumulators[key] = nil
                    continue
                end

                -- Define the three corners of the grid cell area
                local sx = gridX - halfSize
                local sz = gridZ - halfSize
                local sy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, sx, 0, sz)

                local wx = gridX + halfSize
                local wz = gridZ - halfSize
                local wy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, wx, 0, wz)

                local hx = gridX - halfSize
                local hz = gridZ + halfSize
                local hy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, hx, 0, hz)

                -- Calculate proper line coordinates for the area (like tedder does)
                local lsx, lsy, lsz, lex, ley, lez, lineRadius = DensityMapHeightUtil.getLineByAreaDimensions(
                    sx, sy, sz, wx, wy, wz, hx, hy, hz, true
                )

                -- Remove straw from density map (negative amount = pickup)
                local removed = DensityMapHeightUtil.tipToGroundAroundLine(
                    nil,            -- object (nil for no object)
                    -removalAmount, -- negative = pickup
                    pile.fillType,  -- straw fillType
                    lsx, lsy, lsz,  -- start position
                    lex, ley, lez,  -- end position
                    2,              -- radius
                    nil,            -- line offset
                    nil,            -- last line offset
                    false,          -- create piles
                    nil             -- function callback
                )

                if removed ~= 0 then
                    -- Reset accumulator after removal
                    self.strawRotAccumulators[key] = 0

                    -- Check if pile still has content, cleanup if empty
                    self:checkPileHasContent(gridX, gridZ, pile.fillType)
                end
            end
        else
            -- Clear accumulator when not rotting
            if self.strawRotAccumulators[key] then
                self.strawRotAccumulators[key] = nil
            end
        end
    end
end

---
-- Check if pile has content and remove tracking if empty
-- @param gridX, gridZ: Grid coordinates
-- @param fillType: The filltype to check
-- @return boolean: true if pile still has content, false if empty/removed
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
        local storage
        if moistureSystem:isGrassOnGroundFillType(fillType) then
            storage = self.grassPiles
        elseif moistureSystem:isHayFillType(fillType) then
            storage = self.hayPiles
        elseif moistureSystem:isStrawFillType(fillType) then
            storage = self.strawPiles
        else
            storage = self.gridPiles
        end
        if storage[key] then
            storage[key] = nil
            -- print(string.format("[CLEANUP] Removed empty pile at (%d,%d)", gridX, gridZ))
        end
        return false
    end

    return true
end

---
-- Get properties for pile at specific position
-- @param x, z: World coordinates
-- @param fillType: The filltype to check
-- @return properties table or nil
---
function GroundPropertyTracker:getPilePropertiesAtPosition(x, z, fillType)
    local moistureSystem = g_currentMission.MoistureSystem
    local storage
    if moistureSystem:isGrassOnGroundFillType(fillType) then
        storage = self.grassPiles
    elseif moistureSystem:isHayFillType(fillType) then
        storage = self.hayPiles
    elseif moistureSystem:isStrawFillType(fillType) then
        storage = self.strawPiles
    else
        storage = self.gridPiles
    end

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

    for key, pile in pairs(self.hayPiles) do
        table.insert(oldPiles, {
            gridX = pile.gridX,
            gridZ = pile.gridZ,
            fillType = pile.fillType,
            properties = pile.properties,
            isHay = true
        })
    end

    for key, pile in pairs(self.strawPiles) do
        table.insert(oldPiles, {
            gridX = pile.gridX,
            gridZ = pile.gridZ,
            fillType = pile.fillType,
            properties = pile.properties,
            isStraw = true
        })
    end

    -- Clear existing storage
    self.gridPiles = {}
    self.grassPiles = {}
    self.hayPiles = {}
    self.strawPiles = {}

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
                            isHay = oldPile.isHay,
                            isStraw = oldPile.isStraw,
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
        local storage
        if cell.isGrass then
            storage = self.grassPiles
        elseif cell.isHay then
            storage = self.hayPiles
        elseif cell.isStraw then
            storage = self.strawPiles
        else
            storage = self.gridPiles
        end

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
end

function GroundPropertyTracker:saveToXMLFile(xmlFile, key)
    if not self.isServer then return end

    setXMLInt(xmlFile, key .. "#gridSize", GroundPropertyTracker.GRID_SIZE)

    local i = 0
    -- Save crop piles (optimized format)
    for gridKey, pile in pairs(self.gridPiles) do
        local pileKey = string.format("%s.cropPiles.p(%d)", key, i)

        setXMLInt(xmlFile, pileKey .. "#f", pile.fillType)
        setXMLInt(xmlFile, pileKey .. "#x", math.floor(pile.gridX))
        setXMLInt(xmlFile, pileKey .. "#z", math.floor(pile.gridZ))

        -- Save moisture with 3 decimal precision
        if pile.properties.moisture then
            local roundedMoisture = math.floor(pile.properties.moisture * 1000 + 0.5) / 1000
            setXMLFloat(xmlFile, pileKey .. "#m", roundedMoisture)
        end

        i = i + 1
    end

    local cropCount = i

    -- Save grass piles (optimized format)
    i = 0
    for gridKey, pile in pairs(self.grassPiles) do
        local pileKey = string.format("%s.grassPiles.p(%d)", key, i)

        setXMLInt(xmlFile, pileKey .. "#f", pile.fillType)
        setXMLInt(xmlFile, pileKey .. "#x", math.floor(pile.gridX))
        setXMLInt(xmlFile, pileKey .. "#z", math.floor(pile.gridZ))

        -- Save moisture with 3 decimal precision
        if pile.properties.moisture then
            local roundedMoisture = math.floor(pile.properties.moisture * 1000 + 0.5) / 1000
            setXMLFloat(xmlFile, pileKey .. "#m", roundedMoisture)
        end

        i = i + 1
    end

    -- Save hay piles (optimized format)
    i = 0
    for gridKey, pile in pairs(self.hayPiles) do
        local pileKey = string.format("%s.hayPiles.p(%d)", key, i)

        setXMLInt(xmlFile, pileKey .. "#f", pile.fillType)
        setXMLInt(xmlFile, pileKey .. "#x", math.floor(pile.gridX))
        setXMLInt(xmlFile, pileKey .. "#z", math.floor(pile.gridZ))

        -- Save moisture with 3 decimal precision
        if pile.properties.moisture then
            local roundedMoisture = math.floor(pile.properties.moisture * 1000 + 0.5) / 1000
            setXMLFloat(xmlFile, pileKey .. "#m", roundedMoisture)
        end

        i = i + 1
    end

    -- Save straw piles (optimized format)
    i = 0
    for gridKey, pile in pairs(self.strawPiles) do
        local pileKey = string.format("%s.strawPiles.p(%d)", key, i)

        setXMLInt(xmlFile, pileKey .. "#f", pile.fillType)
        setXMLInt(xmlFile, pileKey .. "#x", math.floor(pile.gridX))
        setXMLInt(xmlFile, pileKey .. "#z", math.floor(pile.gridZ))

        -- Save moisture with 3 decimal precision
        if pile.properties.moisture then
            local roundedMoisture = math.floor(pile.properties.moisture * 1000 + 0.5) / 1000
            setXMLFloat(xmlFile, pileKey .. "#m", roundedMoisture)
        end

        i = i + 1
    end
end

---
-- Load pile data from old format (backward compatibility - can be removed in future)
-- @param xmlFile: XML file handle
-- @param pileKey: XML key for pile
-- @return fillType, gridX, gridZ, moisture (or nil if not found)
---
function GroundPropertyTracker:loadPileLegacyFormat(xmlFile, pileKey)
    if not hasXMLProperty(xmlFile, pileKey) then
        return nil
    end

    local fillType = getXMLInt(xmlFile, pileKey .. "#fillType")
    local gridX = getXMLFloat(xmlFile, pileKey .. "#gridX")
    local gridZ = getXMLFloat(xmlFile, pileKey .. "#gridZ")
    local moisture = getXMLFloat(xmlFile, pileKey .. "#moisture")

    return fillType, gridX, gridZ, moisture
end

function GroundPropertyTracker:loadFromXMLFile(xmlFile, key)
    if not self.isServer then return end

    self.loadedGridSize = getXMLInt(xmlFile, key .. "#gridSize") or 5

    local i = 0
    local loadedCount = 0

    -- Load crop piles (try new format first, fallback to legacy)
    while true do
        local pileKey = string.format("%s.cropPiles.p(%d)", key, i)
        local fillType, gridX, gridZ, moisture

        -- Try new optimized format
        if hasXMLProperty(xmlFile, pileKey) then
            fillType = getXMLInt(xmlFile, pileKey .. "#f")
            gridX = getXMLInt(xmlFile, pileKey .. "#x")
            gridZ = getXMLInt(xmlFile, pileKey .. "#z")
            moisture = getXMLFloat(xmlFile, pileKey .. "#m")
        else
            -- Try legacy format for backward compatibility
            local legacyKey = string.format("%s.cropPiles.pile(%d)", key, i)
            fillType, gridX, gridZ, moisture = self:loadPileLegacyFormat(xmlFile, legacyKey)
            if fillType == nil then
                break
            end
        end

        local pile = {
            fillType = fillType,
            fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillType),
            gridX = gridX,
            gridZ = gridZ,
            properties = {}
        }

        if moisture then
            pile.properties.moisture = moisture
        end

        local gridKey = self:getGridKey(gridX, gridZ, fillType)
        self.gridPiles[gridKey] = pile
        loadedCount = loadedCount + 1

        i = i + 1
    end

    -- local cropCount = loadedCount

    -- Load grass piles (try new format first, fallback to legacy)
    i = 0
    loadedCount = 0
    while true do
        local pileKey = string.format("%s.grassPiles.p(%d)", key, i)
        local fillType, gridX, gridZ, moisture

        -- Try new optimized format
        if hasXMLProperty(xmlFile, pileKey) then
            fillType = getXMLInt(xmlFile, pileKey .. "#f")
            gridX = getXMLInt(xmlFile, pileKey .. "#x")
            gridZ = getXMLInt(xmlFile, pileKey .. "#z")
            moisture = getXMLFloat(xmlFile, pileKey .. "#m")
        else
            -- Try legacy format for backward compatibility
            local legacyKey = string.format("%s.grassPiles.pile(%d)", key, i)
            fillType, gridX, gridZ, moisture = self:loadPileLegacyFormat(xmlFile, legacyKey)
            if fillType == nil then
                break
            end
        end

        local pile = {
            fillType = fillType,
            fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillType),
            gridX = gridX,
            gridZ = gridZ,
            properties = {}
        }

        if moisture then
            pile.properties.moisture = moisture
        end

        local gridKey = self:getGridKey(gridX, gridZ, fillType)
        self.grassPiles[gridKey] = pile
        loadedCount = loadedCount + 1

        i = i + 1
    end

    -- Load hay piles (try new format first, fallback to legacy)
    i = 0
    loadedCount = 0
    while true do
        local pileKey = string.format("%s.hayPiles.p(%d)", key, i)
        local fillType, gridX, gridZ, moisture

        -- Try new optimized format
        if hasXMLProperty(xmlFile, pileKey) then
            fillType = getXMLInt(xmlFile, pileKey .. "#f")
            gridX = getXMLInt(xmlFile, pileKey .. "#x")
            gridZ = getXMLInt(xmlFile, pileKey .. "#z")
            moisture = getXMLFloat(xmlFile, pileKey .. "#m")
        else
            -- Try legacy format for backward compatibility
            local legacyKey = string.format("%s.hayPiles.pile(%d)", key, i)
            fillType, gridX, gridZ, moisture = self:loadPileLegacyFormat(xmlFile, legacyKey)
            if fillType == nil then
                break
            end
        end

        local pile = {
            fillType = fillType,
            fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillType),
            gridX = gridX,
            gridZ = gridZ,
            properties = {}
        }

        if moisture then
            pile.properties.moisture = moisture
        end

        local gridKey = self:getGridKey(gridX, gridZ, fillType)
        self.hayPiles[gridKey] = pile
        loadedCount = loadedCount + 1

        i = i + 1
    end

    -- Load straw piles (try new format first, fallback to legacy)
    i = 0
    loadedCount = 0
    while true do
        local pileKey = string.format("%s.strawPiles.p(%d)", key, i)
        local fillType, gridX, gridZ, moisture

        -- Try new optimized format
        if hasXMLProperty(xmlFile, pileKey) then
            fillType = getXMLInt(xmlFile, pileKey .. "#f")
            gridX = getXMLInt(xmlFile, pileKey .. "#x")
            gridZ = getXMLInt(xmlFile, pileKey .. "#z")
            moisture = getXMLFloat(xmlFile, pileKey .. "#m")
        else
            -- Try legacy format for backward compatibility
            local legacyKey = string.format("%s.strawPiles.pile(%d)", key, i)
            fillType, gridX, gridZ, moisture = self:loadPileLegacyFormat(xmlFile, legacyKey)
            if fillType == nil then
                break
            end
        end

        local pile = {
            fillType = fillType,
            fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillType),
            gridX = gridX,
            gridZ = gridZ,
            properties = {}
        }

        if moisture then
            pile.properties.moisture = moisture
        end

        local gridKey = self:getGridKey(gridX, gridZ, fillType)
        self.strawPiles[gridKey] = pile
        loadedCount = loadedCount + 1

        i = i + 1
    end
end
