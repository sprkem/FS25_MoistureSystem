# FS25 MoistureSystem Mod - Development Guidelines

## Project Overview

This mod tracks moisture levels on fields and dropped crop piles in Farming Simulator 25. Moisture varies by terrain height and affects crop properties when harvested and stored.

## Core Architecture

### Moisture System
- **Location**: `src/main.lua`
- **Global Access**: `g_currentMission.MoistureSystem`
- Tracks field moisture based on terrain height relative to midHeight
- Higher elevation = lower moisture, lower elevation = higher moisture
- Uses `getMoistureAtPosition(x, z)` to get moisture at any coordinate (returns 0-1 scale)
- `currentMoisturePercent` is always stored in 0-1 range (not 0-100 percentage)
- Initializes moisture to 25% above minimum of min/max range for current month/environment
- Uses 500ms update interval (`updateInterval = 500`)
- Dynamic moisture changes based on rainfall, snowfall, temperature, and time of day
- Reduced loss at night (6am-8pm = day, night = 33% loss rate)
- **FillType Checking Methods**:
  - `isGrassOnGroundFillType(fillType)` - Check if fillType is grass/alfalfa/clover using TEDDER converter data
  - `isHayFillType(fillType)` - Check if fillType is converted hay/dry grass (target of TEDDER conversion)
  - `shouldTrackFillType(fillType)` - Check if fillType should be tracked (grass or in CropValueMap)
  - Uses `g_fillTypeManager:getConverterDataByName("TEDDER")` to dynamically detect grass types

### Moisture Settings & Clamp System
- **Location**: `src/MoistureSettings.lua` and `src/data/MoistureClamp.lua`
- **Global Access**: `g_currentMission.MoistureSystem.settings`
- Provides in-game settings menu for environment type (DRY/NORMAL/WET)
- MoistureClamp defines monthly moisture ranges (0-100 scale) for each environment
- Settings sync across multiplayer via `MoistureSettingsEvent`
- Server-only setting with permission-based access control
- Persists in save game XML

#### Adding New Settings
Follow these steps to add a new setting to the mod:

1. **Define constants (if using enums)** - In `MoistureSettings.lua`:
   ```lua
   -- Prefer integer constants over string values for settings with multiple options
   MoistureSettings.SETTING_OPTION_ONE = 1
   MoistureSettings.SETTING_OPTION_TWO = 2
   ```

2. **Add to menuItems array** - In `MoistureSettings.lua`:
   ```lua
   MoistureSettings.menuItems = {
       'environment',
       'existingSetting',
       'newSettingName'  -- Add your setting here
   }
   ```

3. **Define setting configuration** - In `MoistureSettings.lua`:
   ```lua
   MoistureSettings.SETTINGS.newSettingName = {
       ['default'] = 1,  -- Index of default value (1-based)
       ['serverOnly'] = false,  -- true = only server/admin can change, false = client setting
       ['permission'] = 'moistureSettings',  -- Permission required
       ['values'] = { MoistureSettings.SETTING_OPTION_ONE, MoistureSettings.SETTING_OPTION_TWO },
       ['strings'] = {
           g_i18n:getText("setting_moisture_newSettingName_option1"),
           g_i18n:getText("setting_moisture_newSettingName_option2")
       }
   }
   ```

4. **Add localization strings** - In `languages/l10n_en.xml`:
   ```xml
   <!-- Setting label and tooltip -->
   <text name="setting_moisture_newSettingName" text="Setting Display Name"/>
   <text name="setting_moisture_newSettingName_tooltip" text="Description of what the setting does."/>
   
   <!-- Option labels -->
   <text name="setting_moisture_newSettingName_option1" text="Option One"/>
   <text name="setting_moisture_newSettingName_option2" text="Option Two"/>
   ```

