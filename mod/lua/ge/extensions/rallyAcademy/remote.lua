-- Remote commands over local HTTP (docs/STREAM_DECK.md): a Stream Deck web-request key, a
-- script or a button box calls http://127.0.0.1:<port>/<command> and the mod runs it, with
-- no key emulation and no need for the game window to have focus.
-- Pure Lua: request parsing, routing and responses. The extension owns the socket.
--
-- Safety: the extension listens on 127.0.0.1 only; only the fixed commands below exist (no
-- Lua is ever run from a request); requests from a web browser (they carry Origin or
-- Referer) are refused, so a web page can't press keys for you.
local R = {}

R.DEFAULT_PORT = 29393
R.MAX_REQUEST = 8192 -- bytes: anything longer is refused

-- Commands, in the order the docs and `GET /` list them: path, extension function, argument.
R.COMMANDS = {
  {path = 'retry', fn = 'retry', desc = 'Back to the start, car repaired'},
  {path = 'go-to-drill', fn = 'goToDrill', desc = "Load the selected drill's map and car, place you at its start"},
  {path = 'previous', fn = 'selectPrevious', desc = 'Select the previous drill'},
  {path = 'next', fn = 'selectNext', desc = 'Select the next drill'},
  {path = 'menu', fn = 'toggleMenu', desc = 'Open or close the Academy screen'},
  {path = 'mark-start', fn = 'markStart', desc = 'Mark the start here (a course drill lays its course out from here)'},
  {path = 'venue-start', fn = 'useVenueStart', desc = 'Course drills: lay the course out at the venue again'},
  {path = 'mark-finish', fn = 'markFinish', desc = 'Mark the finish, stop zone or stop line here'},
  {path = 'add-gate', fn = 'addGate', desc = 'Mark the next gate here'},
  {path = 'clear-gates', fn = 'clearGates', desc = 'Remove the marked gates'},
  {path = 'pass', fn = 'recordAttempt', arg = true, desc = 'Score a pass (self-assessed drills)'},
  {path = 'miss', fn = 'recordAttempt', arg = false, desc = 'Score a miss; abandons a run on graded drills'},
  {path = 'auto-retry', fn = 'toggleAutoRetry', desc = 'Turn auto-retry on or off'},
  {path = 'save-spot', fn = 'saveSpot', desc = 'Bookmark this place as a possible venue'},
}
local byPath = {}
for _, c in ipairs(R.COMMANDS) do byPath[c.path] = c end

-- Parse the request head (everything before the blank line).
-- Returns {method, path (no leading slash, no query, lower case), headers = {lower-name = value}} or nil.
function R.parseRequest(head)
  local method, target = head:match('^(%u+) (%S+) HTTP/%d%.%d\r?\n')
  if not method then return nil end
  local headers = {}
  for name, value in head:gmatch('\n([%w%-]+):%s*([^\r\n]*)') do headers[name:lower()] = value end
  local path = target:gsub('[?#].*$', ''):gsub('^/+', ''):gsub('/+$', ''):lower()
  return {method = method, path = path, headers = headers}
end

-- How many body bytes a request says it has (0 if none).
function R.contentLength(head)
  return tonumber(head:match('\n[Cc][Oo][Nn][Tt][Ee][Nn][Tt]%-[Ll][Ee][Nn][Gg][Tt][Hh]:%s*(%d+)')) or 0
end

local function listing()
  local out = {}
  for _, c in ipairs(R.COMMANDS) do out[#out + 1] = {path = '/' .. c.path, does = c.desc} end
  return out
end

-- Decide what to do with a request. `run(command)` runs a command and `state()` returns the
-- session state; both come from the extension. Returns status code and a body table.
function R.handle(req, run, state)
  if not req then return 400, {ok = false, error = 'Not an HTTP request'} end
  if req.headers.origin or req.headers.referer then
    return 403, {ok = false, error = 'Requests from web pages are refused'}
  end
  if req.method ~= 'GET' and req.method ~= 'POST' then
    return 405, {ok = false, error = 'Use GET or POST'}
  end
  if req.path == '' then return 200, {ok = true, service = 'Rally Academy', commands = listing()} end
  if req.path == 'state' then return 200, {ok = true, state = state()} end
  local c = byPath[req.path]
  if not c then
    return 404, {ok = false, error = 'Unknown command /' .. req.path, commands = listing()}
  end
  local okRun, err = run(c)
  if okRun == false then return 500, {ok = false, command = c.path, error = tostring(err)} end
  return 200, {ok = true, command = c.path, state = state()}
end

local REASONS = {[200] = 'OK', [400] = 'Bad Request', [403] = 'Forbidden', [404] = 'Not Found',
                 [405] = 'Method Not Allowed', [413] = 'Payload Too Large', [500] = 'Internal Server Error'}

-- The full HTTP response for a status and an already-encoded JSON body.
function R.response(status, json)
  return string.format('HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\n'
    .. 'Cache-Control: no-store\r\nConnection: close\r\n\r\n%s', status, REASONS[status] or 'OK', #json, json)
end

return R
