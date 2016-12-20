
-- [SublimeLinter luacheck-globals:term,colours,textutils,keys,fs]

-- Zombease - a top-down zombie survival shooter by viluon

--TODO: Melee/ranged/knockback resistance

-- Passed from launcher (menu.lua)
local args = { ... }
local settings = args[ 1 ]

if not require or type( settings ) ~= "table" then
	print( "wiLL kIll you But RUn mEnU.LUa FiRst" )
	error( "    -- nOT thEmm zOMbiez", 0 )
end

-- Imports
local bump = require "utils.bump"
local buffer = require "desktox.buffer"
local round = require( "desktox.utils" ).round

-- Localisation
local textutils = textutils
local coroutine = coroutine
local colours = colours
local term = term
local keys = keys
local math = math
local fs = fs
local os = os
local yield = coroutine.yield
local queue = os.queueEvent
local random = math.random
local clock = os.clock
local remove = table.remove

-- Functions
local	redraw, spawn_zombie, update, fire, get_coord_speeds,
		move_player, place_static, equip_weapon, reload_weapon,
		place_pickup, bake_weapon, collision_filter,
		save_state, has_weapon

-- Display setup
local main_window = term.current()
local w, h = main_window.getSize()
local main_buf    = buffer.new( 0, 0, w, h )
local overlay_buf = buffer.new( 0, 0, w, h, main_buf, -1, -2, "\0" )

-- Constants
local WAVE_PREPARATION_TIME = 10
local MAX_ZOMBIES = 30
--- Under what amount of bullets left in the clip should the counter change colour
--TODO: This could be based on the weapon's RPS
local BULLETS_LEFT_WARNING = 2

local framerate_cap = settings.limit_FPS

-- Data
local now = -1
local end_time
local start_time = clock()
--local stuff = "interestring"
local running = true
local HUD_enabled = true
local auto_reload = true
local selected_weapon_index

--- Stats
local damage_dealt = 0
local zombies_spawned = 0
local pickup_taken_count = 0
local pickup_dropped_count = 0
local kills = 0
---- Imagine Dragons
local shots = 0
local melee_swings = 0
local hits = 0
local melee_hits = 0
local wave_count = 0

local next_wave_countdown = -math.huge

--- Held keys and buttons
local held = { mouse = {} }

--- Directory
local root = "/"

local world = bump.newWorld( 8 )
local world_size = {
	x = 50;
	y = 50;
}

local camera_offset = {
	x = 0;
	y = 0;
}

local weapon_kinds = {}
local bullet_kinds = {}

--- Load assets
--TODO: Generalize this code
local weapons = {}

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
				weapon_kinds[ name ] = result
				weapons[ name ] = {
					kind = result;
				}
			else
				error( "Loading asset " .. weapon_dir .. name .. " failed:\n\t" .. result )
			end
		end
	end
end

local player = {
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
			weapons.fists,
		};

		attachments = {

		};
	};
}

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
				player.inventory.ammunition[ name ] = player.inventory.ammunition[ name ] or 0
			else
				error( "Loading asset " .. bullet_dir .. name .. " failed:\n\t" .. result )
			end
		end
	end
end

local attachment_kinds = {}

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

player.x = 10
player.y = 6

local zombie_kinds = {
	[ 1 ] = {
		name = "generic";

		text = "&";
		bg = colours.black;
		fg = colours.green;

		-- How much time (in seconds) until the zombie can move
		movement_speed = 0.6;
		damage = 8;
		health = 20;

		-- Since which wave can the kind spawn
		difficulty = 1;

		drop = {
			-- Pistol ammo
			{ probability = 0.45; item = 1; };
			-- Pistol weapon
			{ probability = 0.33;  item = 4; };
		};
	};
	[ 2 ] = {
		name = "runner";

		text = "$";
		bg = colours.black;
		fg = colours.lime;

		movement_speed = 0.25;
		damage = 4;
		health = 12;

		difficulty = 2;

		drop = {
			{ probability = 0.2;  item = 3; };
			{ probability = 0.05; item = 1; };
		};
	};
	[ 3 ] = {
		name = "heavyduty";

		text = "@";
		bg = colours.grey;
		fg = colours.lime;

		movement_speed = 0.95;
		damage = 26;
		health = 55;

		difficulty = 3;

		drop = {
			{ probability = 0.4;  item = 2; };
			{ probability = 0.15; item = 5; };
		};
	};
	[ 4 ] = {
		name = "mercenary";

		text = "\1";
		bg = colours.lime;
		fg = colours.black;

		movement_speed = 0.5;
		damage = 10;
		health = 40;

		difficulty = 5;

		drop = {
			{ probability = 0.4;  item = 1; };
			{ probability = 0.2;  item = 2; };
			{ probability = 0.05; item = 6; };
		}
	}
}

