
-- Yellowave
--	viluon's visual signature, improved approach
--	Uses the BLittle API by Bomb Bloke

local root = "/" .. fs.getDir( shell.getRunningProgram() ) .. "/"

if not fs.exists( root .. "blittle" ) then
	shell.run( "pastebin get ujchRSnU " .. root .. "blittle" )
end

os.loadAPI( root .. "blittle" )
local blittle = blittle

local rnd = math.random

local term = term
local colours = colours

local w, h = term.getSize()
local oldTerm = term.current()
local mainWindow = window.create( oldTerm, 1, 1, w, h, false )

term.setBackgroundColour( colours.black )
term.clear()
local renderBuffer = blittle.createWindow( mainWindow )
term.redirect( renderBuffer )

local biggestX, biggestY = -1, -1
local animWidth = -1
local xOffset, yOffset = 0, 0
local xOffsetImage, yOffsetImage = 0, 0

local yellowavePos

-- Approx. total time of the animation, used for scaling the stationary time of particles
-- The higher this is, the greater the difference between arrival time of particles at the left vs particles at the right will be
local totalTime = 3

local particles = {}
local frames = {}

local flypaths = {
	{
		fn = function( dt, particle )
			if particle.stationaryTime < 0 then
				particle.x = particle.x + particle.xSpeed * dt
				particle.y = particle.y + particle.ySpeed * dt
			else
				particle.stationaryTime = particle.stationaryTime - dt
			end
		end;
		new = function( x, y )
			local stationaryTime = ( animWidth - x ) / animWidth * totalTime
			return {
				x = x;
				y = y;
				stationaryTime = stationaryTime;
				xSpeed = rnd( -10, 10 ) * ( stationaryTime + x / animWidth );
				ySpeed = rnd( -10, 10 ) * ( stationaryTime + x / animWidth );
				colour = colours.white;
			}
		end;
	};
	{
		fn = function( dt, particle )
			if particle.stationaryTime < 0 then
				particle.life = particle.life + dt
				particle.x = particle.x + particle.xSpeed * dt
				particle.y = particle.y + particle.ySpeed * dt
			else
				particle.stationaryTime = particle.stationaryTime - dt
			end

			if particle.life < 0.5 then
				particle.ySpeed = math.abs( particle.ySpeed )
				--particle.colour = colours.green
			else
				particle.ySpeed = -math.abs( particle.ySpeed )
				--particle.colour = colours.white
			end
		end;
		new = function( x, y )
			local stationaryTime = ( animWidth - x ) / animWidth * totalTime
			return {
				x = x;
				y = y;
				stationaryTime = stationaryTime;
				xSpeed = rnd( -1, 10 ) * ( stationaryTime + x / animWidth );
				ySpeed = rnd( 4, 10 ) * ( stationaryTime + x / animWidth );
				life = 0;
				colour = colours.white;
			}
		end;
	};
	{
		fn = function( dt, particle )
			if particle.stationaryTime < 0 then
				particle.x = particle.x + particle.xSpeed * dt
				particle.y = particle.y + particle.ySpeed * dt
			else
				particle.stationaryTime = particle.stationaryTime - dt
			end
		end;
		new = function( x, y )
			local stationaryTime = ( animWidth - x ) / animWidth * totalTime + y / 15
			return {
				x = x;
				y = y;
				stationaryTime = stationaryTime;
				xSpeed = rnd( 15, 20 ) * ( stationaryTime + x / animWidth );
				ySpeed = rnd( -1, 1 ) * ( stationaryTime + x / animWidth );
				colour = colours.white;
			}
		end;
	};
	{
		fn = function( dt, particle )
			if particle.stationaryTime < 0 then
				particle.life = particle.life + dt
				particle.x = particle.x + particle.xSpeed * dt
				particle.y = particle.y + particle.ySpeed * dt
			else
				particle.stationaryTime = particle.stationaryTime - dt
			end

			if particle.life < 0.5 then
				particle.ySpeed = math.abs( particle.ySpeed )
				--particle.colour = colours.green
			else
				particle.ySpeed = -math.abs( particle.ySpeed )
				--particle.colour = colours.white
			end
		end;
		new = function( x, y )
			local stationaryTime = ( animWidth - x ) / animWidth * totalTime
			return {
				x = x;
				y = y;
				stationaryTime = stationaryTime;
				xSpeed = rnd( -10, 1 ) * ( stationaryTime + x / animWidth );
				ySpeed = rnd( 10, 12 ) * ( stationaryTime + x / animWidth );
				life = 0;
				colour = colours.white;
			}
		end;
	};
	{
		fn = function( dt, particle )
			particle.x = particle.x + particle.xSpeed * dt
			particle.y = particle.y + particle.ySpeed * dt
		end;
		new = function( x, y )
			return {
				x = x;
				y = y;
				stationaryTime = stationaryTime;
				xSpeed = ( ( animWidth - x ) / animWidth > 0.4 and 1 or -1 ) * rnd( 12, 15 );
				ySpeed = -0.5 + rnd();
				colour = colours.white;
			}
		end;
	};
	{
		fn = function( dt, particle )
			particle.x = particle.x + particle.xSpeed * dt
			particle.y = particle.y + particle.ySpeed * dt
		end;
		new = function( x, y )
			return {
				x = x;
				y = y;
				xSpeed = rnd( -5, 5 );
				ySpeed = rnd( 8, 10 ) + x / animWidth * 15 - 10;
				colour = colours.white;
			}
		end;
	};
	{
		fn = function( dt, particle )
			if particle.stationaryTime < 0 then
				particle.life = particle.life + dt

				particle.x = particle.x + particle.xSpeed * dt
				particle.y = particle.y + particle.ySpeed * dt
			else
				particle.stationaryTime = particle.stationaryTime - dt
			end

			if particle.life < 0.5 then
				particle.xSpeed = particle.xSpeed + 5 * dt
				particle.ySpeed = particle.ySpeed - 1 * dt

			elseif particle.life < 1.5 then
				particle.xSpeed = particle.xSpeed - 10 * dt
				particle.ySpeed = particle.ySpeed - 30 * dt

			elseif particle.life < 2 then
				particle.xSpeed = particle.xSpeed - 40 * dt
				particle.ySpeed = particle.ySpeed + 20 * dt

			end
		end;
		new = function( x, y )
			local stationaryTime = ( animWidth - x ) / animWidth * totalTime
			return {
				x = x;
				y = y;
				stationaryTime = stationaryTime;
				xSpeed = rnd( 2, 5 ) * ( stationaryTime + x / animWidth );
				ySpeed = rnd( 6, 8 ) * ( stationaryTime + x / animWidth );
				life = 0;
				colour = colours.white;
			}
		end;
	};
}

