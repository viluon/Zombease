
-- [SublimeLinter luacheck-globals:term,colours,textutils,keys,blittle,shell,sleep,fs,http]

-- Zombease - a top-down zombie survival shooter by viluon

if not term.isColour or not term.isColour() then
	error( "Zombease requires an advanced computer!", 0 )
end

if not fs.exists "blittle" then shell.run "pastebin get ujchRSnU blittle" end
os.loadAPI "blittle"
local blittle = blittle

if not require then shell.run "/desktox/init.lua" end

local args = { ... }

local base64 = require "utils.base64"
local buffer = require "desktox.buffer"
local round  = require( "desktox.utils" ).round

local SNOWFLAKE_SPAWN_RATE = 0.05
local SETTINGS_SAVE_PERIOD = 5
local MENU_ANIM_DURATION = 0.5
local MENU_WIDTH = 15

local	redraw, shade, update, ease_in_quad,
		ease_out_quad, change_menu, parse_model,
		draw_model, save_settings, align_number,
		get_paste

local version = "0.1.3-beta"
local root = "/"

local colours = colours
local string = string
local shell = shell
local table = table
local term = term
local math = math

local remove = table.remove
local random = math.random
local sleep = sleep
local clock = os.clock
local queue = os.queueEvent
local floor = math.floor
local gsub = string.gsub
local min = math.min
local max = math.max

local now
local running = true
local launch = false
local perform_update = false

