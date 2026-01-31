---
-- MoistureSystem - Grades Frame
--

MoistureGuiGrades = {}

local MoistureGuiGrades_mt = Class(MoistureGuiGrades, TabbedMenuFrameElement)

function MoistureGuiGrades.new(l18n)
    local self = TabbedMenuFrameElement.new(nil, MoistureGuiGrades_mt)
    self.l18n = l18n
    return self
end

function MoistureGuiGrades:initialize()
    -- Initialize frame content here
end

function MoistureGuiGrades:onFrameOpen()
    MoistureGuiGrades:superClass().onFrameOpen(self)
end

function MoistureGuiGrades:onFrameClose()
    MoistureGuiGrades:superClass().onFrameClose(self)
end