5. **Update MoistureSettingsEvent** - In `src/events/MoistureSettingsEvent.lua`:
   ```lua
   -- In new() function:
   function MoistureSettingsEvent.new()
       local self = MoistureSettingsEvent.emptyNew()
       -- ... existing settings ...
       self.newSettingName = g_currentMission.MoistureSystem.settings.newSettingName
       return self
   end
   
   -- In writeStream() function:
   function MoistureSettingsEvent:writeStream(streamId, connection)
       -- ... existing writes ...
       streamWriteInt32(streamId, self.newSettingName)  -- Use appropriate type
   end
   
   -- In readStream() function:
   function MoistureSettingsEvent:readStream(streamId, connection)
       -- ... existing reads ...
       self.newSettingName = streamReadInt32(streamId)  -- Use matching type
       self:run(connection)
   end
   
   -- In run() function:
   function MoistureSettingsEvent:run(connection)
       -- ... existing assignments ...
       g_currentMission.MoistureSystem.settings.newSettingName = self.newSettingName
       -- ... rest of function ...
   end
   ```

6. **Use the setting in code**:
   ```lua
   local settingValue = g_currentMission.MoistureSystem.settings.newSettingName
   if settingValue == MoistureSettings.SETTING_OPTION_TWO then
       -- Do something based on setting
   end
   ```

**Important conventions:**
- Always use integer constants for enum-style settings (not strings)
- Use appropriate stream functions: `streamWriteInt32`/`streamReadInt32` for integers, `streamWriteBool`/`streamReadBool` for booleans, `streamWriteFloat32`/`streamReadFloat32` for floats
- Localization keys follow pattern: `setting_moisture_<settingName>` for labels, `setting_moisture_<settingName>_tooltip` for descriptions
- Default index is 1-based (first option = 1, not 0)
- Settings are stored in `g_currentMission.MoistureSystem.settings` table

### Bale Rotting System
- **Location**: `src/BaleRottingSystem.lua`
- **Global Access**: `g_currentMission.baleRottingSystem`
- Tracks bale exposure to rain with grace period and gradual decay
- Three rot rate tiers based on peak exposure time:
  - Slow rot: After 20 minutes exposure
  - Normal rot: After 40 minutes exposure
  - Fast rot: After 60 minutes exposure
- Bales can dry if exposure < slow rot threshold (20 minutes)
- Once rotting starts, bales cannot dry back
- Exposure time decrements slowly when dry (decay rate: 0.375)
- Sunshine provides drying bonus (1.0-1.25x multiplier)
- Bale status tracked: GETTING_WET, DRYING, ROTTING_SLOWLY, ROTTING, ROTTING_QUICKLY
- Persists exposure and peak exposure in save game

### Ground Property Tracker
- **Location**: `src/GroundPropertyTracker.lua`
- **Global Access**: `g_currentMission.groundPropertyTracker`
- Tracks custom properties (moisture) on dropped filltype piles
- Uses grid-based storage (2m cells) with `"gridX_gridZ_fillType"` keys
- Separate storage for grass piles (`grassPiles`) vs other crops (`gridPiles`)
- Distributes volume proportionally across grid cells based on bounding box overlap
- Automatically merges piles in same grid cell using volume-weighted averaging
- Stores data in separate XML file: `MoistureSystem.xml`
- Grid-aligned coordinates for O(1) lookups without spatial indexing
- Special handling for tedded grass with cooldown system (10 cycles = 5 seconds)
- Automatic hay conversion when grass moisture ≤ 7% (`DRY_THRESHOLD`)
- `hayCells` tracking prevents grass from re-appearing in recently converted cells
- **Grass Rotting System**: Wet grass (>15% moisture) gradually decays using accumulator system
  - Tracks rot accumulators per pile (`grassRotAccumulators`)
  - Random accumulation (0.1-0.3 liters per cycle) when moisture > 15%
  - Removes 10 liters when accumulator threshold reached
  - Uses `DensityMapHeightUtil.tipToGroundAroundLine` with negative amount for removal
  - Automatically cleans up empty piles via `checkPileHasContent`

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

### Network Event Pattern

