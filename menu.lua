
-- luacheck:globals term colours textutils keys blittle shell sleep fs http peripheral

-- Zombease - a top-down zombie survival shooter by viluon

-- Environment set up
if not term.isColour or not term.isColour() then
	error( "Zombease requires an advanced computer!", 0 )
end

local root = "/" .. fs.getDir( shell.getRunningProgram() ) .. "/"

if not fs.exists( root .. "blittle" ) then
	shell.run( "pastebin get ujchRSnU " .. root .. "blittle" )
end

os.loadAPI( root .. "blittle" )
local blittle = blittle

if not require then shell.run( root .. "desktox/init.lua" ) end

_G.require = require

local args = { ... }

-- Dependencies
local base64 = require "utils.base64"
local buffer = require "desktox.buffer"
local round  = require( "desktox.utils" ).round

-- Constants
--- How many seconds between wind howls
local WIND_HOWL_PERIOD = 20
--- How long should one howl last
local WIND_HOWL_DURATION = 5
--- How long should the wind be speeding up/slowing down
local WIND_HOWL_TRANSITION = 2
local WIND_MAX_SPEED = -35
local WIND_MIN_SPEED = -8

local SNOWFLAKE_SPAWN_RATE = 0.05
local SETTINGS_SAVE_PERIOD = 5
local MENU_ANIM_DURATION = 0.5
local START_MENU_POS_Y = 5

local REQUIRED_MIN_SCREEN_WIDTH = 30
local REQUIRED_MIN_SCREEN_HEIGHT = 15

-- Function declarations
local	redraw, shade, update, ease_in_quad,
		ease_out_quad, change_menu, parse_model,
		draw_model, save_settings, align_number,
		get_paste, populate_resolution_menu,
		move_player
local empty_func = function() end

local version = "0.2.2-beta"

-- Localisation
local colours = colours
local string = string
local shell = shell
local table = table
local term = term
local math = math

local remove = table.remove
local insert = table.insert
local random = math.random
local yield = coroutine.yield
local queue = os.queueEvent
local clock = os.clock
local sleep = sleep
local floor = math.floor
local gsub = string.gsub
local sub = string.sub
local min = math.min
local max = math.max
local sin = math.sin

-- Data
local now
local running = true
local launch = false
local perform_update = false

--- Held keys and buttons
local held = { mouse = {} }

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

--- Terminal set up
local main_win = term.current()

local w, h = main_win.getSize()

if w < REQUIRED_MIN_SCREEN_WIDTH or h < REQUIRED_MIN_SCREEN_HEIGHT then
	print(
		"We're sorry, Zombease requires a resolution of at least " .. REQUIRED_MIN_SCREEN_WIDTH .. "x" .. REQUIRED_MIN_SCREEN_HEIGHT
	)

	return
end

local main_buf    = buffer.new( 0, 0, w, h, nil, colours.black )
local overlay_buf = buffer.new( 0, 0, w, h, main_buf, -1, -2, "\0" )
local armoury_buf = buffer.new( 0, logo.height, w, h - logo.height, main_buf )

local wave_win = main_buf:get_window_interface( main_win )
wave_win.setVisible( true )

local stuff = ""

local wind_howling = false
local last_wind_howl_start = clock()
local wind_speed = WIND_MIN_SPEED
local particles = {}
local symbols = {
	"\127", "*",
}

-- The terminal the game should use
local terminal = main_win
local terminal_scale = 1

