---
-- PlaceableObjectStorageExtension
-- Extends PlaceableObjectStorage to keep rotting bales alive in storage
-- This allows BaleRottingSystem to continue processing bales even when stored
---

MSPlaceableObjectStorageExtension = {}

---
-- Override saveToXMLFile to save uniqueId for rotting bales
-- @param superFunc: Original function
-- @param xmlFile: XML file handle
-- @param key: XML key path
-- @param usedModNames: Used mod names table
---
function MSPlaceableObjectStorageExtension:saveToXMLFile(superFunc, xmlFile, key, usedModNames)
    superFunc(self, xmlFile, key, usedModNames)
    
    -- We can't save uniqueId directly to storage XML (schema doesn't allow it)
    -- Instead, we save a mapping in MoistureSystem.xml via the main save hook
    -- The storage uniqueId mapping will be saved by MoistureSystem:saveToXmlFile
end

----- Override loadFromXMLFile to load uniqueId for rotting bales
-- @param superFunc: Original function
-- @param xmlFile: XML file handle
-- @param key: XML key path
---
function MSPlaceableObjectStorageExtension:loadFromXMLFile(superFunc, xmlFile, key)
    superFunc(self, xmlFile, key)
    
    if not self.isServer then return end
    
    local spec = self.spec_objectStorage
    if not spec or not spec.storedObjects then return end
    
    -- Load uniqueId from our MoistureSystem save file (not from storage XML due to schema restrictions)
    local moistureSystem = g_currentMission.MoistureSystem
    if moistureSystem and moistureSystem.pendingStorageBaleIds and moistureSystem.pendingStorageBaleIds[self.uniqueId] then
        local placeableMappings = moistureSystem.pendingStorageBaleIds[self.uniqueId]
        
        for objectIndex, uniqueId in pairs(placeableMappings) do
            local abstractObject = spec.storedObjects[objectIndex + 1]  -- Convert 0-based to 1-based
            if abstractObject then
                -- Store in baleAttributes (live bales will get it via getBaleAttributes)
                if abstractObject.baleAttributes then
                    abstractObject.baleAttributes.uniqueId = uniqueId
                end
                if abstractObject.baleObject then
                    abstractObject.baleObject.uniqueId = uniqueId
                end
            end
        end
    end
end

----- Override addObjectToObjectStorage to keep rotting bales alive
-- Rotting bales need to stay as live objects (like fermenting bales) so they can continue rotting
-- This completely handles rotting bale storage without manipulating isFermenting flag
-- @param superFunc: Original function
-- @param object: Object to store
-- @param loadedFromSavegame: Boolean - if loading from save
---
function MSPlaceableObjectStorageExtension:addObjectToObjectStorage(superFunc, object, loadedFromSavegame)
    if not self.isServer then
        return superFunc(self, object, loadedFromSavegame)
    end
    
    -- Check if this is a rotting bale (non-fermenting)
    local isRotting = object.getIsRotting and object:getIsRotting()
    local isFermenting = object.isFermenting
    
    -- Only handle non-fermenting rotting bales with custom logic
    -- Fermenting bales and non-rotting bales use normal storage
    if not isRotting or isFermenting then
        return superFunc(self, object, loadedFromSavegame)
    end
    
    -- This is a rotting (non-fermenting) bale - keep it alive using custom logic
    
    -- Get storage position
    local x, y, z = getWorldTranslation(self.rootNode)
    local rx, ry, rz = getWorldRotation(self.rootNode)
    
    -- Create custom abstract object to hold the live bale
    local abstractObject = {
        isRottingBale = true,  -- Mark as our custom storage
        baleObject = nil,
        REFERENCE_CLASS_NAME = "Bale"  -- Required for XML save
    }
    
    -- Store the bale object (keep it alive)
    if loadedFromSavegame then
        removeFromPhysics(object.nodeId)
        setVisibility(object.nodeId, false)
        setWorldTranslation(object.nodeId, x, y, z)
        setWorldRotation(object.nodeId, rx, ry, rz)
        object:unregister()
        object:setNeedsSaving(false)
        abstractObject.baleObject = object
    else
        -- Get attributes, delete old bale, create new one at storage location
        local baleAttributes = object:getBaleAttributes()
        local uniqueId = object.uniqueId
        
        -- CRITICAL: Save rotting state before deletion (onBaleDeleted hook will clear it)
        local baleRottingSystem = g_currentMission.baleRottingSystem
        local savedExposureData = nil
        if baleRottingSystem and baleRottingSystem.baleRainExposureTimes[uniqueId] then
            savedExposureData = {
                exposure = baleRottingSystem.baleRainExposureTimes[uniqueId].exposure,
                peakExposure = baleRottingSystem.baleRainExposureTimes[uniqueId].peakExposure,
                status = baleRottingSystem.baleRainExposureTimes[uniqueId].status
            }
        end
        
        object:delete()
        
        local newBale = Bale.new(self.isServer, self.isClient)
        if newBale:loadFromConfigXML(baleAttributes.xmlFilename, x, y, z, rx, ry, rz, uniqueId) then
            newBale:applyBaleAttributes(baleAttributes)
            newBale:setNeedsSaving(false)
            removeFromPhysics(newBale.nodeId)
            setVisibility(newBale.nodeId, false)
            
            -- Restore rotting state after creating new bale
            if savedExposureData and baleRottingSystem then
                baleRottingSystem.baleRainExposureTimes[uniqueId] = savedExposureData
            end
            
            abstractObject.baleObject = newBale
        else
            return
        end
    end
    
    -- Add all required methods
    MSPlaceableObjectStorageExtension.addAbstractObjectMethods(abstractObject)
    
    -- Add to storage
    local spec = self.spec_objectStorage
    table.insert(spec.storedObjects, abstractObject)
    spec.numStoredObjects = #spec.storedObjects
    g_farmManager:updateFarmStats(self:getOwnerFarmId(), "storedBales", 1)
