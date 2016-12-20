
local base64 = require( "utils.base64" )

local args = { ... }

local input = io.open( args[ 1 ], "rb" )
local output = io.open( args[ 2 ], "w" )

local byte = input:read()
local str = ""

while byte do
	str = str .. string.char( byte )
	byte = input:read()
end

input:close()

output:write( base64.encode( str ) )
output:close()