**CRITICAL: Event sending in FS25**
- **ALWAYS use `g_client:getServerConnection():sendEvent()` to send events from your code**
- **NEVER use `g_server:broadcastEvent()` directly from your mod code**
- Both client AND server code uses `g_client:getServerConnection():sendEvent()` to initiate events
- Inside the event's `run()` method, when server receives from client, it uses `g_server:broadcastEvent()` to relay to all clients
- Do NOT change this pattern - it is correct and used consistently across all events

**Create custom network events for multiplayer sync:**
```lua
EventName = {}
EventName_mt = Class(EventName, Event)

InitEventClass(EventName, "EventName")

function EventName.emptyNew()
    local self = Event.new(EventName_mt)
    return self
end

function EventName.new(param1, param2)
    local self = EventName.emptyNew()
    self.param1 = param1
    self.param2 = param2
    return self
end

function EventName:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.param1)
    streamWriteFloat32(streamId, self.param2)
end

function EventName:readStream(streamId, connection)
    self.param1 = streamReadInt32(streamId)
    self.param2 = streamReadFloat32(streamId)
    self:run(connection)
end

function EventName:run(connection)
    -- Server broadcasts to all clients (ONLY inside run() method)
    if not connection:getIsServer() then
        g_server:broadcastEvent(EventName.new(self.param1, self.param2))
    end
    
    -- Apply changes on receiving end
    -- Your game state update code here
end
```

**Send event from anywhere in your code (client OR server):**
```lua
g_client:getServerConnection():sendEvent(EventName.new(value1, value2))
```

### Stream Functions Reference

**Writing:**
- `streamWriteInt32(streamId, value)` - Write integer
- `streamWriteFloat32(streamId, value)` - Write float
- `streamWriteString(streamId, value)` - Write string
- `streamWriteBool(streamId, value)` - Write boolean

**Reading:**
- `streamReadInt32(streamId)` - Read integer
- `streamReadFloat32(streamId)` - Read float
- `streamReadString(streamId)` - Read string
- `streamReadBool(streamId)` - Read boolean

### Save/Load XML Patterns

**Main mod initialization (in loadMap):**
```lua
function MoistureSystem:loadMap()
    g_currentMission.MoistureSystem = self
    
    -- Initialize subsystems
    g_currentMission.groundPropertyTracker = GroundPropertyTracker.new()
    
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
        g_currentMission.groundPropertyTracker:loadFromXMLFile(xmlFile, MoistureSystem.SaveKey)
        
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
    g_currentMission.groundPropertyTracker:saveToXMLFile(xmlFile, MoistureSystem.SaveKey)
    
    saveXMLFile(xmlFile)
    delete(xmlFile)
end

FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, MoistureSystem.saveToXmlFile)
```

**Initialize on mission start:**
```lua
function MoistureSystem:onStartMission()
    CropValueMap.initialize()  -- Convert fillType names to indices
    local ms = g_currentMission.MoistureSystem
    ms:setHeights()  -- Calculate terrain height range
    
    if g_currentMission:getIsServer() then
        -- Initialize mod on new game
        if not ms.didLoadFromXML then
            ms:firstLoad()  -- Set initial moisture level
        end
    end
end

FSBaseMission.onStartMission = Utils.appendedFunction(FSBaseMission.onStartMission, MoistureSystem.onStartMission)
addModEventListener(MoistureSystem)  -- Enable loadMap and update callbacks
```

**Subsystem save method (takes xmlFile and key):**
```lua
function GroundPropertyTracker:saveToXMLFile(xmlFile, key)
    if not self.isServer then return end
    
    local i = 0
    for gridKey, pile in pairs(self.gridPiles) do
        local pileKey = string.format("%s.cropPiles.pile(%d)", key, i)
        
        setXMLInt(xmlFile, pileKey .. "#fillType", pile.fillType)
        setXMLFloat(xmlFile, pileKey .. "#gridX", pile.gridX)
        setXMLFloat(xmlFile, pileKey .. "#gridZ", pile.gridZ)
        
        if pile.properties.moisture then
            setXMLFloat(xmlFile, pileKey .. "#moisture", pile.properties.moisture)
        end
        
        i = i + 1
    end
end
```

