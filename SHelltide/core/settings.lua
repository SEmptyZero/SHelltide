local gui = require "gui"
local settings = {
    enabled = false,
    salvage = true,
    path_angle = 20,
    open_silent_chests = false,
    return_to_origin = false,
}

function settings:update_settings()
    settings.enabled = gui.elements.main_toggle:get()
    settings.salvage = gui.elements.salvage_toggle:get()
    settings.maiden_slider_attempts = gui.elements.maiden_slider_attempts:get()
    settings.maiden_slider_minutes = gui.elements.maiden_slider_minutes:get()
    settings.open_silent_chests = gui.elements.open_silent_chests_toggle:get()
    settings.return_to_origin = gui.elements.return_to_origin_toggle:get()
    settings.maiden_enable_toggle = gui.elements.maiden_enable_toggle:get()
    settings.draw_status_offset_x = gui.elements.draw_status_offset_x:get()
    settings.draw_status_offset_y = gui.elements.draw_status_offset_y:get()
    settings.debug_toggle = gui.elements.debug_toggle:get()
end

return settings