----------------------------------------------------------------------------------------------------
-- MoistureMeterTool
----------------------------------------------------------------------------------------------------
-- Purpose:  Hand tool loader and registration for Moisture Meter
--
-- Copyright (c) 2025
----------------------------------------------------------------------------------------------------

MSHandTools = {}

local modDirectory = g_currentModDirectory
local modName = g_currentModName
local path = modDirectory .. "xml/handTools.xml"
local xmlFile = XMLFile.loadIfExists("msHandTools", path)

MSHandTools.xmlPaths = {}

if xmlFile ~= nil then
    -- Register specializations
    xmlFile:iterate("handTools.specializations.specialization", function(_, key)
        local name = xmlFile:getString(key .. "#name")
        local className = xmlFile:getString(key .. "#className")
        local filename = xmlFile:getString(key .. "#filename")
        
        g_handToolSpecializationManager:addSpecialization(name, className, modDirectory .. filename)
        
        print(string.format("[MoistureSystem] Registered hand tool specialization: %s", name))
    end)
    
    -- Register types
    xmlFile:iterate("handTools.types.type", function(_, key)
        g_handToolTypeManager:loadTypeFromXML(xmlFile.handle, key, false, nil, modName)
        
        MSHandTools.xmlPaths[xmlFile:getString(key .. "#name")] = modDirectory .. xmlFile:getString(key .. "#xmlFile")
        
        print(string.format("[MoistureSystem] Registered hand tool type: %s", xmlFile:getString(key .. "#name")))
    end)
    
    xmlFile:delete()
end