**Subsystem load method (takes xmlFile and key):**
```lua
function GroundPropertyTracker:loadFromXMLFile(xmlFile, key)
    if not self.isServer then return end
    
    local i = 0
    while true do
        local pileKey = string.format("%s.cropPiles.pile(%d)", key, i)
        
        if not hasXMLProperty(xmlFile, pileKey) then
            break
        end
        
        local fillType = getXMLInt(xmlFile, pileKey .. "#fillType")
        local gridX = getXMLFloat(xmlFile, pileKey .. "#gridX")
        local gridZ = getXMLFloat(xmlFile, pileKey .. "#gridZ")
        local moisture = getXMLFloat(xmlFile, pileKey .. "#moisture")
        
        local pile = {
            fillType = fillType,
            gridX = gridX,
            gridZ = gridZ,
            properties = { moisture = moisture }
        }
        
        local gridKey = self:getGridKey(gridX, gridZ, fillType)
        self.gridPiles[gridKey] = pile
        
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

### Settings & GUI Integration

**Define settings with permission system:**
```lua
-- Extend Farm permission system
Farm.PERMISSION['CUSTOM_SETTINGS'] = "customSettings"
table.insert(Farm.PERMISSIONS, Farm.PERMISSION.CUSTOM_SETTINGS)

ModSettings = {}
ModSettings.menuItems = { 'setting1', 'setting2' }
ModSettings.multiplayerPermissions = { 'customSettings' }

ModSettings.SETTINGS = {}
ModSettings.SETTINGS.setting1 = {
    ['default'] = 2,
    ['serverOnly'] = true,
    ['permission'] = 'customSettings',
    ['values'] = { 1, 2, 3 },
    ['strings'] = { "Low", "Normal", "High" }
}
```

**Get state index from value:**
```lua
function ModSettings.getStateIndex(id, value)
    local value = value or g_currentMission.ModSystem.settings[id]
    local values = ModSettings.SETTINGS[id].values
    
    if type(value) == 'number' then
        local index = ModSettings.SETTINGS[id].default
        local initialdiff = math.huge
        for i, v in pairs(values) do
            local currentdiff = math.abs(v - value)
            if currentdiff < initialdiff then
                initialdiff = currentdiff
                index = i
            end
        end
        return index
    else
        for i, v in pairs(values) do
            if value == v then
                return i
            end
        end
    end
    return ModSettings.SETTINGS[id].default
end
```

**Inject settings into in-game menu:**
```lua
function ModSettings.addSettingsToMenu()
    local inGameMenu = g_gui.screenControllers[InGameMenu]
    local settingsPage = inGameMenu.pageSettings
    
    -- Create controls and add to settings page
    -- Use settingsPage:addElement() to integrate
end
```

### Specialized Extension Patterns

**Tracking properties on discharge to ground:**
```lua
function MSDischargeableExtension:dischargeToGround(superFunc, dischargeNode, emptyLiters)
    local dischargedLiters, minDropReached, hasMinDropFillLevel = superFunc(self, dischargeNode, emptyLiters)
    
    if not self.isServer or dischargedLiters == 0 then
        return dischargedLiters, minDropReached, hasMinDropFillLevel
    end
    
    -- Get discharge area coordinates
    local info = dischargeNode.info
    local sx, sy, sz = localToWorld(info.node, -info.width, 0, info.zOffset)
    local ex, ey, ez = localToWorld(info.node, info.width, 0, info.zOffset)
    
    -- Get moisture from vehicle or use field moisture
    local fillType = self:getDischargeFillType(dischargeNode)
    local moisture = g_currentMission.MoistureSystem:getObjectMoisture(self.uniqueId, fillType)
    
    if moisture == nil then
        local centerX = (sx + ex) / 2
        local centerZ = (sz + ez) / 2
        moisture = g_currentMission.MoistureSystem:getMoistureAtPosition(centerX, centerZ)
    end
    
    -- Track pile with properties using absolute value (dischargedLiters is negative)
    g_currentMission.groundPropertyTracker:addPile(
        sx, sz, ex, ez, ex, ez,
        math.abs(dischargedLiters),
        fillType,
        { moisture = moisture }
    )
    
    return dischargedLiters, minDropReached, hasMinDropFillLevel
