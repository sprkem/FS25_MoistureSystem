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
        { lower = 0.00, upper = 0.06, grade = CropValueMap.Grades.D, multiplier = 0.55 },
        { lower = 0.06, upper = 0.08, grade = CropValueMap.Grades.C, multiplier = 0.75 },
        { lower = 0.08, upper = 0.11, grade = CropValueMap.Grades.B, multiplier = 0.90 },
        { lower = 0.11, upper = 0.13, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.13, upper = 0.15, grade = CropValueMap.Grades.B, multiplier = 0.90 },
        { lower = 0.15, upper = 0.18, grade = CropValueMap.Grades.C, multiplier = 0.75 },
        { lower = 0.18, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.55 }
    },
    ["BARLEY"] = {
        { lower = 0.00, upper = 0.07, grade = CropValueMap.Grades.D, multiplier = 0.65 },
        { lower = 0.07, upper = 0.09, grade = CropValueMap.Grades.C, multiplier = 0.80 },
        { lower = 0.09, upper = 0.12, grade = CropValueMap.Grades.B, multiplier = 0.92 },
        { lower = 0.12, upper = 0.14, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.14, upper = 0.17, grade = CropValueMap.Grades.B, multiplier = 0.92 },
        { lower = 0.17, upper = 0.20, grade = CropValueMap.Grades.C, multiplier = 0.80 },
        { lower = 0.20, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.65 }
    },
    ["WINTERBARLEY"] = {
        { lower = 0.00, upper = 0.07, grade = CropValueMap.Grades.D, multiplier = 0.65 },
        { lower = 0.07, upper = 0.09, grade = CropValueMap.Grades.C, multiplier = 0.80 },
        { lower = 0.09, upper = 0.12, grade = CropValueMap.Grades.B, multiplier = 0.92 },
        { lower = 0.12, upper = 0.14, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.14, upper = 0.17, grade = CropValueMap.Grades.B, multiplier = 0.92 },
        { lower = 0.17, upper = 0.20, grade = CropValueMap.Grades.C, multiplier = 0.80 },
        { lower = 0.20, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.65 }
    },
    ["WINTERWHEAT"] = {
        { lower = 0.00, upper = 0.06, grade = CropValueMap.Grades.D, multiplier = 0.55 },
        { lower = 0.06, upper = 0.08, grade = CropValueMap.Grades.C, multiplier = 0.75 },
        { lower = 0.08, upper = 0.11, grade = CropValueMap.Grades.B, multiplier = 0.90 },
        { lower = 0.11, upper = 0.13, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.13, upper = 0.15, grade = CropValueMap.Grades.B, multiplier = 0.90 },
        { lower = 0.15, upper = 0.18, grade = CropValueMap.Grades.C, multiplier = 0.75 },
        { lower = 0.18, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.55 }
    },
    ["MAIZE"] = {
        { lower = 0.00, upper = 0.08, grade = CropValueMap.Grades.D, multiplier = 0.65 },
        { lower = 0.08, upper = 0.10, grade = CropValueMap.Grades.C, multiplier = 0.82 },
        { lower = 0.10, upper = 0.13, grade = CropValueMap.Grades.B, multiplier = 0.93 },
        { lower = 0.13, upper = 0.16, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.16, upper = 0.24, grade = CropValueMap.Grades.B, multiplier = 0.93 },
        { lower = 0.24, upper = 0.27, grade = CropValueMap.Grades.C, multiplier = 0.82 },
        { lower = 0.27, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.65 }
    },
    ["SILAGEMAIZE"] = {
        { lower = 0.00, upper = 0.08, grade = CropValueMap.Grades.D, multiplier = 0.65 },
        { lower = 0.08, upper = 0.10, grade = CropValueMap.Grades.C, multiplier = 0.82 },
        { lower = 0.10, upper = 0.13, grade = CropValueMap.Grades.B, multiplier = 0.93 },
        { lower = 0.13, upper = 0.16, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.16, upper = 0.24, grade = CropValueMap.Grades.B, multiplier = 0.93 },
        { lower = 0.24, upper = 0.27, grade = CropValueMap.Grades.C, multiplier = 0.82 },
        { lower = 0.27, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.65 }
    },
    ["OAT"] = {
        { lower = 0.00, upper = 0.08, grade = CropValueMap.Grades.D, multiplier = 0.68 },
        { lower = 0.08, upper = 0.10, grade = CropValueMap.Grades.C, multiplier = 0.83 },
        { lower = 0.10, upper = 0.13, grade = CropValueMap.Grades.B, multiplier = 0.93 },
        { lower = 0.13, upper = 0.14, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.14, upper = 0.16, grade = CropValueMap.Grades.B, multiplier = 0.93 },
        { lower = 0.16, upper = 0.19, grade = CropValueMap.Grades.C, multiplier = 0.83 },
        { lower = 0.19, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.68 }
    },
    ["RYE"] = {
        { lower = 0.00, upper = 0.08, grade = CropValueMap.Grades.D, multiplier = 0.62 },
        { lower = 0.08, upper = 0.10, grade = CropValueMap.Grades.C, multiplier = 0.78 },
        { lower = 0.10, upper = 0.13, grade = CropValueMap.Grades.B, multiplier = 0.91 },
        { lower = 0.13, upper = 0.14, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.14, upper = 0.16, grade = CropValueMap.Grades.B, multiplier = 0.91 },
        { lower = 0.16, upper = 0.19, grade = CropValueMap.Grades.C, multiplier = 0.78 },
        { lower = 0.19, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.62 }
    },
    ["TRITICALE"] = {
        { lower = 0.00, upper = 0.08, grade = CropValueMap.Grades.D, multiplier = 0.66 },
        { lower = 0.08, upper = 0.10, grade = CropValueMap.Grades.C, multiplier = 0.81 },
        { lower = 0.10, upper = 0.13, grade = CropValueMap.Grades.B, multiplier = 0.92 },
        { lower = 0.13, upper = 0.14, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.14, upper = 0.16, grade = CropValueMap.Grades.B, multiplier = 0.92 },
        { lower = 0.16, upper = 0.19, grade = CropValueMap.Grades.C, multiplier = 0.81 },
        { lower = 0.19, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.66 }
    },
    ["SPELT"] = {
        { lower = 0.00, upper = 0.07, grade = CropValueMap.Grades.D, multiplier = 0.58 },
        { lower = 0.07, upper = 0.09, grade = CropValueMap.Grades.C, multiplier = 0.76 },
        { lower = 0.09, upper = 0.12, grade = CropValueMap.Grades.B, multiplier = 0.91 },
        { lower = 0.12, upper = 0.14, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.14, upper = 0.17, grade = CropValueMap.Grades.B, multiplier = 0.91 },
        { lower = 0.17, upper = 0.20, grade = CropValueMap.Grades.C, multiplier = 0.76 },
        { lower = 0.20, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.58 }
    },
    ["RICE"] = {
        { lower = 0.00, upper = 0.07, grade = CropValueMap.Grades.D, multiplier = 0.52 },
        { lower = 0.07, upper = 0.09, grade = CropValueMap.Grades.C, multiplier = 0.72 },
        { lower = 0.09, upper = 0.12, grade = CropValueMap.Grades.B, multiplier = 0.88 },
        { lower = 0.12, upper = 0.14, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.14, upper = 0.17, grade = CropValueMap.Grades.B, multiplier = 0.88 },
        { lower = 0.17, upper = 0.20, grade = CropValueMap.Grades.C, multiplier = 0.72 },
        { lower = 0.20, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.52 }
    },
    ["RICELONGGRAIN"] = {
        { lower = 0.00, upper = 0.07, grade = CropValueMap.Grades.D, multiplier = 0.52 },
        { lower = 0.07, upper = 0.09, grade = CropValueMap.Grades.C, multiplier = 0.72 },
        { lower = 0.09, upper = 0.12, grade = CropValueMap.Grades.B, multiplier = 0.88 },
        { lower = 0.12, upper = 0.14, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.14, upper = 0.17, grade = CropValueMap.Grades.B, multiplier = 0.88 },
        { lower = 0.17, upper = 0.20, grade = CropValueMap.Grades.C, multiplier = 0.72 },
        { lower = 0.20, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.52 }
    },
    ["SORGHUM"] = {
        { lower = 0.00, upper = 0.08, grade = CropValueMap.Grades.D, multiplier = 0.67 },
        { lower = 0.08, upper = 0.10, grade = CropValueMap.Grades.C, multiplier = 0.82 },
        { lower = 0.10, upper = 0.13, grade = CropValueMap.Grades.B, multiplier = 0.93 },
        { lower = 0.13, upper = 0.14, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.14, upper = 0.16, grade = CropValueMap.Grades.B, multiplier = 0.93 },
        { lower = 0.16, upper = 0.19, grade = CropValueMap.Grades.C, multiplier = 0.82 },
        { lower = 0.19, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.67 }
    },
    ["CANOLA"] = {
        { lower = 0.00, upper = 0.04, grade = CropValueMap.Grades.D, multiplier = 0.50 },
        { lower = 0.04, upper = 0.06, grade = CropValueMap.Grades.C, multiplier = 0.72 },
        { lower = 0.06, upper = 0.08, grade = CropValueMap.Grades.B, multiplier = 0.88 },
        { lower = 0.08, upper = 0.10, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.10, upper = 0.12, grade = CropValueMap.Grades.B, multiplier = 0.88 },
        { lower = 0.12, upper = 0.15, grade = CropValueMap.Grades.C, multiplier = 0.72 },
        { lower = 0.15, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.50 }
    },
    ["SOYBEAN"] = {
        { lower = 0.00, upper = 0.08, grade = CropValueMap.Grades.D, multiplier = 0.53 },
        { lower = 0.08, upper = 0.10, grade = CropValueMap.Grades.C, multiplier = 0.74 },
        { lower = 0.10, upper = 0.13, grade = CropValueMap.Grades.B, multiplier = 0.89 },
        { lower = 0.13, upper = 0.16, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.16, upper = 0.24, grade = CropValueMap.Grades.B, multiplier = 0.89 },
        { lower = 0.24, upper = 0.27, grade = CropValueMap.Grades.C, multiplier = 0.74 },
        { lower = 0.27, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.53 }
    },
    ["SUNFLOWER"] = {
        { lower = 0.00, upper = 0.07, grade = CropValueMap.Grades.D, multiplier = 0.51 },
        { lower = 0.07, upper = 0.09, grade = CropValueMap.Grades.C, multiplier = 0.73 },
        { lower = 0.09, upper = 0.11, grade = CropValueMap.Grades.B, multiplier = 0.88 },
        { lower = 0.11, upper = 0.14, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.14, upper = 0.19, grade = CropValueMap.Grades.B, multiplier = 0.88 },
        { lower = 0.19, upper = 0.22, grade = CropValueMap.Grades.C, multiplier = 0.73 },
        { lower = 0.22, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.51 }
    },
    ["MUSTARD"] = {
        { lower = 0.00, upper = 0.04, grade = CropValueMap.Grades.D, multiplier = 0.50 },
        { lower = 0.04, upper = 0.06, grade = CropValueMap.Grades.C, multiplier = 0.72 },
        { lower = 0.06, upper = 0.08, grade = CropValueMap.Grades.B, multiplier = 0.88 },
        { lower = 0.08, upper = 0.10, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.10, upper = 0.12, grade = CropValueMap.Grades.B, multiplier = 0.88 },
        { lower = 0.12, upper = 0.15, grade = CropValueMap.Grades.C, multiplier = 0.72 },
        { lower = 0.15, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.50 }
    },
    ["POPPY"] = {
        { lower = 0.00, upper = 0.04, grade = CropValueMap.Grades.D, multiplier = 0.50 },
        { lower = 0.04, upper = 0.06, grade = CropValueMap.Grades.C, multiplier = 0.72 },
        { lower = 0.06, upper = 0.08, grade = CropValueMap.Grades.B, multiplier = 0.88 },
        { lower = 0.08, upper = 0.10, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.10, upper = 0.12, grade = CropValueMap.Grades.B, multiplier = 0.88 },
        { lower = 0.12, upper = 0.15, grade = CropValueMap.Grades.C, multiplier = 0.72 },
        { lower = 0.15, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.50 }
    },
    ["LINSEED"] = {
        { lower = 0.00, upper = 0.05, grade = CropValueMap.Grades.D, multiplier = 0.52 },
        { lower = 0.05, upper = 0.07, grade = CropValueMap.Grades.C, multiplier = 0.73 },
        { lower = 0.07, upper = 0.09, grade = CropValueMap.Grades.B, multiplier = 0.88 },
        { lower = 0.09, upper = 0.11, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.11, upper = 0.13, grade = CropValueMap.Grades.B, multiplier = 0.88 },
        { lower = 0.13, upper = 0.16, grade = CropValueMap.Grades.C, multiplier = 0.73 },
        { lower = 0.16, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.52 }
    },
    ["PEA"] = {
        { lower = 0.00, upper = 0.08, grade = CropValueMap.Grades.D, multiplier = 0.60 },
        { lower = 0.08, upper = 0.10, grade = CropValueMap.Grades.C, multiplier = 0.77 },
        { lower = 0.10, upper = 0.13, grade = CropValueMap.Grades.B, multiplier = 0.90 },
        { lower = 0.13, upper = 0.15, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.15, upper = 0.18, grade = CropValueMap.Grades.B, multiplier = 0.90 },
        { lower = 0.18, upper = 0.21, grade = CropValueMap.Grades.C, multiplier = 0.77 },
        { lower = 0.21, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.60 }
    },
    ["GREENBEAN"] = {
        { lower = 0.00, upper = 0.08, grade = CropValueMap.Grades.D, multiplier = 0.60 },
        { lower = 0.08, upper = 0.11, grade = CropValueMap.Grades.C, multiplier = 0.77 },
        { lower = 0.11, upper = 0.13, grade = CropValueMap.Grades.B, multiplier = 0.90 },
        { lower = 0.13, upper = 0.15, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.15, upper = 0.24, grade = CropValueMap.Grades.B, multiplier = 0.90 },
        { lower = 0.24, upper = 0.27, grade = CropValueMap.Grades.C, multiplier = 0.77 },
        { lower = 0.27, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.60 }
    },
    ["BEANS"] = {
        { lower = 0.00, upper = 0.08, grade = CropValueMap.Grades.D, multiplier = 0.60 },
        { lower = 0.08, upper = 0.10, grade = CropValueMap.Grades.C, multiplier = 0.77 },
        { lower = 0.10, upper = 0.13, grade = CropValueMap.Grades.B, multiplier = 0.90 },
        { lower = 0.13, upper = 0.15, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.15, upper = 0.18, grade = CropValueMap.Grades.B, multiplier = 0.90 },
        { lower = 0.18, upper = 0.21, grade = CropValueMap.Grades.C, multiplier = 0.77 },
        { lower = 0.21, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.60 }
    },
    ["BUCKWHEAT"] = {
        { lower = 0.00, upper = 0.08, grade = CropValueMap.Grades.D, multiplier = 0.68 },
        { lower = 0.08, upper = 0.10, grade = CropValueMap.Grades.C, multiplier = 0.83 },
        { lower = 0.10, upper = 0.13, grade = CropValueMap.Grades.B, multiplier = 0.93 },
        { lower = 0.13, upper = 0.14, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.14, upper = 0.16, grade = CropValueMap.Grades.B, multiplier = 0.93 },
        { lower = 0.16, upper = 0.19, grade = CropValueMap.Grades.C, multiplier = 0.83 },
        { lower = 0.19, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.68 }
    },
    ["MILLET"] = {
        { lower = 0.00, upper = 0.08, grade = CropValueMap.Grades.D, multiplier = 0.67 },
        { lower = 0.08, upper = 0.10, grade = CropValueMap.Grades.C, multiplier = 0.82 },
        { lower = 0.10, upper = 0.13, grade = CropValueMap.Grades.B, multiplier = 0.93 },
        { lower = 0.13, upper = 0.14, grade = CropValueMap.Grades.A, multiplier = 1.0 },
        { lower = 0.14, upper = 0.16, grade = CropValueMap.Grades.B, multiplier = 0.93 },
        { lower = 0.16, upper = 0.19, grade = CropValueMap.Grades.C, multiplier = 0.82 },
        { lower = 0.19, upper = 1.00, grade = CropValueMap.Grades.D, multiplier = 0.67 }
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
