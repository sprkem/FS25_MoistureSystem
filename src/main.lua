MoistureSystem = {}

MoistureSystem.dir = g_currentModDirectory
MoistureSystem.SaveKey = "MoistureSystem"

function MoistureSystem:loadMap()
    g_currentMission.MoistureSystem = self
    self.didLoadFromXML = false
    self.midHeight = 0
    self.currentMoisture = 0
end

function MoistureSystem:getMoistureAtPosition(x, z)
    local height = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)

    -- At midHeight, return currentMoisture
    -- Higher elevation = lower moisture, lower elevation = higher moisture
    local heightRange = self.maxHeight - self.minHeight
    if heightRange > 0 then
        -- Calculate proportional difference from midHeight (-1 to +1 range)
        local heightDiff = height - self.midHeight
        local heightFactor = heightDiff / (heightRange / 2)

        -- Adjust moisture: higher elevation reduces moisture, lower increases it
        local moistureLevel = self.currentMoisture - (heightFactor * 0.2)
        return math.max(0, math.min(1, moistureLevel))
    else
        return self.currentMoisture
    end
end

function MoistureSystem:firstLoad()
    self:findMidHeight()
    -- TODO = init the moisture level based on current period
    self.currentMoisture = 1
end

function MoistureSystem:findMidHeight()
    local minHeight = math.huge
    local maxHeight = -math.huge
    local count = 0
    for _, farmland in pairs(g_farmlandManager.farmlands) do
        if farmland.showOnFarmlandsScreen and farmland.field ~= nil then
            local field = farmland.field
            local x, z = field:getCenterOfFieldWorldPosition()
            local height = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
            minHeight = math.min(minHeight, height)
            maxHeight = math.max(maxHeight, height)
            count = count + 1
        end
    end
    if count > 0 then
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.midHeight = (minHeight + maxHeight) / 2
    else
        self.minHeight = 0
        self.maxHeight = 0
        self.midHeight = 0
    end
end

function MoistureSystem:onStartMission()
    local ms = g_currentMission.MoistureSystem

    if g_currentMission:getIsServer() then
        -- Initialize mod on new game
        if not ms.didLoadFromXML then
            ms:firstLoad()
        end
    end
end

FSBaseMission.onStartMission = Utils.prependedFunction(FSBaseMission.onStartMission, MoistureSystem.onStartMission)
addModEventListener(MoistureSystem)