end

---
-- Remove a bale from storage when it has rotted to 0 volume
-- Called by BaleRottingSystem when a stored bale is deleted
-- @param bale: Bale object being deleted
---
function MSPlaceableObjectStorageExtension:removeRottedBaleFromStorage(bale)
    if not self.isServer then return end
    
    local spec = self.spec_objectStorage
    if not spec or not spec.storedObjects then 
        return 
    end
    
    -- Find the abstract bale object that contains this bale
    for i = #spec.storedObjects, 1, -1 do
        local abstractObject = spec.storedObjects[i]
        
        -- Check if this is the abstract object containing our bale
        if abstractObject.baleObject and abstractObject.baleObject == bale then
            -- Remove from storage
            table.remove(spec.storedObjects, i)
            spec.numStoredObjects = spec.numStoredObjects - 1
            
            -- Update object infos
            self:setObjectStorageObjectInfosDirty()
            
            -- Update farm stats
            g_farmManager:updateFarmStats(self:getOwnerFarmId(), "storedBales", -1)
            
            -- Clear the bale object reference to prevent double deletion
            abstractObject.baleObject = nil
            
            return true
        end
    end
    
    return false
end

---
-- Find which storage (if any) contains a given bale
-- @param bale: Bale object to search for
-- @return PlaceableObjectStorage or nil
---
function MSPlaceableObjectStorageExtension.findStorageForBale(bale)
    if not bale or not bale.isServer then return nil end
    
    -- Search all placeables with objectStorage spec
    for _, placeable in pairs(g_currentMission.placeableSystem.placeables) do
        if placeable.spec_objectStorage then
            local spec = placeable.spec_objectStorage
            
            -- Check stored objects for this bale
            if spec.storedObjects then
                for _, abstractObject in ipairs(spec.storedObjects) do
                    if abstractObject.baleObject and abstractObject.baleObject == bale then
                        return placeable
                    end
                end
            end
        end
    end
    
    return nil
end

-- Override the addObjectToObjectStorage function
PlaceableObjectStorage.saveToXMLFile = Utils.overwrittenFunction(
    PlaceableObjectStorage.saveToXMLFile,
    MSPlaceableObjectStorageExtension.saveToXMLFile
)

PlaceableObjectStorage.loadFromXMLFile = Utils.overwrittenFunction(
    PlaceableObjectStorage.loadFromXMLFile,
    MSPlaceableObjectStorageExtension.loadFromXMLFile
)

PlaceableObjectStorage.addObjectToObjectStorage = Utils.overwrittenFunction(
    PlaceableObjectStorage.addObjectToObjectStorage,
    MSPlaceableObjectStorageExtension.addObjectToObjectStorage
)