local args = { ... }
local flypath = flypaths[ tonumber( args[ 1 ] ) or rnd( 1, #flypaths ) ] -- flypaths[ rnd( 1, #flypaths ) ]

local function newParticle( x, y )
	particles[ #particles + 1 ] = flypath.new( x, y )
end

local function loadInitialFrame( path )
	local frame = {}

	local f = io.open( path, "r" )
	if not f then
		error( "File not found", 2 )
	end

	local y = 1

	for line in f:lines() do
		animWidth = math.max( animWidth, #line )

		for x = 1, #line do
			if line:sub( x, x ) ~= " " then
				biggestX = math.max( biggestX, x )
				biggestY = math.max( biggestY, y )
				newParticle( x, y )
			end
		end

		y = y + 1
	end

	return frame
end

local function updateParticles( dt )
	for i, particle in ipairs( particles ) do
		flypath.fn( dt, particle )
	end
end

local function drawParticles()
	mainWindow.setVisible( false )

	term.setBackgroundColour( colours.black )
	term.clear()

	term.redirect( mainWindow )
	term.setCursorPos( xOffsetImage, yOffsetImage + 3 )
	term.write( "made by" )

	term.redirect( renderBuffer )

	for i, particle in ipairs( particles ) do
		if yellowavePos and yellowavePos >= particle.x then
			term.setBackgroundColour( colours.yellow )
		else
			term.setBackgroundColour( particle.colour )
		end

		term.setCursorPos( particle.x + xOffset, particle.y + yOffset )
		term.write( " " )
	end

	mainWindow.setVisible( true )
end

local function copy( tbl )
	if type( tbl ) ~= "table" then
		return tbl
	end

	local result = {}

	for k, v in pairs( tbl ) do
		result[ copy( k ) ] = copy( v )
	end

	return result
end

local function saveFrame()
	frames[ #frames + 1 ] = copy( particles )
end

local function loadFrames()
	local i = #frames
	return function()
		particles = frames[ i ]

		i = i - 1

		if not particles then return nil end
		return true
	end
end

-- Compute

loadInitialFrame( root .. "assets/frames/viluon.frm" )

xOffsetImage = w / 2 - ( biggestX / 2 ) / 2
yOffsetImage = h / 2 - ( biggestY / 3 ) / 2

xOffset = w * 2 / 2 - biggestX / 2	-- w / 2 - biggestX / 2
yOffset = h * 3 / 2 - biggestY / 2	-- h / 2 - biggestY / 2

saveFrame()

for i = 1, 3 do
	updateParticles( 0.1 )
	saveFrame()
end

for i = 1, 20 do
	updateParticles( 0.2 )
	saveFrame()
end

for i = 1, 10 do
	updateParticles( 0.5 )
	saveFrame()
end

-- Render

for _ in loadFrames() do
	drawParticles()

	sleep( 0.01 )
end

particles = frames[ 1 ]
yellowavePos = 1

local totalWaveAnimTime = 0.4
local startTime = os.clock()

while yellowavePos < animWidth do
	local now = os.clock()

	yellowavePos = ( now - startTime ) / totalWaveAnimTime * animWidth
	drawParticles()
	sleep( 0 )
end

term.redirect( oldTerm )
term.setCursorPos( 1, 1 )