local zombies = {
	target = main_buf;
}

local bullets = {
	target = overlay_buf;
}

local statics = {
	target = main_buf;
}

local pickup_kinds = {
	[ 1 ] = {
		name = "pistol_ammo";

		text = "=";
		bg = colours.black;
		fg = colours.lightGrey;

		life = 5;

		on_pickup = function()
			player.inventory.ammunition.generic = player.inventory.ammunition.generic + random( 1, 5 )
		end;
	};
	[ 2 ] = {
		name = "assault_ammo";

		text = "\19"; -- two exclamation marks
		bg = colours.black;
		fg = colours.lightGrey;

		life = 8;

		on_pickup = function()
			player.inventory.ammunition.assault = player.inventory.ammunition.assault + random( 10, 50 )
		end;
	};
	[ 3 ] = {
		name = "small_health";

		text = "\3";
		bg = colours.black;
		fg = colours.pink;

		life = 10;

		on_pickup = function()
			player.health = player.health + 10
		end;
	};
	[ 4 ] = {
		name = "pistol";

		weapon = weapons.pistol;

		text = weapons.pistol.kind.text;
		bg = colours.black;
		fg = colours.white;

		life = 15;

		on_pickup = function()
			if not has_weapon( weapons.pistol ) then
				player.inventory.weapons[ #player.inventory.weapons + 1 ] = weapons.pistol
			end
		end;
	};
	[ 5 ] = {
		name = "assault_rifle";

		weapon = weapons.assault_rifle;

		text = weapons.assault_rifle.kind.text;
		bg = colours.black;
		fg = colours.white;

		life = 15;

		on_pickup = function()
			if not has_weapon( weapons.assault_rifle ) then
				player.inventory.weapons[ #player.inventory.weapons + 1 ] = weapons.assault_rifle
			end
		end;
	};
	[ 6 ] = {
		name = "katana";

		weapon = weapons.katana;

		text = weapons.katana.kind.text;
		bg = colours.black;
		fg = colours.white;

		life = 15;

		on_pickup = function()
			if not has_weapon( weapons.katana ) then
				player.inventory.weapons[ #player.inventory.weapons + 1 ] = weapons.katana
			end
		end;
	};
}

local pickups = {
	target = main_buf;
}

-- Drawable stuffs, in order of rendering
local drawables  = { statics, pickups, zombies, bullets }
-- Stuffs that can perish over time
local ephemerals = { statics, pickups, bullets }
-- Stuffs that collide
local physicals  = { zombies, bullets }

--- Props
local blood = {
	text = "\215";
	bg = colours.black;
	fg = colours.red;

	-- This blood has a life! (In seconds)
	life = 10;
}

-- FPS counter
local frames = 0
local last_fps = 0
local last_fps_reset = 0
local FPS_RESET_INTERVAL = 0.5

--- Calculate the x and y speeds of a bullet from a mouse click.
function get_coord_speeds( x, y, max )
	local scale = math.sqrt( x * x + y * y ) / max
	return x / scale, y / scale
end

--- The universal collision filter describing interactions in the game world. For use with world:move().
-- @param item description
-- @param other description
-- @return The type of collision for bump.lua to use
function collision_filter( item, other )
	if other.type == "pickup" or item.type == "pickup" then
		return "cross"
	end

	return "slide"
end

--- Redraw the view.
-- @return nil
function redraw()
	overlay_buf:clear( -1, -2, "\0" )
	main_buf:clear( colours.black )

	--stuff = next_wave_countdown

	-- Draw the background
	local line_number = math.floor( camera_offset.y / 6 )
	for y = camera_offset.y % 6, h - 1, 6 do
		for x = camera_offset.x % 10 - 10, w - 1, 10 do
			main_buf:write( x + line_number % 2 * 4, y, "\127", colours.black, colours.grey )
		end

		line_number = line_number + 1
	end

	line_number = math.floor( camera_offset.y / 6 )
	for y = camera_offset.y % 6 - 3, h - 1, 6 do
		for x = camera_offset.x % 10 - 5, w - 1, 10 do
			main_buf:write( x + line_number % 2 * 4, y, ".", colours.black, colours.grey )
		end

		line_number = line_number + 1
	end

	-- Draw the world borders
	main_buf
		:clear_column(
			camera_offset.x, colours.black,
			colours.grey, "*",
			camera_offset.y,
			camera_offset.y + world_size.y
		)
		:clear_column(
			camera_offset.x + world_size.x, colours.black,
			colours.grey, "*",
			camera_offset.y,
			camera_offset.y + world_size.y
		)
		:clear_line  (
			camera_offset.y, colours.black,
			colours.grey, "*",
			camera_offset.x,
			camera_offset.x + world_size.x
		)
		:clear_line  (
			camera_offset.y + world_size.y, colours.black,
			colours.grey, "*",
			camera_offset.x,
			camera_offset.x + world_size.x
		)

	-- Draw all objects in the world
	for index = 1, #drawables do
		local collection = drawables[ index ]
		local target = collection.target

		for i = 1, #collection do
			local object = collection[ i ]

			local pos_y = round( object.y + camera_offset.y )
			local pos_x = round( object.x + camera_offset.x )

			if pos_y >= 0 and pos_y < h then
				if pos_x >= 0 and pos_x < w then
					-- Object is visible, draw it
					local kind = object.kind
					target:write( pos_x, pos_y, object.text, kind.bg, object.fg or kind.fg )
				end
			end
		end
	end

	-- Draw the player
	main_buf:write( player.x + camera_offset.x, player.y + camera_offset.y, player.text, player.bg, player.fg )

	-- Draw the overlay
	--- Weapon info
	local weapon_info, weapon_info_colour

	if not player.weapon.melee then
		local reloading = player.weapon.reload_start > now - player.weapon.reload_delay * player.reload_time_multiplier
		local clip

		if not reloading then
			clip = player.weapon.current_clip_size
			weapon_info = clip .. "/" .. player.inventory.ammunition[ player.weapon.bullet_kind ]
		else
			weapon_info = "reloading"
		end

		weapon_info_colour = reloading and colours.orange or ( clip < BULLETS_LEFT_WARNING and colours.red or colours.lightGrey )

	else
		if player.weapon.current_cooldown > 0 then
			local percentage = round( 100 * ( 1 - player.weapon.current_cooldown / player.weapon.cooldown ) )

			weapon_info = "(" .. percentage .. "%)"
			weapon_info_colour = colours.orange
		else
			weapon_info = "melee"
			weapon_info_colour = colours.lightGrey
		end
	end

	overlay_buf
		:write( 0, 0, ""
			.. " Health: "  .. player.health
			.. " Zombies: " .. #zombies
			.. " Bullets: " .. #bullets
			.. " FPS: "     .. last_fps,
			-2, colours.lightGrey )
		:write( w - #weapon_info, h - 1, weapon_info, -2, weapon_info_colour )

	--- Weapon selection bar
	for index, weapon in ipairs( player.inventory.weapons ) do
		if weapon == player.weapon then
			overlay_buf:write( ( index - 1 ) * 3, h - 1, "[ ]", -2, colours.white )

			local text, bg, fg = weapon.text, -1, colours.white

			if weapon.melee then
				local frame = weapon.anim[ round( ( #weapon.anim - 1 ) * weapon.current_cooldown / weapon.cooldown ) + 1 ]
				text, bg, fg = frame.text, frame.bg, frame.fg
			end

			overlay_buf:write( player.x + camera_offset.x, player.y + camera_offset.y, text, bg, fg )
		end

		overlay_buf:write( ( index - 1 ) * 3 + 1, h - 1, weapon.text, -2, colours.lightGrey )
	end

	-- Wave countdown
	if next_wave_countdown > -math.huge then
		local  text = ""
			.. " WAVE #"
			.. wave_count
			.. " IN "
			.. ( next_wave_countdown < 5 and round( next_wave_countdown, 1 ) or math.floor( next_wave_countdown ) )
			.. " "

		overlay_buf:write( round( w / 2 - #text / 2 ), 5, text, -2, colours.white )
	end

	if player.health <= 0 then
		end_time = end_time or clock()
		local text = " YOU ARE DEAD "

		local time = end_time - start_time
		local time_str = math.floor( time / 60 ) .. "m " .. math.floor( time % 60 ) .. "s"

		overlay_buf:write( round( w / 2 - #text / 2 ), round( h / 2 ) - 4, text, colours.black, colours.white )

		local stats = ""
			.. " Zombies killed: " .. kills .. " (" .. round( kills / ( zombies_spawned + 0.000001 ) * 100 ) .. "%) \n"
			.. " Time alive: " .. time_str .. " \n"
			.. " Waves survived: " .. wave_count - 1 .. " \n"
			.. " Shots fired: " .. shots .. " (" .. round( hits / ( shots + 0.000001 ) * 100 ) .. "% hit) \n"
			.. " Melee swings: " .. melee_swings .. " (" .. round( melee_hits / ( melee_swings + 0.000001 ) * 100 ) .. "% hit) \n"
			.. " Damage dealt: " .. damage_dealt .. " \n"
			.. ( random() > 0.1 and " Pickups taken: " or " Picks uped: " )
			.. pickup_taken_count .. " (" .. round( pickup_taken_count / ( pickup_dropped_count + 0.000001 ) * 100 ) .. "%) \n"

		local i = -2
		for line in stats:gmatch( "([^\n]*)\n" ) do
			overlay_buf:write( round( w / 2 - 12 ), round( h / 2 ) + i, line, colours.black, colours.white )
			i = i + 1
		end
	end

	if HUD_enabled then
		overlay_buf:render()
	end

	main_buf:render_to_window( main_window )
end

--- Update the world.
-- @param dt Time since last update
-- @return nil
function update( dt )
	--TODO: This needs fixing!
	if player.health <= 0 then
		running = false
	end

	if not running then
		return
	end

	-- Enemy wave mechanics
	next_wave_countdown = next_wave_countdown - dt

	if #zombies == 0 and next_wave_countdown == -math.huge then
		-- Countdown to next wave
		wave_count = wave_count + 1
		next_wave_countdown = WAVE_PREPARATION_TIME

	elseif #zombies == 0 and next_wave_countdown <= 0 then
		-- Send the next wave!

		-- Spawn zombies
		for _ = 1, math.min( wave_count * 5, MAX_ZOMBIES ) do
			spawn_zombie()
		end

		next_wave_countdown = -math.huge
	end

	--TODO: What about using a single table? Would that break anything?

	-- Update physics-enabled objects
	for index = 1, #physicals do
		local to_destroy = {}
		local collection = physicals[ index ]

		for i = 1, #collection do
			local object = collection[ i ]

			if object.type == "zombie" then
				if object.health <= 0 then
					local drop = object.kind.drop

					if drop then
						for ii = 1, #drop do
							local kind = pickup_kinds[ drop[ ii ].item ]

							if  random() < drop[ ii ].probability
							and ( not kind.weapon or not has_weapon( kind.weapon ) ) then
								place_pickup( object.x, object.y, kind )
							end
						end
					end

					to_destroy[ #to_destroy + 1 ] = object
					kills = kills + 1
				end

				if now - object.last_moved >= object.kind.movement_speed then
					-- Move the zombie toward the player
					local new_x, new_y, collisions, len = world:move(
						object,
						object.x + ( object.x > player.x and -1 or 1 ),
						object.y + ( object.y > player.y and -1 or 1 ),
						collision_filter
					)

					object.x, object.y = new_x, new_y

					for ii = 1, len do
						if collisions[ ii ].other == player then
							player.health = player.health - object.damage
							break
						end
					end

					object.last_moved = now
				end

			elseif object.type == "bullet" then
				local new_x, new_y, collisions, len = world:move(
					object,
					object.x + object.speed_x * dt,
					object.y + object.speed_y * dt,
					collision_filter
				)

				local should_die = false

				if new_x < 0 or new_x > world_size.x or new_y < 0 or new_y > world_size.y then
					should_die = true

				else
					if len > 0 then
						for ii = 1, len do
							local other = collisions[ ii ].other

							if other.type ~= "pickup" then
								should_die = true
							end

							if other.health and other ~= player then
								other.health = other.health - object.damage
								other.x = other.x + ( object.x < other.x and object.knockback or -object.knockback )
								other.y = other.y + ( object.y < other.y and object.knockback or -object.knockback )

								if object.kind and object.kind.melee then
									melee_hits = melee_hits + 1
								else
									hits = hits + 1
								end

								damage_dealt = damage_dealt + object.damage
							end
						end
					end
				end

				if should_die then
					to_destroy[ #to_destroy + 1 ] = object
				else
					object.x, object.y = new_x, new_y
				end
			end
		end

		for i = 1, #to_destroy do
			local corpse = to_destroy[ i ]
			world:remove( corpse )

			for ii = 1, #collection do
				if corpse == collection[ ii ] then
					if corpse.type == "zombie" then
						place_static( corpse.x, corpse.y, blood )
					end

					remove( collection, ii )
					break
				end
			end
		end
	end

	--[[

		local bullets_to_destroy = {}

		-- Move the bullets!
		for i = 1, #bullets do
			local bullet = bullets[ i ]

			local new_x, new_y, collisions, len = world:move(
				bullet,
				bullet.x + bullet.speed_x * dt,
				bullet.y + bullet.speed_y * dt
			)

			bullet.x, bullet.y = new_x, new_y

			if new_x < 0 or new_x > world_size.x or new_y < 0 or new_y > world_size.y or len > 0 then
				bullets_to_destroy[ #bullets_to_destroy + 1 ] = bullet

				for index = 1, len do
					local object = collisions[ index ].other

					if object.health and object ~= player then
						object.health = object.health - bullet.damage
						hits = hits + 1
					end
				end
			end
		end

		-- Remove the *truly dead* zombies from the world
		for _, v in ipairs( zombies_to_destroy ) do
			world:remove( v )

			for i = 1, #zombies do
				if zombies[ i ] == v then
					place_static( v.x, v.y, blood )
					remove( zombies, i )
					break
				end
			end
		end

		-- Remove the collided bullets from the world
		for _, v in ipairs( bullets_to_destroy ) do
			world:remove( v )

			for i = 1, #bullets do
				if bullets[ i ] == v then
					remove( bullets, i )
					break
				end
			end
		end
	--]]

	-- Loop through things that can perish
	for i = 1, #ephemerals do
		local collection = ephemerals[ i ]
		local to_destroy = {}

		for index = 1, #collection do
			local object = collection[ index ]

			if object.created + object.kind.life < now then
				to_destroy[ #to_destroy + 1 ] = object
			end
		end

		for _, v in ipairs( to_destroy ) do
			if v.collides then
				world:remove( v )
			end

			for index = 1, #collection do
				if collection[ index ] == v then
					remove( collection, index )
					break
				end
			end
		end
	end

	-- Update the camera position to centre on the player character
	camera_offset.x = round( -player.x + w / 2 )
	camera_offset.y = round( -player.y + h / 2 )
end

--- Fire a bullet.
-- @param x description
-- @param y description
-- @param speed_x description
-- @param speed_y description
-- @param kind description
-- @return nil
function fire( x, y, dir_x, dir_y, kind, damage_multiplier, accuracy )
	x = x or 0
	y = y or 0

	kind = kind and bullet_kinds[ kind ] or bullet_kinds.generic
	accuracy = accuracy or 1

	-- We take the natural number from the knockback (2 out of 2.1) and the decimal part as the chance (0.1 out of 2.1)
	local knockback = math.floor( kind.knockback ) * ( random() < kind.knockback % 1 and 1 or 0 )

	local accuracy_modifier = ( 1 + random() * ( 1 - accuracy ) )

	if random() > 0.5 then
		dir_x = dir_x * accuracy_modifier + ( random() - 0.5 ) * ( 1 - accuracy )
		dir_y = dir_y / accuracy_modifier + ( random() - 0.5 ) * ( 1 - accuracy )
	else
		dir_x = dir_x / accuracy_modifier + ( random() - 0.5 ) * ( 1 - accuracy )
		dir_y = dir_y * accuracy_modifier + ( random() - 0.5 ) * ( 1 - accuracy )
	end

	local speed_x, speed_y = get_coord_speeds( dir_x, dir_y, kind.speed )

	local ratio = math.abs( speed_x / speed_y )

	-- Perform the first step, so that we don't hit the place we're firing *from*
	x = x + ( round( speed_x, 1 ) == 0 and 0 or ( speed_x > 0 and 1 or -1 ) )
	y = y + ( round( speed_y, 1 ) == 0 and 0 or ( speed_y > 0 and 1 or -1 ) )

	local bullet = {
		type = "bullet";

		fg = knockback == 0 and kind.fg or kind.knockback_highlight or colours.cyan;

		x = x;
		y = y;
		speed_x = speed_x;
		speed_y = speed_y;

		text = ( ratio >= 1.333 and kind.text_horizontal or kind.text_vertical ) or kind.text;

		kind = kind;
		damage = kind.damage * ( damage_multiplier or player.weapon.damage_multiplier );
		knockback = knockback;

		created = now;
		collides = true;
	}

	bullets[ #bullets + 1 ] = bullet
	world:add( bullet, bullet.x, bullet.y, 1, 1 )
end

--- Move the player character (respecting collisions)
-- @param x description
-- @param y description
-- @return nil
function move_player( x, y )
	local new_x, new_y, collisions, len = world:move( player, x, y, collision_filter )

	player.x = round( new_x )
	player.y = round( new_y )

	if len > 0 then
		-- Go through the collisions to check whether we hit a pickup
		for i = 1, len do
			local other = collisions[ i ].other

			if other.type == "pickup" then
				if type( other.kind.on_pickup ) == "function" then
					--TODO: Any args here?
					other.kind.on_pickup()
				end

				-- We've picked this one up,
				pickup_taken_count = pickup_taken_count + 1
				-- remove...
				world:remove( other )
				for index = 1, #pickups do
					if pickups[ index ] == other then
						remove( pickups, index )
						break
					end
				end

				if player.weapon.current_clip_size == 0 then
					-- It might have been ammo, so let's reload
					reload_weapon()
				end

				-- The space is now empty, try to move in there again
				--TODO: We now use "cross" as the collision type for pickups => is this still needed?
				return move_player( x, y )
			end
		end
	end
end

--- Save the player progress.
-- @return nil
function save_state()
	local inventory = {}

	inventory.ammunition  = player.inventory.ammunition
	inventory.attachments = {}
	inventory.weapons = {}

	-- Save only the weapon links
	for _, item in ipairs( player.inventory.weapons ) do
		for name, weapon in pairs( weapons ) do
			if item == weapon then
				inventory.weapons[ #inventory.weapons + 1 ] = name

				if not item.melee then
					-- Don't forget about ammunition left in the clip!
					inventory.ammunition[ weapon.bullet_kind ] =
						inventory.ammunition[ weapon.bullet_kind ] + ( item.current_clip_size or 0 )
				end

				break
			end
		end
	end

	-- ...And attachment links
	for _, item in ipairs( player.inventory.attachments ) do
		for _, attachment in pairs( attachment_kinds ) do
			if item == attachment then
				inventory.weapons[ #inventory.weapons + 1 ] = attachment.name
				break
			end
		end
	end

	local save_file = io.open( root .. "saves/unnamed.tbl", "w" )
	save_file:write( textutils.serialise( inventory ) )
	save_file:close()
end

--- Prepare a weapon object for actual use (process its properties).
-- @param weapon description
-- @return nil
function bake_weapon( weapon )
	-- Copy the weapon's kind data to the object itself (so that we don't modify the kind later on)
	for key, value in pairs( weapon.kind ) do
		weapon[ key ] = value
	end

	weapon.reload_start = -1
	weapon.current_clip_size = weapon.current_clip_size or 0

	weapon.attachments = weapon.attachments or {}

	-- Apply the attachments
	for i = 1, #weapon.attachments do
		local attachment = weapon.attachments[ i ]

		if not attachment.filter or attachment.filter( weapon ) then
			attachment.apply( weapon )
		end
	end
end

--- Check for a weapon in the player's inventory.
-- @param weapon description
-- @return nil
function has_weapon( weapon )
	-- Check if the  weapon  is already there
	for _, weap in ipairs( player.inventory.weapons ) do
		if weap == weapon then
			return true
		end
	end
end

--- Change the currently equipped weapon.
-- @param new_weapon description
-- @return nil
function equip_weapon( new_weapon )
	if player.weapon and not player.weapon.melee
	and player.weapon.reload_start > now - player.weapon.reload_delay * player.reload_time_multiplier then
		local ammo = player.inventory.ammunition
		local weapon = player.weapon

		weapon.current_clip_size = weapon.current_clip_size - weapon.change
		ammo[ weapon.bullet_kind ] = ammo[ weapon.bullet_kind ] + weapon.change
	end

	player.weapon = new_weapon
	player.weapon.reload_start = -1
	player.weapon.current_cooldown = 0
	player.weapon.current_clip_size = player.weapon.current_clip_size or 0

	if auto_reload and not player.weapon.melee and player.weapon.current_clip_size <= 0 then
		reload_weapon()
	end
end

--- Reload the currently equipped weapon.
-- @param weapon (Optional) The weapon to reload, defaults to player.weapon
-- @param instantly (Optional) Whether to perform the reload without a delay, defaults to false
-- @return nil
function reload_weapon( weapon, instantly )
	weapon = weapon or player.weapon

	if weapon.melee then
		return
	end

	local ammo = player.inventory.ammunition

	if ammo[ weapon.bullet_kind ] < 1
	or ( weapon.reload_start + weapon.reload_delay * player.reload_time_multiplier > now and not instantly )
	or weapon.current_clip_size == weapon.clip_size
	then
		return
	end

	local change = math.min( ammo[ weapon.bullet_kind ], weapon.clip_size - weapon.current_clip_size )

	weapon.change = change
	weapon.current_clip_size = weapon.current_clip_size + change
	ammo[ weapon.bullet_kind ] = ammo[ weapon.bullet_kind ] - change

	if not instantly then
		weapon.reload_start = now
	end
end

--- Spawn a zombie.
-- @param x (Optional) The x coordinate to spawn the zombie at, defaults to a random value from 0 to world_size.x - 1
-- @param y (Optional) The y coordinate to spawn the zombie at, defaults to a random value from 0 to world_size.y - 1
-- @param kind (Optional) The kind of zombie to spawn (an index to zombie_kinds), defaults to a random value from 1 to #zombie_kinds
-- @return nil
function spawn_zombie( x, y, kind )
	if not kind then
		-- This zombie isn't kind
		repeat
			kind = zombie_kinds[ math.random( 1, #zombie_kinds ) ]
		until kind.difficulty <= wave_count
	else
		kind = zombie_kinds[ kind ]
	end

	local zombie = {
		type = "zombie";

		x = x or random( 0, world_size.x - 1 );
		y = y or random( 0, world_size.y - 1 );

		kind = kind;
		text = kind.text;
		last_moved = -1;
		health = kind.health;
		damage = kind.damage;
	}

	zombies[ #zombies + 1 ] = zombie
	world:add( zombie, zombie.x, zombie.y, 1, 1 )

	zombies_spawned = zombies_spawned + 1
end

--- Place a static object.
-- @param x description
-- @param y description
-- @param object description
-- @return nil
function place_static( x, y, kind )
	local static = {
		type = "static";

		x = x;
		y = y;

		text = kind.text;
		kind = kind;
		created = now;
	}

	statics[ #statics + 1 ] = static
end

--- Place a pickup.
-- @param x description
-- @param y description
-- @param kind description
-- @return nil
function place_pickup( x, y, kind )
	local pickup = {
		type = "pickup";

		x = x;
		y = y;

		text = kind.text;
		kind = kind;
		created = now;

		collides = true;
	}

	world:add( pickup, x, y, 1, 1 )
	pickup_dropped_count = pickup_dropped_count + 1

	pickups[ #pickups + 1 ] = pickup
end

-- Initial setup
--- Load save, if present
local save_file = io.open( root .. "saves/unnamed.tbl", "r" )
if save_file then
	local contents = save_file:read( "*a" )

	local inventory = textutils.unserialise( contents )

	if inventory then
		-- Link the items to their kinds
		for i, item in ipairs( inventory.weapons ) do
			for name, weapon in pairs( weapons ) do
				if name == item then
					player.inventory.weapons[ i ] = weapon
					break
				end
			end
		end

		player.inventory.ammunition = inventory.ammunition
	end

	save_file:close()
end

--- Bake all the weapons
for _, weapon in pairs( weapons ) do
	bake_weapon( weapon )
	--equip_weapon( weapon )
	reload_weapon( weapon, true )
end

selected_weapon_index = 1
equip_weapon( player.inventory.weapons[ selected_weapon_index ] )
world:add( player, player.x, player.y, 1, 1 )

local last_coords = {
	x = 0;
	y = 0;
}

local end_queued = false
local last_time = clock()

-- The Glorious Game Loop
while running do
	if not end_queued then
		queue( "end" )
		end_queued = true
	end

	local ev = { yield() }

	now = clock()
	local dt = now - last_time

	if ev[ 1 ] == "end" then
		end_queued = false

	elseif ev[ 1 ] == "key" then
		held[ ev[ 2 ] ] = true

		if ev[ 2 ] == keys.t then
			spawn_zombie()

		elseif ev[ 2 ] == keys.q then
			break

		elseif ev[ 2 ] == keys.r then
			reload_weapon()

		elseif ev[ 2 ] == keys.g then
			next_wave_countdown = next_wave_countdown - WAVE_PREPARATION_TIME

		elseif ev[ 2 ] == keys.f then
			HUD_enabled = not HUD_enabled

		-- Weapon selection keys
		elseif ev[ 2 ] > 1 and ev[ 2 ] < 10 then
			local weapon = player.inventory.weapons[ ev[ 2 ] - 1 ]

			if weapon then
				selected_weapon_index = ev[ 2 ] - 1
				equip_weapon( weapon )
			end
		end

	elseif ev[ 1 ] == "key_up" then
		held[ ev[ 2 ] ] = false

	elseif ev[ 1 ] == "mouse_click" then
		held.mouse[ ev[ 2 ] ] = true

		last_coords.x = ev[ 3 ]
		last_coords.y = ev[ 4 ]

	elseif ev[ 1 ] == "mouse_drag" then
		-- Mouse on drags
		last_coords.x = ev[ 3 ]
		last_coords.y = ev[ 4 ]

	elseif ev[ 1 ] == "mouse_up" then
		held.mouse[ ev[ 2 ] ] = false

	elseif ev[ 1 ] == "mouse_scroll" then
		selected_weapon_index = math.max( 1, math.min( #player.inventory.weapons, selected_weapon_index + ev[ 2 ] ) )
		equip_weapon( player.inventory.weapons[ selected_weapon_index ] )

	elseif ev[ 1 ] == "terminate" then
		break
	end

	player.weapon.current_cooldown = player.weapon.current_cooldown - dt

	if  player.weapon.current_cooldown < 0 then
		player.weapon.current_cooldown = 0
	end

	-- React to *held* keys (and mouse buttons)
	if held.mouse[ 1 ] and player.weapon.current_cooldown <= 0 then
		local x = last_coords.x - player.x - camera_offset.x - 1
		local y = last_coords.y - player.y - camera_offset.y - 1

		-- Handle firing the gun!
		if    player.weapon.melee
		or  ( player.weapon.current_clip_size > 0
		      and player.weapon.reload_start  < now - player.weapon.reload_delay * player.reload_time_multiplier
		    )
		then
			if not player.weapon.melee then
				shots = shots + 1
				player.weapon.current_clip_size = player.weapon.current_clip_size - 1
			else
				melee_swings = melee_swings + 1
			end

			fire( player.x, player.y, x, y,  player.weapon.bullet_kind, player.weapon.damage_multiplier, player.weapon.accuracy )

			player.weapon.current_cooldown = player.weapon.cooldown

			if auto_reload and not player.weapon.melee and player.weapon.current_clip_size <= 0 then
				reload_weapon()
			end
		end
	end

	if last_fps_reset ~= now and now - last_fps_reset >= FPS_RESET_INTERVAL then
		last_fps = round( frames / FPS_RESET_INTERVAL )
		last_fps_reset = now
		frames = 0
	end

	-- Player movement
	if player.movement_speed < now - player.last_moved and ( held[ keys.w ] or held[ keys.s ] or held[ keys.a ] or held[ keys.d ] ) then
		move_player(
			player.x + ( held[ keys.a ] and -1 or 0 ) + ( held[ keys.d ] and 1 or 0 ),
			player.y + ( held[ keys.w ] and -1 or 0 ) + ( held[ keys.s ] and 1 or 0 )
		)

		player.last_moved = now
	end

	if not framerate_cap or dt ~= 0 then
		update( dt )
		redraw()

		last_time = now
		frames = frames + 1
	end
end

save_state()

queue "clean_up"
os.pullEvent "clean_up"
