PilePropertyUpdateEvent = {}
PilePropertyUpdateEvent_mt = Class(PilePropertyUpdateEvent, Event)

InitEventClass(PilePropertyUpdateEvent, "PilePropertyUpdateEvent")

function PilePropertyUpdateEvent.emptyNew()
    local self = Event.new(PilePropertyUpdateEvent_mt)
    return self
end

function PilePropertyUpdateEvent.new(key, properties, fillTypeIndex, gridX, gridZ)
    local self = PilePropertyUpdateEvent.emptyNew()
    self.key = key
    self.properties = properties or {}
    self.fillTypeIndex = fillTypeIndex
    self.gridX = gridX
    self.gridZ = gridZ
    return self
end

function PilePropertyUpdateEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.key)
    streamWriteInt32(streamId, self.fillTypeIndex)
    streamWriteFloat32(streamId, self.gridX)
    streamWriteFloat32(streamId, self.gridZ)

    -- Write moisture property
    local hasMoisture = self.properties.moisture ~= nil
    streamWriteBool(streamId, hasMoisture)
    if hasMoisture then
        streamWriteFloat32(streamId, self.properties.moisture)
    end
end

function PilePropertyUpdateEvent:readStream(streamId, connection)
    self.key = streamReadString(streamId)
    self.fillTypeIndex = streamReadInt32(streamId)
    self.gridX = streamReadFloat32(streamId)
    self.gridZ = streamReadFloat32(streamId)

    self.properties = {}
    local hasMoisture = streamReadBool(streamId)
    if hasMoisture then
        self.properties.moisture = streamReadFloat32(streamId)
    end

    self:run(connection)
end

function PilePropertyUpdateEvent:run(connection)
    if not connection:getIsServer() then
        g_server:broadcastEvent(PilePropertyUpdateEvent.new(
            self.key, self.properties, self.fillTypeIndex, self.gridX, self.gridZ
        ))
    end

    local isGrass = self.fillTypeIndex == FillType.GRASS_WINDROW or self.fillTypeIndex == FillType.GRASS

    local tracker = g_currentMission.harvestPropertyTracker
    if isGrass and self.properties.moisture and self.properties.moisture <= MSTedderExtension.DRY_THRESHOLD then
        if g_currentMission:getIsServer() then
            -- Calculate area from grid position with 20% buffer to catch grass at edges
            local halfSize = HarvestPropertyTracker.GRID_SIZE / 2
            local buffer = halfSize * 0.2  -- 20% buffer
            local sx = self.gridX - halfSize - buffer
            local sz = self.gridZ - halfSize - buffer
            local wx = self.gridX + halfSize + buffer
            local wz = self.gridZ - halfSize - buffer
            local hx = self.gridX - halfSize - buffer
            local hz = self.gridZ + halfSize + buffer

            local grassFillType = g_fillTypeManager:getFillTypeIndexByName("GRASS_WINDROW")
            local hayFillType = g_fillTypeManager:getFillTypeIndexByName("DRYGRASS_WINDROW")
            -- print(string.format("[HAY CONVERSION] Cell (%d,%d) moisture %.1f%% <= %.1f%% threshold - converting GRASS to HAY (with 20%% buffer)",
            --     self.gridX, self.gridZ, self.properties.moisture * 100, MSTedderExtension.DRY_THRESHOLD * 100))
            DensityMapHeightUtil.changeFillTypeAtArea(sx, sz, wx, wz, hx, hz, grassFillType, hayFillType)
            
            -- Mark this cell as a "hay cell" for 5 seconds (10 cycles at 500ms each)
            local gridKey = tracker:getSimpleGridKey(self.gridX, self.gridZ)
            tracker.hayCells[gridKey] = 10
            
            -- Check and cleanup any remaining grass pile tracking
            tracker:checkPileHasContent(self.gridX, self.gridZ, hayFillType)
            tracker:checkPileHasContent(self.gridX, self.gridZ, self.fillTypeIndex)
        end
    else
        -- Update or create pile on both server and client
        local storage = isGrass and tracker.grassPiles or tracker.gridPiles
        storage[self.key] = {
            properties = self.properties,
            fillType = self.fillTypeIndex,
            gridX = self.gridX,
            gridZ = self.gridZ
        }
    end
end