---
-- Convert attribute-stored rotting bales to live storage after savegame load
-- Called after mission start when rotting data has been loaded
---
function MSPlaceableObjectStorageExtension.convertRottingBalesToLiveStorage()
    if not g_currentMission:getIsServer() then return end
    
    local baleRottingSystem = g_currentMission.baleRottingSystem
    if not baleRottingSystem then 
        return
    end
    
    -- Check all placeables with storage
    for _, placeable in pairs(g_currentMission.placeableSystem.placeables) do
        if placeable.spec_objectStorage then
            local spec = placeable.spec_objectStorage
            
            if spec.storedObjects and #spec.storedObjects > 0 then
                
                -- Check each stored object
                for i = #spec.storedObjects, 1, -1 do
                    local abstractObject = spec.storedObjects[i]
                    
                    -- Check if this is an attribute-only bale (no live baleObject)
                    if abstractObject.baleAttributes and not abstractObject.baleObject then
                        local uniqueId = abstractObject.baleAttributes.uniqueId
                        
                        -- Check if this bale has rotting exposure data
                        if uniqueId and baleRottingSystem.baleRainExposureTimes[uniqueId] then
                            
                            -- Create live bale from attributes
                            local x, y, z = getWorldTranslation(placeable.rootNode)
                            local rx, ry, rz = getWorldRotation(placeable.rootNode)
                            
                            local newBale = Bale.new(true, false)
                            if newBale:loadFromConfigXML(abstractObject.baleAttributes.xmlFilename, x, y, z, rx, ry, rz, uniqueId) then
                                newBale:applyBaleAttributes(abstractObject.baleAttributes)
                                newBale:setNeedsSaving(false)
                                removeFromPhysics(newBale.nodeId)
                                setVisibility(newBale.nodeId, false)
                                
                                -- Replace the abstract object with our custom one
                                abstractObject.baleObject = newBale
                                abstractObject.baleAttributes = nil
                                abstractObject.isRottingBale = true
                                abstractObject.REFERENCE_CLASS_NAME = "Bale"
                                
                                -- Add all required methods
                                MSPlaceableObjectStorageExtension.addAbstractObjectMethods(abstractObject)
                            end
                        end
                    end
                end
            end
        end
    end
end