end
```

**Clearing object moisture when empty:**
```lua
function MSCombineExtension:onFillUnitFillLevelChanged(superFunc, fillUnitIndex, fillLevelDelta, fillTypeIndex, toolType, fillPositionData, appliedDelta)
    if superFunc ~= nil then
        superFunc(self, fillUnitIndex, fillLevelDelta, fillTypeIndex, toolType, fillPositionData, appliedDelta)
    end
    
    if not self.isServer then
        return
    end
    
    -- Clear moisture when tank is emptied
    local fillLevel = self:getFillUnitFillLevel(fillUnitIndex)
    if fillLevel <= 0.001 then
        g_currentMission.MoistureSystem:setObjectMoisture(self.uniqueId, fillTypeIndex, nil)
    end
end
```

**Loading from ground piles with bucket/shovel:**
```lua
function MSFillVolumeExtension:onFillUnitFillLevelChanged(superFunc, fillUnitIndex, fillLevelDelta, fillType, toolType, fillPositionData, appliedDelta)
    if superFunc ~= nil then
        superFunc(self, fillUnitIndex, fillLevelDelta, fillType, toolType, fillPositionData, appliedDelta)
    end
    
    -- Only track pickups (positive delta with position data)
    if not self.isServer or fillLevelDelta <= 0 or fillPositionData == nil then
        return
    end
    
    -- Get moisture from tracked pile at pickup location
    local properties = g_currentMission.groundPropertyTracker:getPilePropertiesAtPosition(
        fillPositionData.x, fillPositionData.z, fillType
    )
    
    local moisture = properties and properties.moisture or 
                    g_currentMission.MoistureSystem:getMoistureAtPosition(fillPositionData.x, fillPositionData.z)
    
    -- Volume-weighted average with existing vehicle moisture
    local currentLiters = self:getFillUnitFillLevel(fillUnitIndex) - fillLevelDelta
    local currentMoisture = g_currentMission.MoistureSystem:getObjectMoisture(self.uniqueId, fillType)
    
    if currentMoisture == nil or currentLiters <= 0 then
        g_currentMission.MoistureSystem:setObjectMoisture(self.uniqueId, fillType, moisture)
    else
        local totalLiters = currentLiters + fillLevelDelta
        local averageMoisture = (currentLiters * currentMoisture + fillLevelDelta * moisture) / totalLiters
        g_currentMission.MoistureSystem:setObjectMoisture(self.uniqueId, fillType, averageMoisture)
    end
