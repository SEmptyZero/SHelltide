local state_machine = {}
state_machine.__index = state_machine

function state_machine.new(initial_state, states)
    local self = setmetatable({}, state_machine)
    self.states = states or {}
    self.current_state = initial_state
    self.previous_state = nil
    if self.states[initial_state] and self.states[initial_state].enter then
        self.states[initial_state].enter(self)
    end
    return self
end

function state_machine:change_state(new_state)
    if self.states[self.current_state] and self.states[self.current_state].exit then
        self.states[self.current_state].exit(self)
    end
    self.previous_state = self.current_state
    self.current_state = new_state
    if self.states[new_state] and self.states[new_state].enter then
        self.states[new_state].enter(self)
    end
end

function state_machine:get_previous_state()
    return self.previous_state
end

function state_machine:get_current_state()
    return self.current_state
end

function state_machine:update(...)
    if self.states[self.current_state] and self.states[self.current_state].execute then
        self.states[self.current_state].execute(self, ...)
    end
end

return state_machine
