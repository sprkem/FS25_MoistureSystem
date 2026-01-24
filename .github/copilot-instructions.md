# FS25 MoistureSystem Mod - Development Guidelines

## Project Overview

This mod tracks moisture levels on fields and dropped crop piles in Farming Simulator 25. Moisture varies by terrain height and affects crop properties when harvested and stored.

## Core Architecture

### Moisture System
- **Location**: `src/main.lua`
- **Global Access**: `g_currentMission.MoistureSystem`
- Tracks field moisture based on terrain height relative to midHeight
- Higher elevation = lower moisture, lower elevation = higher moisture
- Uses `getMoistureAtPosition(x, z)` to get moisture at any coordinate

### Harvest Property Tracker
- **Location**: `src/HarvestPropertyTracker.lua`
- **Global Access**: `g_currentMission.harvestPropertyTracker`
- Tracks custom properties (moisture) on dropped filltype piles
- Uses spatial grid (10m cells) for O(1) lookups
- Automatically merges nearby piles using volume-weighted averaging
- Stores data in separate XML file: `MoistureSystem.xml`

## FS25 Modding Patterns

### Extending Game Functions

**Utils.overwrittenFunction** - Replace a function while preserving original:
```lua
function Extension:originalFunction(superFunc, arg1, arg2)
    -- Your code before
    local result = superFunc(self, arg1, arg2)  -- Call original
    -- Your code after
    return result
end

OriginalClass.originalFunction = Utils.overwrittenFunction(OriginalClass.originalFunction, Extension.originalFunction)
```

**Utils.appendedFunction** - Run code after original function:
```lua
function Extension:originalFunction()
    -- Your additional code runs AFTER original
end

OriginalClass.originalFunction = Utils.appendedFunction(OriginalClass.originalFunction, Extension.originalFunction)
```

**Utils.prependedFunction** - Run code before original function:
```lua
function Extension:originalFunction()
    -- Your additional code runs BEFORE original
end

OriginalClass.originalFunction = Utils.prependedFunction(OriginalClass.originalFunction, Extension.originalFunction)
```

### Save/Load XML Patterns

**Main mod initialization (in loadMap):**
```lua
function MoistureSystem:loadMap()
    g_currentMission.MoistureSystem = self
    
    -- Initialize subsystems
    g_currentMission.harvestPropertyTracker = HarvestPropertyTracker.new()
    
    -- Load from XML directly (NOT via hook)
    self:loadFromXMLFile()
end
```

**Load from separate XML file:**
```lua
function MoistureSystem:loadFromXMLFile()
    if not g_currentMission:getIsServer() then return end
    
    local savegameFolderPath = g_currentMission.missionInfo.savegameDirectory
    if savegameFolderPath == nil then
        savegameFolderPath = ('%ssavegame%d'):format(getUserProfileAppPath(), g_currentMission.missionInfo.savegameIndex)
    end
    savegameFolderPath = savegameFolderPath .. "/"
    
    if fileExists(savegameFolderPath .. MoistureSystem.SaveKey .. ".xml") then
        local xmlFile = loadXMLFile(MoistureSystem.SaveKey, savegameFolderPath .. MoistureSystem.SaveKey .. ".xml")
        
        -- Load subsystems
        g_currentMission.harvestPropertyTracker:loadFromXMLFile(xmlFile, MoistureSystem.SaveKey)
        
        self.didLoadFromXML = true
        delete(xmlFile)
    end
end
```

**Save to separate XML file (hooked via appendedFunction):**
```lua
function MoistureSystem:saveToXmlFile()
    if not g_currentMission:getIsServer() then return end
    
    local savegameFolderPath = g_currentMission.missionInfo.savegameDirectory .. "/"
    if savegameFolderPath == nil then
        savegameFolderPath = ('%ssavegame%d'):format(getUserProfileAppPath(), g_currentMission.missionInfo.savegameIndex .. "/")
    end
    
    local xmlFile = createXMLFile(MoistureSystem.SaveKey, savegameFolderPath .. MoistureSystem.SaveKey .. ".xml", MoistureSystem.SaveKey)
    
    -- Save subsystems
    g_currentMission.harvestPropertyTracker:saveToXMLFile(xmlFile, MoistureSystem.SaveKey)
    
    saveXMLFile(xmlFile)
    delete(xmlFile)
end

FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, MoistureSystem.saveToXmlFile)
```

**Subsystem save method (takes xmlFile and key):**
```lua
function HarvestPropertyTracker:saveToXMLFile(xmlFile, key)
    if not self.isServer then return end
    
    setXMLInt(xmlFile, key .. "#nextPileId", self.nextPileId)
    
    local i = 0
    for pileId, pile in pairs(self.trackedPiles) do
        local pileKey = string.format("%s.pile(%d)", key, i)
        
        setXMLInt(xmlFile, pileKey .. "#id", pile.id)
        setXMLFloat(xmlFile, pileKey .. "#moisture", pile.properties.moisture)
        -- ... more properties
        
        i = i + 1
    end
end
```