end
```

## Key Game Systems

### Density Map System
- Stores only filltype index and height
- No support for custom per-pile properties
- Located at world coordinates, managed by `DensityMapHeightUtil`
- Key functions:
  - `DensityMapHeightUtil.getFillLevelAtArea(fillType, x1, z1, x2, z2, x3, z3)` - Get volume in area
  - `DensityMapHeightUtil.changeFillTypeAtArea(sx, sz, wx, wz, hx, hz, fromType, toType)` - Convert fillType
  - `DensityMapHeightUtil.tipToGroundAroundLine(object, liters, fillType, x1, y1, z1, x2, y2, z2, radius, ...)` - Drop material

### Terrain & Coordinates
- `getTerrainHeightAtWorldPos(g_terrainNode, x, y, z)` - Get terrain height
- `getWorldTranslation(node)` - Get node's world coordinates (returns x, y, z)
- `localToWorld(node, x, y, z)` - Convert local to world coordinates

### FillType System
- `g_fillTypeManager:getFillTypeNameByIndex(fillType)` - Get name from index
- `g_fillTypeManager:getFillTypeIndexByName(name)` - Get index from name
- `FillType.GRASS` - Grass fillType constant
- `FillType.GRASS_WINDROW` - Grass windrow fillType constant

### Mission Timing
- `g_currentMission.time` - Current mission time in milliseconds
- `g_currentMission.environment.currentPeriod` - Current time period (0-11)
- `g_currentMission.environment.currentHour` - Current hour (0-23)
- `g_currentMission:getEffectiveTimeScale()` - Time scale multiplier
- `MessageType.PERIOD_CHANGED` - Event when period changes

### Weather System
- `g_currentMission.environment.weather` - Weather object
- `weather:getRainFallScale()` - Get rain intensity (0-1)
- `weather:getSnowFallScale()` - Get snow intensity (0-1)
- `weather.temperatureUpdater.currentTemperature` - Current temperature in Celsius

## Object Moisture Tracking

### Vehicle/Object Moisture System
- **Location**: `src/main.lua` (part of MoistureSystem)
- **Storage**: `MoistureSystem.objectMoisture = { [uniqueId] = { [fillTypeName] = moisture } }`
- Uses **fillTypeName** (string) for save/load compatibility, not fillType index
- Supports multiple fillTypes per object (combine can have wheat + barley)
- Key methods:
  - `getObjectMoisture(uniqueId, fillType)` - Get moisture for specific fillType
  - `setObjectMoisture(uniqueId, fillType, moisture)` - Set moisture (nil to clear)
  - `transferObjectMoisture(sourceId, targetId, sourceLiters, targetLiters, fillType)` - Volume-weighted transfer
  - `getDefaultMoisture()` - Returns current field moisture for silo loads
- Automatically cleared when vehicle empties (via CombineExtension)
- Persists in save game alongside pile data

## Tracked Crop System

### CropValueMap
- **Location**: `src/data/CropValueMap.lua`
- Defines which crops are tracked and their moisture grade ranges
- Uses fillType names (strings) in definitions, converted to indices at runtime via `initialize()`
- Grade system: A (optimal), B (good), C (fair), D (poor)
- Each grade has a price multiplier (e.g., A=1.0, B=0.9, C=0.8, D=0.7)
- `getGrade(fillType, moisture)` returns grade and multiplier for given moisture level
- Moisture ranges defined per crop (e.g., wheat optimal: 11-13%, barley: 12-14%)

### Grass Drying & Hay Conversion
- **Location**: `src/extensions/TedderExtension.lua` and `src/GroundPropertyTracker.lua`
- Tedding picks up grass, reduces moisture by configurable amount per pass, drops it back
- Grass moisture updated dynamically in `updateGrassMoisture()` based on weather
- When grass reaches ≤7% moisture (`DRY_THRESHOLD`), automatically converts to hay
- Uses dynamic converter system via `g_fillTypeManager:getConverterDataByName("TEDDER")`
- Conversion uses `DensityMapHeightUtil.changeFillTypeAtArea(sx, sz, wx, wz, hx, hz, grassType, hayType)`
- Converted cells marked as "hay cells" for 5 seconds to prevent grass re-appearing
- Cooldown system prevents tedded cells from being marked again for 5 seconds
- Moisture stored per-grid-cell (2m), tracked separately in `grassPiles` storage
- **Note**: Legacy `GRASS_CONVERSION_MAP` has been replaced with dynamic converter lookup

### Update Cycle Pattern
- Main system updates every 500ms (`updateInterval`)
- Cooldown counters are cycle-based (not timestamps) for efficiency
- Counters decremented each cycle: `counter = counter - 1`
- Remove when `counter <= 0`, not `== 0`
- Examples:
  - `teddedGridCellsCooldown[gridKey]` - 10 cycles = 5 seconds cooldown
  - `hayCells[gridKey]` - 10 cycles = 5 seconds to prevent grass reappearing

## Important Limitations

### Game Engine
1. **No native filltype properties** - Cannot store moisture directly on density map
2. **Area tracking required** - Must maintain parallel data structure for custom properties
3. **Approximate coordinates** - Pile positions are simplified rectangles
4. **Volume queries required** - Always query actual density map volume for accurate weighted averaging

## Performance Considerations

1. **Grid size selection** - 2m grid balances accuracy vs memory (smaller = more cells, more memory)
2. **Update intervals** - 500ms update interval prevents excessive calculations
3. **Volume-weighted averaging** - Always query actual density map volume for accurate weighting
4. **Cleanup tracking** - Remove empty piles from tracking immediately after pickup/conversion
5. **Cooldown timers** - Use cycle-based counters instead of timestamps for efficiency
6. **Separate storage** - Keep grass separate from crops to reduce lookup collisions
7. **Early returns** - Check `isServer` and nil values before expensive operations
8. **fillTypeName vs fillType** - Store fillTypeName (string) in save data, use fillType (index) in runtime logic
9. **Volume is negative on discharge** - `dischargedLiters` is negative, use `math.abs()` for volume
10. **Check for nil before access** - Chain of property access can fail at any point (`a.b.c` → check each)
11. **Grid position vs world position** - Always convert world coords to grid coords for storage keys
12. **Density map accuracy** - Query actual density map volume for accurate volume-weighted averaging, don't trust cached values
13. **Extension self reference** - Extensions add `self` as first param after `superFunc`, not before
14. **Cooldown counters** - Decrement counters in update loop, remove when ≤ 0, not == 0
15. **Cache invalidation** - Clear moisture cache when currentMoisturePercent changes or month transitions occur
16. **Grass rotting randomization** - Random accumulation prevents uniform removal across map
17. **Dynamic converter lookup** - Use `g_fillTypeManager:getConverterDataByName()` instead of hardcoded maps for future-proof fillType detection

## Common Patterns

### Volume-Weighted Averaging Pattern

Always use actual density map volume for accurate weighted averaging:
```lua
-- Get actual volume from density map
local checkRadius = GroundPropertyTracker.GRID_SIZE / 2  -- 2m grid = 1m radius
local existingVolume = DensityMapHeightUtil.getFillLevelAtArea(
    fillType,
    gridX - checkRadius, gridZ - checkRadius,
    gridX + checkRadius, gridZ - checkRadius,
    gridX - checkRadius, gridZ + checkRadius
)