---
-- Helper function to add all required abstract object methods
-- Separated so it can be used both during storage and post-load conversion
---
function MSPlaceableObjectStorageExtension.addAbstractObjectMethods(abstractObject)
    -- getRealObject - returns the actual bale object
    abstractObject.getRealObject = function(self)
        return self.baleObject
    end
    
    -- getXMLFilename - returns bale config path
    abstractObject.getXMLFilename = function(self)
        if self.baleObject then
            return self.baleObject.xmlFilename
        end
        return nil
    end
    
    -- getIsIdentical - check if two abstract objects are same type
    abstractObject.getIsIdentical = function(self, otherAbstractObject)
        if self.baleObject and otherAbstractObject.baleObject then
            return self.baleObject.xmlFilename == otherAbstractObject.baleObject.xmlFilename and
                   self.baleObject:getFillType() == otherAbstractObject.baleObject:getFillType()
        end
        return false
    end
    
    -- getDialogText - returns display text for UI
    abstractObject.getDialogText = function(self)
        if self.baleObject then
            local xmlFilename = self.baleObject.xmlFilename
            local fillTypeName = g_fillTypeManager:getFillTypeTitleByIndex(self.baleObject:getFillType())
            local fillLevel = self.baleObject:getFillLevel()
            
            local isRoundbale = g_baleManager:getBaleInfoByXMLFilename(xmlFilename, true)
            local baleType
            if isRoundbale then
                baleType = g_i18n:getText("fillType_roundBale")
            else
                baleType = g_i18n:getText("fillType_squareBale")
            end
            
            return string.format("%s (%s %s)", baleType, fillTypeName, g_i18n:formatFluid(fillLevel))
        end
        return "Unknown Bale"
    end
    
    -- getSpawnInfo - returns spawn dimensions and info
    abstractObject.getSpawnInfo = function(self)
        if self.baleObject then
            local xmlFilename = self.baleObject.xmlFilename
            local isRoundbale, width, height, length, diameter, maxStackHeight = g_baleManager:getBaleInfoByXMLFilename(xmlFilename, true)
            
            -- Use actual dimensions or fallback to bale object properties
            width = width or self.baleObject.width or 1.2
            height = height or self.baleObject.height or 1.2
            length = length or self.baleObject.length or 1.2
            diameter = diameter or width
            maxStackHeight = maxStackHeight or 1.0
            
            if isRoundbale then
                -- Round bale: offsetX=0, offsetY=width/2, offsetZ=0, width=diameter, height=width, length=diameter, maxStackHeight
                return 0, width * 0.5, 0, diameter, width, diameter, maxStackHeight
            else
                -- Square bale: offsetX=0, offsetY=height/2, offsetZ=0, width, height, length, maxStackHeight
                return 0, height * 0.5, 0, width, height, length, maxStackHeight
            end
        end
        -- Fallback for invalid bale
        return 0, 0.6, 0, 1.2, 1.2, 1.2, 1.0
    end
    
    -- getLimitedObjectId - returns limited object info (for slot system)
    abstractObject.getLimitedObjectId = function(self)
        return SlotSystem.LIMITED_OBJECT_BALE, PlaceableObjectStorageErrorEvent.ERROR_SLOT_LIMIT_REACHED_BALES
    end
    
    -- delete - cleanup when abstract object is deleted
    abstractObject.delete = function(self)
        if self.baleObject then
            self.baleObject = nil
        end
    end
    
    -- spawnVisualObjects - spawn visual representations in storage area
    abstractObject.spawnVisualObjects = function(self, visualSpawnInfos)
        if not self.baleObject then return end
        
        -- Get bale properties for visual spawning
        local xmlFilename = self.baleObject.xmlFilename
        local fillType = self.baleObject:getFillType()
        local wrappingState = self.baleObject.wrappingState
        local wrappingColor = self.baleObject.wrappingColor
        local variationIndex = self.baleObject.variationIndex
        
        -- Create dummy bale for cloning
        local dummyBaleId, sharedLoadRequestId = Bale.createDummyBale(xmlFilename, fillType, variationIndex, wrappingState, wrappingColor)
        
        if dummyBaleId then
            -- Clone for each spawn position
            for i = 1, #visualSpawnInfos do
                local spawnInfo = visualSpawnInfos[i]
                local clonedBale = clone(dummyBaleId, false, false, false)
                
                -- Link to spawn node and position
                link(spawnInfo[1], clonedBale)
                setTranslation(clonedBale, spawnInfo[2], spawnInfo[3], spawnInfo[4])
                setRotation(clonedBale, spawnInfo[5], spawnInfo[6], spawnInfo[7])
                
                -- Rotate round bales
                local isRoundbale = g_baleManager:getBaleInfoByXMLFilename(xmlFilename, true)
                if isRoundbale then
                    rotateAboutLocalAxis(clonedBale, 1.5707963267948966, 1, 0, 0)
                end
            end
            
            -- Cleanup dummy
            delete(dummyBaleId)
            g_i3DManager:releaseSharedI3DFile(sharedLoadRequestId)
        end
    end
    
    -- removeFromStorage - called when unloading from storage
    abstractObject.removeFromStorage = function(self, storage, x, y, z, rx, ry, rz, spawnedCallback)
        if self.baleObject then
            addToPhysics(self.baleObject.nodeId)
            setVisibility(self.baleObject.nodeId, true)
            local quatX, quatY, quatZ, quatW = mathEulerToQuaternion(rx, ry, rz)
            self.baleObject:setLocalPositionQuaternion(x, y, z, quatX, quatY, quatZ, quatW, true)
            self.baleObject:register()
            self.baleObject:setNeedsSaving(true)
            
            if self.baleObject.isRoundbale then
                removeFromPhysics(self.baleObject.nodeId)
                rotateAboutLocalAxis(self.baleObject.nodeId, 1.5707963267948966, 1, 0, 0)
                addToPhysics(self.baleObject.nodeId)
            end
            
            g_farmManager:updateFarmStats(storage:getOwnerFarmId(), "storedBales", -1)
            spawnedCallback(storage, self.baleObject)
        end
    end
    
    -- writeStream - for network sync
    abstractObject.writeStream = function(self, streamId, connection)
        if self.baleObject then
            streamWriteString(streamId, NetworkUtil.convertToNetworkFilename(self.baleObject.xmlFilename))
            streamWriteFloat32(streamId, self.baleObject:getFillLevel())
            streamWriteUIntN(streamId, self.baleObject:getFillType(), FillTypeManager.SEND_NUM_BITS)
            streamWriteBool(streamId, self.baleObject.wrappingState ~= 0)
            streamWriteUIntN(streamId, self.baleObject.variationIndex - 1, Bale.NUM_BITS_VARIATION)
        end
    end
    
    -- saveToXMLFile - save bale data to savegame
    abstractObject.saveToXMLFile = function(self, storage, xmlFile, key)
        if self.baleObject then
            local baleAttributes = self.baleObject:getBaleAttributes()
            Bale.saveBaleAttributesToXMLFile(baleAttributes, xmlFile, key)
        end
    end
end
