
local term = term
local args = { ... }

--- Load a model from its textual description.
-- @param text	The textual definition of the model
-- @param name	(Optional) The name of the model, useful for debugging
-- @return The loaded model
local function parse_model( text, name )
	local fn, err = loadstring( text, name or "model" )

	if not fn then
		error( "Failed to parse model " .. tostring( name ) .. ": " .. err,   2 )
	end

	local ok, model = pcall( fn )
	if not ok then
		error( "Failed to load model "  .. tostring( name ) .. ": " .. model, 2 )
	end

	model.width  = #model.background[ 1 ]
	model.height = #model.background

	return model
end

--- Draw a model at the specified coordinates.
-- @param x description
-- @param y description
-- @param model description
-- @return nil
local function draw_model( x, y, model )
	for i = 1, model.height do
		term.setCursorPos( x, y + i )
		term.blit( model.characters[ i ], model.foreground[ i ], model.background[ i ] )
	end
end

term.clear()

---[[
local f = io.open( args[ 1 ], "r" )
local contents = f:read( "*a" )
f:close()

draw_model( 2, 2, parse_model( contents ) )
--]]

--[[
local pistol = io.open( "/assets/pistol.mdl", "r" )
local pistol_contents = pistol:read( "*a" )
pistol:close()

local scope = io.open( "/assets/scope.mdl", "r" )
local scope_contents = scope:read( "*a" )
scope:close()

pistol = parse_model( pistol_contents, "pistol" )
scope  = parse_model( scope_contents,  "scope" )

local x, y = 2, 5

draw_model( x, y, pistol )
draw_model( x + pistol.slots.sight.x - scope.mount_point.x, y + pistol.slots.sight.y - scope.mount_point.y, scope )
--]]

term.setCursorPos( 1, 1 )