local totalVolume = existingVolume + incomingVolume

-- Volume-weighted average
if totalVolume > 0 then
    newValue = (existingValue * existingVolume + incomingValue * incomingVolume) / totalVolume
end
```

### Grass Rotting Pattern

Gradual grass decay when wet using accumulator system:
```lua
-- Check moisture threshold and accumulate rot
if pile.properties.moisture > GroundPropertyTracker.ROT_MOISTURE_THRESHOLD then
    if not self.grassRotAccumulators[key] then
        self.grassRotAccumulators[key] = 0
    end
    
    -- Add randomized amount (prevents uniform removal)
    local randomAmount = GroundPropertyTracker.ROT_ACCUMULATION_MIN + 
        math.random() * (GroundPropertyTracker.ROT_ACCUMULATION_MAX - GroundPropertyTracker.ROT_ACCUMULATION_MIN)
    self.grassRotAccumulators[key] = self.grassRotAccumulators[key] + randomAmount
    
    -- Remove grass when threshold reached
    if self.grassRotAccumulators[key] >= GroundPropertyTracker.ROT_REMOVAL_THRESHOLD then
        -- Use tipToGroundAroundLine with negative amount
        local removed = DensityMapHeightUtil.tipToGroundAroundLine(
            nil, -amount, fillType, lsx, lsy, lsz, lex, ley, lez, radius, nil, nil, false, nil
        )
        if removed ~= 0 then
            self.grassRotAccumulators[key] = 0
            self:checkPileHasContent(gridX, gridZ, fillType)
        end
    end
