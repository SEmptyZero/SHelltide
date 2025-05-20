local enums = {
    quests = {
        pit_ongoing = 1815152,
        pit_started = 1922713
    },
    portal_names = {
        horde_portal = "Portal_Dungeon_Generic"
    },
    misc = {
        obelisk = "TWN_Kehj_IronWolves_PitKey_Crafter",
        blacksmith = "TWN_Scos_Cerrigar_Crafter_Blacksmith",
        jeweler = "TWN_Scos_Cerrigar_Vendor_Weapons",
        portal = "TownPortal"
    },
    positions = {
        obelisk_position = vec3:new(-1659.1735839844, -613.06573486328, 37.2822265625),
        blacksmith_position = vec3:new(-1685.5394287109, -596.86566162109, 37.6484375),
        jeweler_position = vec3:new(-1658.699219, -620.020508, 37.888672), 
        portal_position = vec3:new(-1656.7141113281, -598.21716308594, 36.28515625), 
        portal_door = vec3:new(28.782243728638, -479.67123413086, -24.51171875) 
    },
    chest_types = {
        [0] = "BSK_UniqueOpChest_Gear",
        [1] = "BSK_UniqueOpChest_Materials",
        [2] = "BSK_UniqueOpChest_Gold",
        [3] = "BSK_UniqueOpChest_GreaterAffix"
    },
    chest_types = {
        GEAR = "BSK_UniqueOpChest_Gear",
        MATERIALS = "BSK_UniqueOpChest_Materials",
        GOLD = "BSK_UniqueOpChest_Gold",
        GREATER_AFFIX = "BSK_UniqueOpChest_GreaterAffix"
    },
    waypoints = {
        CERRIGAR = 0x76D58,
        LIBRARY = 0x10D63D
    },

    helltide_tps = {
        {name = {"Frac_Tundra_S", "Frac_Kyovashad", "Frac_Tundra_N", "Frac_Glacier"}, id = 0xACE9B, file = "menestad"},
        {name = {"Scos_Coast", "Scos_Deep_Forest"}, id = 0x27E01, file = "marowen"},
        {name = {"Kehj_Oasis", "Kehj_Caldeum", "Kehj_HighDesert","Kehj_LowDesert", "Kehj_Gea_Kul"}, id = 0xDEAFC, file = "ironwolfs"},
        {name = {"Hawe_Verge","Hawe_Wetland","Hawe_ZakFort","Hawe_Zarbinzet"}, id = 0x9346B, file = "wejinhani"},
        {name = {"Step_South","Step_Central","Step_Volcano"}, id = 0x462E2, file = "jirandai"},
    },

    maiden_positions = {
        menestad  = { vec3:new(-1517.776733, -20.840151, 105.299805) },
        marowen   = { 
            vec3:new(-1982.549438, -1143.823364, 12.758240),
            vec3:new(-1300.192382, -998.390625, 47.619140)
        },
        ironwolfs = {
            vec3:new(120.874367, -746.962341, 7.089052),
            vec3:new(489.066406, -383.588867, 5.976328),
        },
        jirandai  = { vec3:new(-464.924530, -327.773132, 36.178608) },
        wejinhani = { vec3:new(-1070.214600, 449.095276, 16.321373),
                      vec3:new(-679.525390, 725.866210, 0.389648),
        },
    }, 

    helltide_chests_info = {
        usz_rewardGizmo_1H = 150,  --125?
        usz_rewardGizmo_2H = 150,  
        usz_rewardGizmo_ChestArmor = 75, 
        usz_rewardGizmo_Rings = 125,     
        usz_rewardGizmo_infernalsteel = 250,  
        usz_rewardGizmo_Uber = 250,      
        usz_rewardGizmo_Amulet = 150,    
        usz_rewardGizmo_Gloves = 75,          
        usz_rewardGizmo_Legs = 75,            
        usz_rewardGizmo_Boots = 75,           
        usz_rewardGizmo_Helm = 75,             
        Helltide_RewardChest_Random = 75,
    },
}

return enums