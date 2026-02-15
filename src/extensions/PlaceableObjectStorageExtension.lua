---
-- PlaceableObjectStorageExtension
-- Extends PlaceableObjectStorage to keep rotting bales alive in storage
-- This allows BaleRottingSystem to continue processing bales even when stored
---

MSPlaceableObjectStorageExtension = {}

---
-- Override addObjectToObjectStorage to keep rotting bales alive
-- Rotting bales need to stay as live objects (like fermenting bales) so they can continue rotting
-- @param superFunc: Original function
-- @param object: Object to store
-- @param loadedFromSavegame: Boolean - if loading from save
---
function MSPlaceableObjectStorageExtension:addObjectToObjectStorage(superFunc, object, loadedFromSavegame)
    -- Check if this is a rotting bale
    if object.getIsRotting and object:getIsRotting() then
        -- Temporarily mark as fermenting so PlaceableObjectStorage keeps it alive
        -- The internal AbstractBaleObject:addToStorage checks isFermenting to decide
        -- whether to keep the bale object alive or just store attributes
        local wasNotFermenting = not object.isFermenting
        
        if wasNotFermenting then
            object.isFermenting = true
        end
        
        -- Call original function
        local result = superFunc(self, object, loadedFromSavegame)
        
        -- Restore original isFermenting state
        -- (though the bale object is now stored, so this doesn't matter much)
        if wasNotFermenting then
            -- Object may have been deleted already if not kept alive
            -- So we need to find the stored abstract object and set flag on that bale
            local spec = self.spec_objectStorage
            if spec and spec.storedObjects then
                for _, abstractObject in ipairs(spec.storedObjects) do
                    if abstractObject.baleObject and abstractObject.baleObject.uniqueId == object.uniqueId then
                        abstractObject.baleObject.isFermenting = false
                        break
                    end
                end
            end
        end
        
        return result
    else
        -- Not a rotting bale, use original behavior
        return superFunc(self, object, loadedFromSavegame)
    end
end

---
-- Remove a bale from storage when it has rotted to 0 volume
-- Called by BaleRottingSystem when a stored bale is deleted
-- @param bale: Bale object being deleted
---
function MSPlaceableObjectStorageExtension:removeRottedBaleFromStorage(bale)
    if not self.isServer then return end
    
    local spec = self.spec_objectStorage
    if not spec or not spec.storedObjects then return end
    
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
PlaceableObjectStorage.addObjectToObjectStorage = Utils.overwrittenFunction(
    PlaceableObjectStorage.addObjectToObjectStorage,
    MSPlaceableObjectStorageExtension.addObjectToObjectStorage
)

-- Register the removal function as a method on PlaceableObjectStorage
PlaceableObjectStorage.removeRottedBaleFromStorage = MSPlaceableObjectStorageExtension.removeRottedBaleFromStorage