else
    -- Clear accumulator when dry
    self.grassRotAccumulators[key] = nil
end
```

### Dynamic Grass Type Detection Pattern

Use converter data instead of hardcoded fillType maps:
```lua
-- Get all grass types that can be tedded
local converter = g_fillTypeManager:getConverterDataByName("TEDDER")
for fromFillType, to in pairs(converter) do
    local targetFillType = to.targetFillTypeIndex
    if fromFillType == targetFillType then
        continue  -- Skip non-converting entries
    end
    
    -- fromFillType is grass windrow (e.g., GRASS_WINDROW)
    -- targetFillType is hay/dry grass (e.g., DRYGRASS_WINDROW)
    -- Process grass types here
end
```

## Coding Conventions

### Naming
- **Classes**: PascalCase (e.g., `GroundPropertyTracker`)
- **Extensions**: Prefix with `MS` (e.g., `MSCombineExtension`, `MSTedderExtension`)
- **Functions**: camelCase (e.g., `getMoistureAtPosition`)
- **Constants**: UPPER_SNAKE_CASE (e.g., `GRID_SIZE`, `DRY_THRESHOLD`)
- **Private methods**: Use `:` prefix in self calls (e.g., `self:getGridPosition()`)

### Structure
- Use `Class()` for class definitions with metatables
- Always check `self.isServer` or `g_currentMission:getIsServer()` for server-only operations
- Return early for invalid states
- Use guard clauses to reduce nesting
- Check for nil before accessing nested properties

### Comments
- Document public functions with `---` comments
- Include `@param` and `@return` tags for function signatures
- Explain non-obvious algorithms inline
- Use descriptive print statements for debugging (prefix with `[SYSTEM NAME]`)

### Extension Pattern
```lua
MSExtensionName = {}

function MSExtensionName:functionName(superFunc, param1, param2)
    -- Your code before original
    local result = superFunc(self, param1, param2)
    -- Your code after original
    return result
end

ClassName.functionName = Utils.overwrittenFunction(
    ClassName.functionName,
    MSExtensionName.functionName
)
```

## Common Gotchas

1. **Don't create XMLFile objects** - Use `loadXMLFile` and `createXMLFile` directly
2. **Load in loadMap, not via hook** - loadFromXMLFile called directly during initialization
3. **Only save is hooked** - Use `FSBaseMission.saveSavegame` with `Utils.appendedFunction`
4. **Use separate XML files** - Don't try to inject into careerSavegame.xml
5. **Check hasXMLProperty** - Always check existence before reading nested properties
6. **Manual iteration** - Use `while true` with counter for arrays, not `xmlFile:iterate()`
7. **Server-only operations** - Always check `g_currentMission:getIsServer()` before modifying game state

## Localization (l10n)

All user-facing text must be localized to support multiple languages.

### Adding Localized Text

**Language file location**: `languages/l10n_en.xml` (and other language variants)

**Add text entry:**
```xml
<text name="moistureSystem_gui_cropGradeValues" text="Crop Grade Values"/>
```

**Naming convention**: Use descriptive keys prefixed with mod context
- GUI text: `moistureSystem_gui_<description>`
- Settings: `setting_moisture_<settingName>`
- HUD display: `moistureSystem_<description>`
- Permissions: `permission_moisture_<permissionName>`

### Using Localized Text

**In XML files** - Prefix with `$l10n_`:
```xml
<Text text="$l10n_moistureSystem_gui_cropGradeValues" />
```

**In Lua code** - Use `g_i18n:getText()`:
```lua
local text = g_i18n:getText("moistureSystem_gui_cropGradeValues")
```

**With formatting** - Use `g_i18n:getText()` with string.format:
```lua
local text = string.format(g_i18n:getText("moistureSystem_moisture"), value)
```

### Important Notes
- Never hardcode user-facing strings
- Keys must match exactly between XML and references (case-sensitive)
- All language files must have the same keys (even if translations aren't complete)
- Use comments in l10n files to organize related entries
