CropValueMap = {}

CropValueMap.Grades = {
    A = 1,
    B = 2,
    C = 3,
    D = 4
}

-- Define data using fillType names (strings) to avoid nil references
local dataDefinitions = {
    ["WHEAT"] = {
        { lower = 0.00, upper = 0.08, grade = CropValueMap.Grades.C, multiplier = 0.8 },
        { lower = 0.08, upper = 0.11, grade = CropValueMap.Grades.B, multiplier = 0.9 },
        { lower = 0.11, upper = 0.13, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.13, upper = 0.15, grade = CropValueMap.Grades.B, multiplier = 0.9 },
        { lower = 0.15, upper = 1.00, grade = CropValueMap.Grades.C, multiplier = 0.8 }
    },
    ["BARLEY"] = {
        { lower = 0.00, upper = 0.09, grade = CropValueMap.Grades.D, multiplier = 0.7 },
        { lower = 0.09, upper = 0.12, grade = CropValueMap.Grades.B, multiplier = 0.9 },
        { lower = 0.12, upper = 0.14, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.14, upper = 0.17, grade = CropValueMap.Grades.B, multiplier = 0.9 },
        { lower = 0.17, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.7 }
    }
}

-- Initialize data by converting fillType names to indices
function CropValueMap.initialize()
    CropValueMap.Data = {}
    
    for fillTypeName, ranges in pairs(dataDefinitions) do
        local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
        if fillTypeIndex ~= nil then
            CropValueMap.Data[fillTypeIndex] = ranges
        end
    end
end

function CropValueMap.getGrade(fillType, moisture)
    local ranges = CropValueMap.Data[fillType]
    if not ranges then return nil end

    for _, range in ipairs(ranges) do
        if moisture >= range.lower and moisture < range.upper then
            return range.grade, range.multiplier
        end
    end
    return nil
end
