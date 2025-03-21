local gui = {}
local version = "v1.1.7b"
local plugin_label = "s_helltide"
local author = "EmptyZero"

local function create_checkbox(value, key)
    return checkbox:new(value, get_hash(plugin_label .. "_" .. key))
end

local function create_slider_int(min, max, default, key)
    return slider_int:new(min, max, default, get_hash(plugin_label .. "_" .. key))
end

gui.elements = {
    main_tree = tree_node:new(0),
    main_toggle = create_checkbox(false, "main_toggle"),
    debug_toggle = create_checkbox(false, "debug_toggle"),

    draw_status_settings_tree = tree_node:new(1),
    draw_status_offset_x = create_slider_int(0, 2000, 0, "draw_status_offset_x"),
    draw_status_offset_y = create_slider_int(0, 2000, 100, "draw_status_offset_y"),
    
    alfred_settings_tree = tree_node:new(2),
    salvage_toggle = create_checkbox(true, plugin_label .. "salvage_toggle"),
    
    maiden_settings_tree = tree_node:new(3),
    maiden_return_to_origin_toggle = create_checkbox(false, "maiden_return_to_origin_toggle"),
    maiden_slider_maiden_time = create_slider_int(1, 60, 30, "maiden_slider_maiden_time"),
    maiden_slider_helltide_chests_time = create_slider_int(1, 60, 30, "maiden_slider_helltide_chests_time"),
    maiden_enable_first_maiden_toggle = create_checkbox(false, "maiden_enable_first_maiden_toggle"),
    --maiden_enable_toggle = create_checkbox(false, "maiden_enable_toggle"),
    
    chests_settings_tree = tree_node:new(4),
    return_to_origin_toggle = create_checkbox(false, "return_to_origin"),
    open_silent_chests_toggle = create_checkbox(false, "open_silent_chests")
}

function gui.draw_status(current_task)
    local messages = {
        {
            text = "Helltide Remaining      : " .. current_task:get_helltide_time_remaining(),
            color = color_white(255)
        },
        { 
            text = "Next Helltide In        : " .. current_task:get_next_helltide_msg(), 
            color = color_white(255) 
        },
        { 
            text = "Current Task            : " .. current_task.sm:get_current_state(), 
            color = color_white(255) 
        },
        { 
            text = "Maiden Farm Time Remain : " .. current_task:get_next_chests_msg(), 
            color = color_white(255)
        },
        { 
            text = "Chests Farm Time Remain : " .. current_task:get_next_maiden_msg(), 
            color = color_white(255)
        },
        { 
            text = "Opened Chests           : " .. current_task:get_chests_opened_msg(), 
            color = color_white(255)
        },
        { 
            text = "Missed Chests           : " .. current_task:get_missed_chests_msg(), 
            color = color_white(255)
        }
    }
    
    local x_pos = 8 + gui.elements.draw_status_offset_x:get()
    local y_pos = 50 + gui.elements.draw_status_offset_y:get()
    
    for _, msg in pairs(messages) do
        graphics.text_2d(msg.text, vec2:new(x_pos, y_pos), 17, msg.color)
        y_pos = y_pos + 20
    end
end

function gui.render()
    if not gui.elements.main_tree:push("S Helltide | " .. author .. " | " .. version) then return end

    gui.elements.main_toggle:render("Enable", "Enable the bot")
    gui.elements.maiden_enable_first_maiden_toggle:render("Start rotation from the Maiden", "If enabled, it will start by farming the Maiden (you need at least 3 hearts)")
    --gui.elements.debug_toggle:render("Enable Debug", "Enable debug mode")

    -- Menu Status
    if gui.elements.draw_status_settings_tree:push("Info / Status - Settings") then
        gui.elements.draw_status_offset_x:render("In-Game Offset X","Modify the in-game Info/Status GUI position for the X-axis")
        gui.elements.draw_status_offset_y:render("In-Game Offset Y","Modify the in-game Info/Status GUI position for the Y-axis")
        gui.elements.draw_status_settings_tree:pop()
    end

    -- Menu Alfred - Settings con Salvage
    if gui.elements.alfred_settings_tree:push("Alfred - Settings") then
        gui.elements.salvage_toggle:render("Salvage with alfred", "Enable salvaging items with Alfred")
        gui.elements.alfred_settings_tree:pop()
    end

    -- Menu Maiden - Settings con slider
    if gui.elements.maiden_settings_tree:push("Maiden - Settings") then
        --gui.elements.maiden_enable_toggle:render("Enable Maiden", "Enable the Maiden")
        gui.elements.maiden_return_to_origin_toggle:render("Backtracking to point before trigger", "Return to the point before the trigger")
        gui.elements.maiden_slider_maiden_time:render("Time Maiden", "For how long should it stay farming the maiden")
        gui.elements.maiden_slider_helltide_chests_time:render("Time Chest", "For how long should it stay farming the chests")

        gui.elements.maiden_settings_tree:pop()
    end

    -- Menu Chests - Settings con la nuova checkbox
    if gui.elements.chests_settings_tree:push("Chests - Settings") then
        render_menu_header("WARNING: You need the Whispering Keys,\notherwise the chests will be ignored")
        gui.elements.open_silent_chests_toggle:render("Open Silent Chests", "If enabled, Silent Chests are attempted to be opened during exploration state")
        gui.elements.return_to_origin_toggle:render("Backtracking to point before trigger", "Returns the player to the point of origin after attempting to open a previously visited chest")
        gui.elements.chests_settings_tree:pop()
    end

    gui.elements.main_tree:pop()
end

return gui