if not fs.exists( root .. "tmp/logo_dec" ) then
	-- Decode the logo
	local logo_enc = io.open( root .. "assets/little_images/logo_mix.b64", "r" )
	local logo_data = logo_enc:read( "*a" )
	logo_enc:close()

	local logo_dec = io.open( root .. "tmp/logo_dec", "wb" )
	local data = base64.decode( logo_data )

	local x, y = term.getCursorPos()
	for i = 1, #data do
		logo_dec:write( data:sub( i, i ):byte() )
		term.setCursorPos( x, y )
		term.write( round( 100 * i / #data ) .. "%" )

		if i % 16 == 0 then
			sleep( 0 )
		end
	end

	logo_dec:close()
end

local logo = blittle.load( root .. "tmp/logo_dec" )

local main_win = term.current()

local w, h = main_win.getSize()

local main_buf    = buffer.new( 0, 0, w, h, nil, colours.black )
local overlay_buf = buffer.new( 0, 0, w, h, main_buf, -1, -2, "\0" )
local armoury_buf = buffer.new( 0, logo.height, w, h - logo.height, main_buf )

local wave_win = main_buf:get_window_interface( main_win )
wave_win.setVisible( true )

local stuff = ""

local particles = {}
local symbols = {
	"\127", "*",
}

local settings = {
	show_version = true;
	snowflakes = 0;
	limit_FPS = true;
}

local settings_file = io.open( root .. "saves/settings.tbl", "r" )
if settings_file then
	local contents = settings_file:read( "*a" )

	-- Import from save
	for k, v in pairs( textutils.unserialise( contents ) or settings ) do
		settings[ k ] = v
	end

	settings_file:close()
end

local menu = {
	main = {
		[ 1 ] = {
			label = "Play";
			fn = function( _ )
				change_menu( "play" )
			end;
		};
		[ 2 ] = {
			label = "Armoury";
			fn = function( _ )
				change_menu( "armoury" )
			end;
		};
		[ 3 ] = {
			label = "Settings";
			fn = function( _ )
				change_menu( "settings" )
			end;
		};
		[ 4 ] = {
			label = "Quit";
			fn = function( _ )
				running = false
			end;
		};
	};

	play = {
		[ 1 ] = {
			label = "Endless";
			fn = function( _ )
				launch = true
				running = false
			end;
		};
		[ 2 ] = {
			label = "Back";
			fn = function( _ )
				change_menu( "main" )
			end;
		};
	};

	armoury = {};

	settings = {
		[ 1 ] = {
			label = settings.show_version and "Version: shown" or "Version: hidden";
			fn = function( self )
				settings.show_version = not settings.show_version
				self.label = settings.show_version and "Version: shown" or "Version: hidden"
				save_settings()
			end;
		};
		[ 2 ] = {
			label = settings.limit_FPS and "FPS limit: on" or "FPS limit: off";
			fn = function( self )
				settings.limit_FPS = not settings.limit_FPS
				self.label = settings.limit_FPS and "FPS limit: on" or "FPS limit: off";
				save_settings()
			end;
		};
		[ 3 ] = {
			label = "Back";
			fn = function( _ )
				change_menu( "main" )
			end;
		};
	};
}

local menu_pos_x = 7
local menu_pos_y = 5
local model_offset_x = 0
local model_offset_y = 0
local selected_weapon = 1
local armoury_position = logo.height + 1
local armoury_back_button = {
	label = "< Back";
}

local menu_state = "main"
local new_state  = menu_state
local menu_changed = -1
local menu_label_start = 1
local menu_label_end = math.huge

local inventory
local models = {}
local weapons = {}
local weapon_kinds = {}
local bullet_kinds = {}
local attachment_kinds = {}

local last_spawn = -1

local fade_level = 2

local fade_shader = {
	[ colours.grey ] = colours.black;
	[ colours.lightGrey ] = colours.grey;
	[ colours.white ] = colours.lightGrey;
	[ colours.yellow ] = colours.white;
	[ colours.green ] = colours.lightGrey;
	[ colours.red ] = colours.pink;
	[ colours.pink ] = colours.lightGrey;
}

local shader = fade_shader

-- Adapted from
-- Tweener's easing functions (Penner's Easing Equations)
-- and http://code.google.com/p/tweener/ (jstweener javascript version)
function ease_in_quad( time, begin, change, duration )
	if time > duration then
		return begin + change
	end

	time = time / duration
	return -change * time * ( time - 2 ) + begin
end

function ease_out_quad( time, begin, change, duration )
	if time > duration then
		return begin + change
	end

	time = time / duration
	return change * time ^ 1.5 + begin
end

--- Get the contents of a Pastebin paste.
-- @param code description
-- @return The paste contents or nil plus an error message
function get_paste( code )
	local response, err = http.get(
		"http://pastebin.com/raw/" .. textutils.urlEncode( code )
	)

	if response then
		local contents = response.readAll()
		response.close()
		return contents
	end

	return nil, err
end

--- Load a model from its textual description.
-- @param text	The textual definition of the model
-- @param name	(Optional) The name of the model, useful for debugging
-- @return The loaded model
function parse_model( text, name )
	local fn, err = loadstring( text, name or "model" )

	if not fn then
		error( "Failed to parse model " .. tostring( name ) .. ": " .. err,   2 )
	end

	local ok, model = pcall( fn )
	if not ok then
		error( "Failed to load model "  .. tostring( name ) .. ": " .. model, 2 )
	end

	-- Process "unknown" colours
	for i, str in ipairs( model.background ) do
		model.background[ i ] = gsub( str, " ", "g" )
	end
	for i, str in ipairs( model.foreground ) do
		model.foreground[ i ] = gsub( str, " ", "h" )
	end

	model.width  = #model.background[ 1 ]
	model.height = #model.background

	return model
end

--- Align a nuber on a line to a specified column
-- @param str description
-- @param column description
-- @param number description
-- @return The string for the resultant row
function align_number( str, column, number )
	return str .. string.rep( " ", column - #str ) .. number
end

--- Draw a model to the screen.
-- @param model	The model to draw duh
-- @return nil
function draw_model( model, x, y, buf )
	y = y - 1

	local characters = model.characters
	local background = model.background
	local foreground = model.foreground

	-- Go through all the lines, blitting the model's texture
	for i = 1, model.height do
		-- A -1 for i is included in the y definition above
		buf:blit( x, y + i, characters[ i ], background[ i ], foreground[ i ] )
	end
end

--- Save the current settings.
-- @return nil
function save_settings()
	local file = io.open( root .. "saves/settings.tbl", "w" )
	file:write( textutils.serialise( settings ) )
	file:close()
end

--- Change the menu state.
-- @param state The state to be applied
-- @return nil
function change_menu( state )
	menu_changed = now
	new_state = state
end

--- Apply the current shader on a buffer.
-- @see desktox.buffer:map
function shade( _, _, _, pixel )
	return {
		shader[ pixel[ 1 ] ] or colours.black,
		shader[ pixel[ 2 ] ] or colours.black,
		pixel[ 3 ],
	}
end

--- Redraw the GUI.
-- @return nil
function redraw()
	main_buf:clear( colours.white, colours.white )
	overlay_buf:clear( -1, -2, "\0" )

	-- Draw the menu items
	for i, item in ipairs( menu[ menu_state ] ) do
		local label = item.label
		local start = round( menu_label_start )
		local str   = label:sub( start, min( #label, menu_label_end ) )

		main_buf:write( menu_pos_x + start, menu_pos_y + i, str )
	end

	if settings.show_version then
		-- Print the version information
		main_buf:write( w - #version, h - 1, version, nil, colours.lightGrey )
	end

	-- Overlay
	--- Particles
	for i = 1, #particles do
		local particle = particles[ i ]
		overlay_buf:write( round( particle.x ), round( particle.y ), particle.symbol, particle.bg or -1, particle.fg or -2 )
	end

	overlay_buf:render()

	-- Draw the game logo
	blittle.draw( logo, 2, 1, wave_win )

	if menu_state == "armoury" or new_state == "armoury" then
		armoury_buf:clear( -1, -2, "\0" )

		if inventory then
			local weapon = inventory.weapons[ selected_weapon ]
			-- Draw the selected model
			draw_model(
				models[ weapon.kind.name ],
				round( 3 + model_offset_x ),
				round( 2 + model_offset_y ),
				armoury_buf
			)

			for index, weap in ipairs( inventory.weapons ) do
				if index == selected_weapon then
					armoury_buf:write( ( index - 1 ) * 3, h - logo.height - 1, "[ ]", colours.white, colours.black )
				end

				armoury_buf:write( ( index - 1 ) * 3 + 1, h - logo.height - 1, weap.kind.text, colours.white, colours.grey )
			end

			local infobox_x = round( ( 2 / 3 ) * w ) - 1

			-- Print weapon info
			local damage = bullet_kinds[ weapon.kind.bullet_kind ].damage
			local col = w - infobox_x - 5

			armoury_buf
				:draw_filled_rectangle_from_points(
					infobox_x, 0, w - 1, h - logo.height - 1, colours.grey
				)
				:write( infobox_x + 1, 1, weapon.kind.name, colours.grey, colours.white )
				:write( infobox_x + 1, 2, weapon.kind.melee and "Melee weapon" or "Ranged weapon", colours.grey, colours.white )

				:write( infobox_x + 1, 4, align_number( "Damage", col, damage ), colours.grey, colours.white )
				:write( infobox_x + 1, 5, align_number( "Cooldown", col, weapon.kind.cooldown ), colours.grey, colours.white )
				:write( infobox_x + 1, 6, align_number( "DPS", col, damage / weapon.kind.cooldown ), colours.grey, colours.white )
				:write(
					infobox_x + 1, 7,
					align_number( "Accuracy", col, round( weapon.kind.accuracy * 100 ) .. "%" ),
					colours.grey, colours.white
				)
				:write(
					infobox_x + 1, 8,
					align_number( "Knockback", col, floor( bullet_kinds[ weapon.kind.bullet_kind ].knockback ) ),
					colours.grey, colours.white
				)
				:write(
					infobox_x + 2, 9,
					"(" .. ( bullet_kinds[ weapon.kind.bullet_kind ].knockback % 1 ) * 100 .. "% chance)",
					colours.grey, colours.white
				)
				:write(
					infobox_x + 1, 10,
					align_number( "Clip size", col, weapon.kind.clip_size or "none" ),
					colours.grey, colours.white
				)
				:write(
					infobox_x + 1, 11,
					align_number( "Bullets", col, inventory.ammunition[ weapon.kind.bullet_kind ] ),
					colours.grey, colours.white
				)
		else
			local text = "Get some items in-game first!"
			armoury_buf:write( w / 2 - #text / 2, 4, text )
		end

		armoury_buf:write( 0, 0, armoury_back_button.label )

		armoury_buf:render( main_buf, 0, round( armoury_position ) )

	else
		-- Draw the player
		main_buf:write( w - 14, h - 7, "^", colours.brown, colours.grey )
	end

	-- Apply the proper fade effect
	for _ = 1, fade_level do
		main_buf:map( shade )
	end

	main_buf:write( 0, h - 1, stuff )

	main_buf:render_to_window( main_win )
end

--- Update particle effects and whatnot.
-- @param dt Time since last update
-- @return nil
function update( dt )
	-- Spawn new particles
	if now - last_spawn > SNOWFLAKE_SPAWN_RATE then
		for _ = 1, 2 do
			particles[ #particles + 1 ] = {
				x = random( ( 1 / 6 ) * w, ( 7 / 6 ) * w );
				y = -1;

				x_speed = random() > 0.1 and -12 or -8;
				y_speed = 18;

				symbol  = symbols[ random( 1, #symbols ) ];

				fg = random() > 0.05 and colours.lightGrey or colours.grey;
				bg = colours.white;
			}
		end

		last_spawn = now
	end

	local to_destroy = {}

	-- Update particles
	for i = 1, #particles do
		local particle = particles[ i ]

		particle.x = particle.x + particle.x_speed * dt
		particle.y = particle.y + particle.y_speed * dt

		if particle.x < 0 or particle.x >= ( 4 / 3 ) * w or particle.y < -1 or particle.y >= h then
			to_destroy[ #to_destroy + 1 ] = particle
			settings.snowflakes = settings.snowflakes + 1
		end
	end

	-- Remove particles that went off-screen
	for i = 1, #to_destroy do
		local p = to_destroy[ i ]

		for ii = 1, #particles do
			if particles[ ii ] == p then
				remove( particles, ii )
				break
			end
		end
	end

	-- Animate menu changes
	if new_state ~= menu_state then
		menu_label_end = math.huge
		menu_label_start = ease_in_quad( now - menu_changed, 1, MENU_WIDTH - 1, MENU_ANIM_DURATION )

		if menu_label_start == MENU_WIDTH then
			menu_state = new_state
		end

		if new_state == "armoury" then
			-- Armoury should fly in
			armoury_position = ease_in_quad ( now - menu_changed, h, -h + logo.height, MENU_ANIM_DURATION )

		elseif menu_state == "armoury" then
			-- Armoury should fly out
			armoury_position = ease_out_quad( now - menu_changed, logo.height, h - logo.height, MENU_ANIM_DURATION )
		end
	else
		menu_label_start = 1
		menu_label_end   = ease_in_quad( now - menu_changed - MENU_ANIM_DURATION, 1, MENU_WIDTH - 1, MENU_ANIM_DURATION )
	end
end

-- Execution code
--- Process commandline arguments
local last_setter
local arguments = {}

for i = 1, #args do
	local arg = args[ i ]

	if type( arg ) == "string" then
		if arg:find( "^%-" ) then
			last_setter = arg:gsub( "^%-%-?", "" )
			arguments[ last_setter ] = true
		else
			if last_setter then
				if type( arguments[ last_setter ] ) ~= "table" then
					arguments[ last_setter ] = {}
				end

				arguments[ last_setter ][ #arguments[ last_setter ] + 1 ] = arg
			end
		end
	end
end

--- Display the Yellowave signature (either variation #7 or #1)
if not arguments[ "no-intro" ] then
	term.redirect( wave_win )

	shell.run( "yellowave.lua", random() > 0.25 and 7 or 1 )

	sleep( 1 )

	for _ = 1, 3 do
		main_buf:map( shade )
		main_buf:render_to_window( main_win, 1, 1 )
		sleep( 0 )
		sleep( 0 )
	end

	term.redirect( main_win )
end

wave_win.setVisible( false )

if arguments.menu and type( arguments.menu ) == "table" then
	local value = arguments.menu[ 1 ]

	if menu[ value ] then
		menu_state = value
		new_state = value
	end
end

--- Load assets
local model_dir = root .. "assets/models/"
local weapon_dir = root .. "assets/weapons/"

for _, name in ipairs( fs.list( weapon_dir ) ) do
	local f = io.open( weapon_dir .. name, "r" )

	name = name:gsub( "%.tbl", "" )

	if f then
		local contents = f:read( "*a" )
		f:close()

		local fn = loadstring( contents, name )
		if fn then
			setfenv( fn, { colours = colours; [ "colors" ] = colours } )
			local ok, result = pcall( fn )

			if ok then
				local model_file = io.open( model_dir .. result.model, "r" )

				if model_file then
					local model = model_file:read( "*a" )

					models[ name ] = parse_model( model, model_dir .. result.model )
					weapon_kinds[ name ] = result
					weapons[ name ] = {
						kind = result;
					}
				else
					error( "Model file " .. model_dir .. result.model .. " not found" )
				end
			else
				error( "Loading asset " .. weapon_dir .. name .. " failed:\n\t" .. result )
			end
		end
	end
end

--- Load bullet kinds
local bullet_dir = root .. "assets/bullets/"
for _, name in ipairs( fs.list( bullet_dir ) ) do
	local f = io.open( bullet_dir .. name, "r" )

	name = name:gsub( "%.tbl", "" )

	if f then
		local contents = f:read( "*a" )
		f:close()

		local fn = loadstring( contents, name )
		if fn then
			setfenv( fn, { colours = colours; [ "colors" ] = colours } )
			local ok, result = pcall( fn )

			if ok then
				bullet_kinds[ name ] = result
			else
				error( "Loading asset " .. bullet_dir .. name .. " failed:\n\t" .. result )
			end
		end
	end
end

--- Load attachment kinds
local attachments_dir = root .. "assets/attachments/"
for _, name in ipairs( fs.list( attachments_dir ) ) do
	local f = io.open( attachments_dir .. name, "r" )

	name = name:gsub( "%.tbl", "" )

	if f then
		local contents = f:read( "*a" )
		f:close()

		local fn = loadstring( contents, name )
		if fn then
			setfenv( fn, { colours = colours; [ "colors" ] = colours } )
			local ok, result = pcall( fn )

			if ok then
				attachment_kinds[ name ] = result
			else
				error( "Loading asset " .. attachments_dir .. name .. " failed:\n\t" .. result )
			end
		end
	end
end

--- Load player state
local save_file = io.open( root .. "saves/unnamed.tbl", "r" )
if save_file then
	local contents = save_file:read( "*a" )

	inventory = textutils.unserialise( contents )

	if inventory then
		-- Link the items to their kinds
		for i, item in ipairs( inventory.weapons ) do
			for name, weapon in pairs( weapons ) do
				if name == item then
					inventory.weapons[ i ] = weapon
					break
				end
			end
		end
	end

	save_file:close()
end

--- Run the main GUI loop
local end_queued
now = clock()
local last_time = now
local start_time = now

local last_settings_save = -1

local start_drag_x = 0
local start_drag_y = 0

while running do
	if not end_queued then
		queue "end"
		end_queued = true
	end

	local ev = { coroutine.yield() }

	now = clock()
	local dt = now - last_time

	fade_level = 8 - 8 * ( now - start_time )

	if ev[ 1 ] == "end" then
		end_queued = false

	elseif ev[ 1 ] == "terminate" then
		running = false

	elseif ev[ 1 ] == "mouse_click" then
		start_drag_x = ev[ 3 ]
		start_drag_y = ev[ 4 ]

	elseif ev[ 1 ] == "mouse_drag" then
		-- Mouse on drags
		if menu_state == "armoury" then
			model_offset_x = model_offset_x + ev[ 3 ] - start_drag_x
			model_offset_y = model_offset_y + ev[ 4 ] - start_drag_y
		end

		start_drag_x = ev[ 3 ]
		start_drag_y = ev[ 4 ]

	elseif ev[ 1 ] == "mouse_up" then
		local x = ev[ 3 ] - 1
		local y = ev[ 4 ] - 1

		if menu_state == "armoury" then
			if y == armoury_position and x < #armoury_back_button.label then
				change_menu( "main" )
			end

		elseif x >= menu_pos_x and x <= menu_pos_x + MENU_WIDTH and y >= menu_pos_y and y <= menu_pos_y + #menu[ menu_state ] then
			local index = y - 5

			if  menu[ menu_state ][ index ] then
				menu[ menu_state ][ index ].fn( menu[ menu_state ][ index ] )
			end

		elseif settings.show_version and y == h - 1 and x >= w - #version then
			running = false
			perform_update = true
		end

	elseif ev[ 1 ] == "mouse_scroll" then
		if menu_state == "armoury" then
			selected_weapon = min( max( selected_weapon + ev[ 2 ], 1 ), #inventory.weapons )
			model_offset_x = 0
			model_offset_y = 0
		end

	elseif ev[ 1 ] == "char" then
		if ev[ 2 ] == "q" then
			running = false
		end

	elseif ev[ 1 ] == "key" then
		if ev[ 2 ] == keys.enter then
			if  menu[ menu_state ][ 1 ] then
				menu[ menu_state ][ 1 ].fn( menu[ menu_state ][ 1 ] )
			end
		end
	end

	if now - last_settings_save > SETTINGS_SAVE_PERIOD then
		-- Save the settings
		save_settings()
		last_settings_save = now
	end

	if not settings.limit_FPS or dt ~= 0 then
		update( dt )
		redraw()

		last_time = now
	end
end

queue "clean_up"
os.pullEvent "clean_up"

save_settings()

for i = 0, 6 do
	fade_level = i

	sleep ( 0 )
	update( 0.15 )
	redraw()
end

sleep( 0.1 )

if launch then
	local f = io.open( root .. "main.lua", "r" )
	local contents = f:read( "*a" )
	f:close()

	local fn = loadstring( contents, root .. "main.lua" )
	setfenv( fn, _G )

	return fn( settings )

elseif perform_update then
	term.setCursorPos( 1, 1 )

	local fn = load( get_paste "SNnkfxnx", "installer", "t", _G )
	fn( "update", "no-msg" )

	return shell.run( root .. "menu.lua", "--no-intro", "--menu", menu_state )
end