**Subsystem load method (takes xmlFile and key):**
```lua
function HarvestPropertyTracker:loadFromXMLFile(xmlFile, key)
    if not self.isServer then return end
    
    self.nextPileId = getXMLInt(xmlFile, key .. "#nextPileId") or 1
    
    local i = 0
    while true do
        local pileKey = string.format("%s.pile(%d)", key, i)
        
        if not hasXMLProperty(xmlFile, pileKey) then
            break
        end
        
        local pile = {
            id = getXMLInt(xmlFile, pileKey .. "#id"),
            properties = {
                moisture = getXMLFloat(xmlFile, pileKey .. "#moisture")
            }
        }
        
        self.trackedPiles[pile.id] = pile
        i = i + 1
    end
end
```

### XML Functions Reference

**File Operations:**
- `loadXMLFile(name, path)` - Load XML file, returns xmlFile handle
- `createXMLFile(name, path, rootKey)` - Create new XML file
- `saveXMLFile(xmlFile)` - Write XML file to disk
- `delete(xmlFile)` - Close XML file handle
- `fileExists(path)` - Check if file exists

**Reading:**
- `getXMLString(xmlFile, key)` - Read string value
- `getXMLInt(xmlFile, key)` - Read integer value
- `getXMLFloat(xmlFile, key)` - Read float value
- `getXMLBool(xmlFile, key)` - Read boolean value
- `hasXMLProperty(xmlFile, key)` - Check if property exists

**Writing:**
- `setXMLString(xmlFile, key, value)` - Write string value
- `setXMLInt(xmlFile, key, value)` - Write integer value
- `setXMLFloat(xmlFile, key, value)` - Write float value
- `setXMLBool(xmlFile, key, value)` - Write boolean value

**Key Format:**
- Use `#` for attributes: `"ModName.pile(0)#moisture"`
- Use `()` for indexed arrays: `"ModName.pile(0)"`
- Use `.` for nested elements: `"ModName.subsystem.data"`

## Key Game Systems

### Density Map System
- Stores only filltype index and height
- No support for custom per-pile properties
- Located at world coordinates, managed by `DensityMapHeightUtil`

### Terrain & Coordinates
- `getTerrainHeightAtWorldPos(g_terrainNode, x, y, z)` - Get terrain height
- `getWorldTranslation(node)` - Get node's world coordinates (returns x, y, z)

### FillType System
- `g_fillTypeManager:getFillTypeNameByIndex(fillType)` - Get name from index
- `g_fillTypeManager:getFillTypeIndexByName(name)` - Get index from name

### Mission Timing
- `g_currentMission.time` - Current mission time in milliseconds
- `g_currentMission.environment.currentPeriod` - Current time period
- `MessageType.PERIOD_CHANGED` - Event when period changes

## Important Limitations

### Game Engine
1. **No native filltype properties** - Cannot store moisture directly on density map
2. **Area tracking required** - Must maintain parallel data structure
3. **Approximate coordinates** - Pile positions are simplified rectangles
4. **No partial pickup detection** - Can't easily track when player picks up part of a pile

### Area Tracking System
1. **Not pixel-perfect** - Uses approximate rectangular areas
2. **Pile splitting** - If pile splits, both parts inherit same properties
3. **Memory usage** - Each tracked pile uses ~500 bytes
4. **Max pile limit** - Set to 500 piles to prevent memory issues

## Code Style Conventions

### Naming
- **Classes**: PascalCase (e.g., `HarvestPropertyTracker`)
- **Functions**: camelCase (e.g., `getMoistureAtPosition`)
- **Constants**: UPPER_SNAKE_CASE (e.g., `MAX_TRACKED_PILES`)
- **Private methods**: Use `:` prefix (e.g., `self:addToSpatialGrid()`)

### Structure
- Use `Class()` for class definitions with metatables
- Always check `self.isServer` for server-only operations
- Return early for invalid states
- Use guard clauses to reduce nesting

### Comments
- Document public functions with `---` comments
- Include `@param` and `@return` tags
- Explain non-obvious algorithms inline

## Testing Checklist

When implementing new features:
- [ ] Test on server (multiplayer host)
- [ ] Test on client (multiplayer join)
- [ ] Test save/load functionality
- [ ] Test with 100+ tracked items for performance
- [ ] Verify server-only code runs only on server
- [ ] Check for nil values and edge cases

## Reference Files

- `refs/Policy.lua` - Correct XML save/load patterns
- `refs/RedTape.lua` - Main mod structure with subsystems
- `refs/SprayerExtension.lua` - Vehicle extension pattern example
- `docs/Implementation-Guide-Area-Tracking.md` - Complete implementation guide

## Common Gotchas

1. **Don't create XMLFile objects** - Use `loadXMLFile` and `createXMLFile` directly
2. **Load in loadMap, not via hook** - loadFromXMLFile called directly during initialization
3. **Only save is hooked** - Use `FSBaseMission.saveSavegame` with `Utils.appendedFunction`
4. **Use separate XML files** - Don't try to inject into careerSavegame.xml
5. **Check hasXMLProperty** - Always check existence before reading nested properties
6. **Manual iteration** - Use `while true` with counter for arrays, not `xmlFile:iterate()`
7. **Server-only operations** - Always check `g_currentMission:getIsServer()` before modifying game state