local settings = {
	show_version = true;
	snowflakes = 0;
	limit_FPS = true;
	difficulty = 2;
	report_performance = true;

	keybindings = {
		up = keys.w;
		down = keys.s;
		left = keys.a;
		right = keys.d;
	}
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

local player = {
	x = round( ( 9 / 12 ) * w );
	y = round( ( 8 / 12 ) * h );

	type = "player";

	text = "^";
	bg = colours.brown;
	fg = colours.black;

	health = 100;
	last_moved = -1;
	movement_speed = 0.1;

	reload_time_multiplier = 1;

	-- New save inventory (what you begin with)
	inventory = {
		ammunition = {
			generic = 4;
		};

		weapons = {
			--weapons.fists,
		};

		attachments = {

		};
	};
}

local menu
menu = {
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
		[ 4 ] = {};
		[ 5 ] = {
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
		[ 2 ] = {};
		[ 3 ] = {
			label = "Back";
			fn = function( _ )
				change_menu( "main" )
			end;
		};
	};

	armoury = {};

	settings = {
		[ 1 ] = {
			label = "Difficulty";
			fn = function( _ )
				change_menu( "settings_difficulty" )
			end;
		};
		[ 2 ] = {
			label = "Display";
			fn = function( _ )
				change_menu( "settings_display" )
			end;
		};
		[ 3 ] = {
			label = settings.report_performance and "Tech stats: on" or "Tech stats: off";
			fn = function( self )
				settings.report_performance = not settings.report_performance
				self.label = settings.report_performance and "Tech stats: on" or "Tech stats: off";
				save_settings()
			end;
		};
		[ 4 ] = {
			label = settings.show_version and "Version: shown" or "Version: hidden";
			fn = function( self )
				settings.show_version = not settings.show_version
				self.label = settings.show_version and "Version: shown" or "Version: hidden"
				save_settings()
			end;
		};
		[ 5 ] = {
			label = "Debug menu";
			fn = function( _ )
				change_menu( "debug" )
			end;
		};
		[ 6 ] = {};
		[ 7 ] = {
			label = "Back";
			fn = function( _ )
				change_menu( "main" )
			end;
		};
	};

	settings_difficulty = {
		[ 1 ] = {
			label = ( settings.difficulty == 1 and ">" or " " ) .. " Easy";
			unselected = "  Easy";

			fn = function( self )
				settings.difficulty = 1

				for i = 1, #menu.settings_difficulty - 2 do
					menu.settings_difficulty[ i ].label = menu.settings_difficulty[ i ].unselected
				end

				self.label = "> Easy"
			end;
		};
		[ 2 ] = {
			label = ( settings.difficulty == 2 and ">" or " " ) .. " Normal";
			unselected = "  Normal";

			fn = function( self )
				settings.difficulty = 2

				for i = 1, #menu.settings_difficulty - 2 do
					menu.settings_difficulty[ i ].label = menu.settings_difficulty[ i ].unselected
				end

				self.label = "> Normal"
			end;
		};
		[ 3 ] = {
			label = ( settings.difficulty == 3 and ">" or " " ) .. " Hard";
			unselected = "  Hard";

			fn = function( self )
				settings.difficulty = 3

				for i = 1, #menu.settings_difficulty - 2 do
					menu.settings_difficulty[ i ].label = menu.settings_difficulty[ i ].unselected
				end

				self.label = "> Hard"
			end;
		};
		[ 4 ] = {};
		[ 5 ] = {
			label = "Back";
			fn = function( _ )
				change_menu( "settings" )
			end;
		};
	};

	settings_display = {
		[ 1 ] = {
			label = "Resolution";
			fn = function( _ )
				change_menu( "resolution" )
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
		[ 3 ] = {};
		[ 4 ] = {
			label = "Back";
			fn = function( _ )
				change_menu( "settings" )
			end;
		};
	};

	resolution = {
		[ 1 ] = {};
		[ 2 ] = {
			label = "Back";
			fn = function( _ )
				change_menu( "settings_display" )
			end;
		};
	};

	debug = {
		{ label = "foo 01"; fun = empty_func; };
		{ label = "foo 02"; fun = empty_func; };
		{ label = "foo 03"; fun = empty_func; };
		{ label = "foo 04"; fun = empty_func; };
		{ label = "foo 05"; fun = empty_func; };
		{ label = "foo 06"; fun = empty_func; };
		{ label = "foo 07"; fun = empty_func; };
		{ label = "foo 08"; fun = empty_func; };
		{ label = "foo 09"; fun = empty_func; };
		{ label = "foo 10"; fun = empty_func; };
		{ label = "foo 11"; fun = empty_func; };
		{ label = "foo 12"; fun = empty_func; };
		{ label = "foo 13"; fun = empty_func; };
		{ label = "foo 14"; fun = empty_func; };
		{ label = "foo 15"; fun = empty_func; };
		{ label = "foo 16"; fun = empty_func; };
		{ label = "foo 17"; fun = empty_func; };
		{ label = "foo 18"; fun = empty_func; };
		{ label = "foo 19"; fun = empty_func; };
		{ label = "foo 20"; fun = empty_func; };
		{ label = "foo 21"; fun = empty_func; };
		{ label = "foo 22"; fun = empty_func; };
		{ label = "foo 23"; fun = empty_func; };
		{ label = "foo 24"; fun = empty_func; };
		{};
		{
			label = "Back";
			fn = function( _ )
				change_menu( "settings" )
			end;
		};
	};
}

local previous_menu_width = 0
local menu_width = 0

local menu_pos_x = 7
local menu_pos_y = START_MENU_POS_Y
local model_offset_x = 0
local model_offset_y = 0
local selected_weapon = 1
local armoury_position = logo.height
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
	[ colours.green ] = colours.grey;
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

	-- Process "unknown" colours (and also white background)
	for i, str in ipairs( model.background ) do
		model.background[ i ] = gsub( str, " ", "g" ):gsub( "0", "g" )
	end
	for i, str in ipairs( model.foreground ) do
		model.foreground[ i ] = gsub( str, " ", "h" )
	end
	---[[
	-- For proper transparency, we need to check char by char
	for i, str in ipairs( model.characters ) do
		local res = ""

		for ii = 1, #str do
			local char = sub( str, ii, ii )

			if char:find( "%s" ) and sub( model.background[ i ], ii, ii ) == "g" then
				res = res .. "\0"
			else
				res = res .. char
			end
		end

		model.characters[ i ] = res
	end
	--]]

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
	previous_menu_width = menu_width
	menu_changed = now
	new_state = state

	local longest = -1

	for _, menu_item in ipairs( menu[ state ] ) do
		if menu_item.label then
			if  longest < #menu_item.label then
				longest = #menu_item.label
			end
		end
	end

	menu_width = longest + 1
end

--- Generate options for the resolution submenu
-- @return nil
function populate_resolution_menu()
	local monitors = {}
	local native = term.native()

	peripheral.find( "monitor", function( name, object )
		if object.isColour and object.isColour() then
			monitors[ #monitors + 1 ] = {
				name   = name;
				handle = object;
			}

			monitors[ name ] = object
		end
	end )

	monitors[ main_win ] = main_win
	monitors[ native   ] = native

	--- The function called on a menu item select
	-- @return nil
	local function mon_func( self )
		for i = 1, #menu.resolution - 2 do
			local item = menu.resolution[ i ]
			item.label = " " .. item.label:sub( 2, -1 )
		end

		terminal = monitors[ self.name ]
		terminal_scale = self.scale

		self.label = ">" .. self.label:sub( 2, -1 )
	end

	for i = 1, #monitors do
		local mon = monitors[ i ]

		for scale = 0.5, 5, 0.5 do
			mon.handle.setTextScale( scale )

			local width, height = mon.handle.getSize()

			if width >= REQUIRED_MIN_SCREEN_WIDTH and height >= REQUIRED_MIN_SCREEN_HEIGHT then
				insert( menu.resolution, 1,
					{
						label = '  Monitor "' .. mon.name .. '" ' .. width .. "x" .. height .. " (native)";
						scale = scale;
						name = mon.name;
						fn = mon_func;
					}
				)
			end
		end
	end

	insert( menu.resolution, 1,
		{
			label = "> This window " .. w .. "x" .. h;
			scale = 1;
			name = main_win;
			fn = mon_func;
		}
	)

	local width, height = native.getSize()

	insert( menu.resolution, 1,
		{
			label = "  This computer " .. width .. "x" .. height .. " (native)";
			scale = 1;
			name = native;
			fn = mon_func;
		}
	)
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
	for i, item in pairs( menu[ menu_state ] ) do
		if item.label then
			local label = item.label
			local start = round( menu_label_start )
			local str   = label:sub( start, min( #label, menu_label_end ) )

			main_buf:write( menu_pos_x + start, menu_pos_y + i, str )
		end
	end

	if settings.show_version and menu_state ~= "armoury" and new_state ~= "armoury" then
		-- Print the version information
		main_buf:write( w - #version, h - 1, version, nil, colours.lightGrey )
	end

	-- Wish a merry Christmas
	local wish = "Happy New Year!"
	main_buf:write( logo.width - #wish + 1, logo.height, wish, nil, colours.green )

	-- Overlay
	--- Particles
	for i = 1, #particles do
		local particle = particles[ i ]
		-- Offset from the sin effect (max: 1.7)
		local offset = -1.7 / 2 + sin( now * 6 + particle.sin_offset ) * 1.7

		overlay_buf:write(
			round( particle.x + offset ),
			round( particle.y ),
			particle.symbol,
			particle.bg or -1,
			particle.fg or -2
		)
	end

	overlay_buf:render()

	-- Draw the game logo
	blittle.draw( logo, 2, 1, wave_win )

	-- Draw the player
	main_buf:write( player.x, player.y, player.text, player.bg, player.fg )

	if menu_state == "armoury" or new_state == "armoury" then
		armoury_buf:clear( -1, -2, "\0" )

		if inventory then
			local infobox_x = round( ( 2 / 3 ) * w ) - 1
			local weapon = inventory.weapons[ selected_weapon ]

			if infobox_x <= player.x and armoury_position <= player.y then
				-- Infobox over the player
				main_buf:write( player.x, player.y, player.text, player.fg, player.bg )
			end

			-- Draw the selected model
			local model = models[ weapon.kind.name ]

			local armoury_width  = floor( ( 1 / 3 ) * w ) - 2
			local armoury_height = ( h - logo.height ) / 2

			draw_model(
				model,
				round( max( armoury_width  - model.width  / 2, 1 ) + model_offset_x ),
				round( max( armoury_height - model.height / 2, 1 ) + model_offset_y ),
				armoury_buf
			)

			for index, weap in ipairs( inventory.weapons ) do
				if index == selected_weapon then
					armoury_buf:write( ( index - 1 ) * 3, h - logo.height - 1, "[ ]", colours.white, colours.black )
				end

				armoury_buf:write( ( index - 1 ) * 3 + 1, h - logo.height - 1, weap.kind.text, colours.white, colours.grey )
			end

			-- Print weapon info
			local damage = bullet_kinds[ weapon.kind.bullet_kind ].damage
			local col = w - infobox_x - 5

			armoury_buf
				:draw_filled_rectangle_from_points(
					infobox_x, 0, w - 1, h - logo.height - 1, -2
				)
				:write( infobox_x + 1, 1, weapon.kind.display_name or weapon.kind.name, -2, colours.black )
				:write( infobox_x + 1, 2, weapon.kind.melee and "Melee weapon" or "Ranged weapon", -2, colours.grey )

				:write( infobox_x + 1, 4, align_number( "Damage", col, damage ), -2, colours.grey )
				:write( infobox_x + 1, 5, align_number( "Cooldown", col, weapon.kind.cooldown ), -2, colours.grey )
				:write( infobox_x + 1, 6, align_number( "DPS", col, damage / weapon.kind.cooldown ), -2, colours.grey )
				:write(
					infobox_x + 1, 7,
					align_number( "Accuracy", col, round( weapon.kind.accuracy * 100 ) .. "%" ),
					-2, colours.grey
				)
				:write(
					infobox_x + 1, 8,
					align_number( "Knockback", col, floor( bullet_kinds[ weapon.kind.bullet_kind ].knockback ) ),
					-2, colours.grey
				)
				:write(
					infobox_x + 2, 9,
					"(" .. ( bullet_kinds[ weapon.kind.bullet_kind ].knockback % 1 ) * 100 .. "% chance)",
					-2, colours.grey
				)
				:write(
					infobox_x + 1, 10,
					align_number( "Clip size", col, weapon.kind.clip_size or "none" ),
					-2, colours.grey
				)
				:write(
					infobox_x + 1, 11,
					align_number( "Bullets", col, inventory.ammunition[ weapon.kind.bullet_kind ] ),
					-2, colours.grey
				)
		else
			local text = "Get some items in-game first!"
			armoury_buf:write( w / 2 - #text / 2, 4, text )
		end

		armoury_buf:write( 0, 0, armoury_back_button.label )

		armoury_buf:render( main_buf, 0, round( armoury_position ) )
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
	-- Calculate wind speed
	local diff = now - last_wind_howl_start

	--stuff = "" .. diff

	if diff > WIND_HOWL_PERIOD then
		last_wind_howl_start = now
		wind_howling = true
		diff = 0
	end

	if wind_howling then
		if diff < WIND_HOWL_DURATION then
			wind_speed = ease_out_quad( diff, WIND_MIN_SPEED, WIND_MAX_SPEED - WIND_MIN_SPEED, WIND_HOWL_TRANSITION )

		elseif diff < WIND_HOWL_DURATION + WIND_HOWL_TRANSITION then
			wind_speed = ease_in_quad ( diff - WIND_HOWL_DURATION, WIND_MAX_SPEED, WIND_MIN_SPEED - WIND_MAX_SPEED, WIND_HOWL_TRANSITION )

		else
			wind_howling = false
		end
	end

	-- Spawn new particles
	if now - last_spawn > SNOWFLAKE_SPAWN_RATE then
		for _ = 1, 2 do
			local position = random( 3 + WIND_MIN_SPEED / 2 - wind_speed / 2, h + w - 1 )

			particles[ #particles + 1 ] = {
				--x = random( 2 - wind_speed / 2, w - wind_speed + WIND_MIN_SPEED + 2 );
				--y = -1;

				x = min( position, w );
				y = position > w and position % w or -1;

				--x_speed = random() > 0.1 and -12 or -8;
				y_speed = 18 + ( random() > 0.5 and 10 or 0 );

				sin_offset = random() * 6;

				symbol = symbols[ random( 1, #symbols ) ];

				fg = random() > 0.10 and colours.lightGrey or colours.grey;
				bg = colours.white;
			}
		end

		last_spawn = now
	end

	local to_destroy = {}

	-- Update particles
	for i = 1, #particles do
		local particle = particles[ i ]

		particle.x = particle.x + wind_speed * dt
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
		menu_label_start = ease_in_quad( now - menu_changed, 1, previous_menu_width - 1, MENU_ANIM_DURATION )
		menu_label_end   = math.huge

		if menu_label_start == previous_menu_width then
			-- This is the actual menu switch!
			menu_state = new_state
			menu_label_end = 0

			menu_pos_y = START_MENU_POS_Y
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
		menu_label_end   = ease_in_quad( now - menu_changed - MENU_ANIM_DURATION, 1, menu_width - 1, MENU_ANIM_DURATION )
	end
end

--- Move the player character (while respecting collisions).
-- @param x	description
-- @param y	description
-- @return nil
function move_player( x, y )
	player.x = x
	player.y = y
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

if not arguments[ "no-intro" ] then
	--- Display the Yellowave signature
	--  (either variation #7, #1, or, if specified, the one set by the command line arg -yw)
	term.redirect( wave_win )

	local variation
	if type( arguments.yw ) == "table" and arguments.yw[ 1 ] then
		variation = arguments.yw[ 1 ]
	else
		variation = random() > 0.25 and 7 or 1
	end

	shell.run( "yellowave.lua", variation )

	sleep( 1 )

	for _ = 1, 3 do
		main_buf:map( shade )
		main_buf:render_to_window( main_win, 1, 1, true )
		sleep( 0 )
		sleep( 0 )
	end

	term.redirect( main_win )
end

wave_win.setVisible( false )

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
if arguments[ "quick-launch" ] then
	running = false
	launch = true
end


local end_queued
now = clock()
local last_time = now
local start_time = now

---- Switch to main menu
change_menu( "main" )

if arguments.menu and type( arguments.menu ) == "table" then
	local value = arguments.menu[ 1 ]

	if menu[ value ] then
		change_menu( value )
	end
end

populate_resolution_menu()

local last_settings_save = -1

local start_drag_x = 0
local start_drag_y = 0

while running do
	if not end_queued then
		queue "end"
		end_queued = true
	end

	local ev = { yield() }

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

	elseif ev[ 1 ] == "mouse_up" or ev[ 1 ] == "monitor_touch" then
		local x = ev[ 3 ] - 1
		local y = ev[ 4 ] - 1

		if menu_state == "armoury" then
			if y == armoury_position and x < #armoury_back_button.label then
				change_menu( "main" )
			end

		elseif x >= menu_pos_x and x <= menu_pos_x + menu_width and y >= menu_pos_y and y <= menu_pos_y + #menu[ menu_state ] then
			local index = y - menu_pos_y

			if  menu[ menu_state ][ index ] and menu[ menu_state ][ index ].fn then
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

		elseif #menu[ menu_state ] >= h / 2 then
			menu_pos_y = max( min( menu_pos_y - ev[ 2 ], START_MENU_POS_Y ), h - #menu[ menu_state ] - 3 )
		end

	elseif ev[ 1 ] == "char" then
		if ev[ 2 ] == "q" then
			running = false
		end

	elseif ev[ 1 ] == "key" then
		held[ ev[ 2 ] ] = true

		if ev[ 2 ] == keys.enter then
			if  menu[ menu_state ][ 1 ] and menu[ menu_state ][ 1 ].fn then
				menu[ menu_state ][ 1 ].fn( menu[ menu_state ][ 1 ] )
			end
		end

	elseif ev[ 1 ] == "key_up" then
		held[ ev[ 2 ] ] = false

	elseif ev[ 1 ] == "term_resize" or ev[ 1 ] == "monitor_resize" or ev[ 1 ] == "peripheral" then
		if ev[ 1 ] == "term_resize" then
			-- Resize buffers
			w, h = main_win.getSize()

			main_buf:resize( w, h )
			overlay_buf:resize( w, h )
			armoury_buf:resize( w, h - logo.height )
		end

		-- Remove "old" entries from the resolution settings menu
		for i = #menu.resolution - 2, 1, -1 do
			remove( menu.resolution, i )
		end

		-- Insert updated ones
		populate_resolution_menu()
	end

	-- Player movement
	local keybind = settings.keybindings

	if  player.movement_speed < now - player.last_moved and false --TODO: Remove the block and continue ;)
	and ( held[ keybind.up ] or held[ keybind.down ] or held[ keybind.left ] or held[ keybind.right ] ) then
		move_player(
			player.x + ( held[ keybind.left ] and -1 or 0 ) + ( held[ keybind.right ] and 1 or 0 ),
			player.y + ( held[ keybind.up   ] and -1 or 0 ) + ( held[ keybind.down  ] and 1 or 0 )
		)

		player.last_moved = now
	end

	-- Save the settings
	if now - last_settings_save > SETTINGS_SAVE_PERIOD then
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

if not arguments[ "quick-launch" ] then
	save_settings()

	for i = 0, 6 do
		fade_level = i

		sleep ( 0 )
		update( 0.15 )
		redraw()
	end

	sleep( 0.1 )
end

if launch then
	local f = io.open( root .. "main.lua", "r" )
	local contents = f:read( "*a" )
	f:close()

	local fn = loadstring( contents, root .. "main.lua" )
	setfenv( fn, _G )

	return fn( settings, terminal, terminal_scale, root )

elseif perform_update then
	term.setCursorPos( 1, 1 )

	local fn = loadstring( get_paste "SNnkfxnx", "installer" )
	setfenv( fn, getfenv() )

	fn( "update", "no-msg", fs.exists( root .. ".noupdate" ) and "dont" or "do" )

	return shell.run( root .. "menu.lua", "--no-intro", "--menu", menu_state )
end
