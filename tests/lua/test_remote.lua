-- Remote commands over local HTTP (remote.lua, pure) and through the extension with a faked
-- LuaSocket (beamng_stubs.lua): the Stream Deck's web-request keys.
local Remote = require('ge/extensions/rallyAcademy/remote')
local json = require('json')
local H = require('ra_helpers')
local eq, has = H.eq, H.has
local T = {}

local function get(path, extra)
  return 'GET ' .. path .. ' HTTP/1.1\r\nHost: 127.0.0.1:29393\r\n' .. (extra or '') .. '\r\n'
end

-- Body of an HTTP response as a table, and its status code.
local function reply(raw)
  local status = tonumber(raw:match('^HTTP/1%.1 (%d+)'))
  local body = raw:match('\r\n\r\n(.*)$')
  return status, json.decode(body)
end

function T.requests_parse_to_a_lower_case_path_without_query()
  local r = Remote.parseRequest('POST /Retry/?x=1 HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n')
  eq(r.method, 'POST', 'method')
  eq(r.path, 'retry', 'path')
  eq(r.headers.host, 'x', 'headers')
  eq(Remote.parseRequest('garbage'), nil, 'not HTTP')
  eq(Remote.contentLength('POST / HTTP/1.1\r\ncontent-length: 12\r\n'), 12, 'body length')
end

function T.handle_routes_known_commands_and_lists_them()
  local ran
  local run = function(c) ran = c; return true end
  local state = function() return {phase = 'ready'} end
  local status, body = Remote.handle(Remote.parseRequest(get('/next')), run, state)
  eq(status, 200, 'ok')
  eq(ran.fn, 'selectNext', 'ran Next drill')
  eq(body.state.phase, 'ready', 'state in the reply')
  Remote.handle(Remote.parseRequest(get('/miss')), run, state)
  eq(ran.arg, false, 'miss passes false')
  local _, list = Remote.handle(Remote.parseRequest(get('/')), run, state)
  eq(#list.commands, #Remote.COMMANDS, 'GET / lists every command')
  status, body = Remote.handle(Remote.parseRequest(get('/launch-missiles')), run, state)
  eq(status, 404, 'unknown command')
  has(body.error, 'Unknown command /launch-missiles')
end

function T.browser_requests_and_other_methods_are_refused()
  local ran = false
  local run = function() ran = true; return true end
  local status = Remote.handle(Remote.parseRequest(get('/retry', 'Origin: https://example.com\r\n')), run, function() end)
  eq(status, 403, 'a web page (Origin) is refused')
  status = Remote.handle(Remote.parseRequest(get('/retry', 'Referer: https://example.com/\r\n')), run, function() end)
  eq(status, 403, 'a link or image (Referer) is refused')
  status = Remote.handle(Remote.parseRequest('DELETE /retry HTTP/1.1\r\n'), run, function() end)
  eq(status, 405, 'only GET and POST')
  eq(ran, false, 'nothing ran')
end

function T.the_extension_listens_on_localhost_only()
  local h = H.setup()
  eq(h.net.bound, '127.0.0.1:29393', 'bound to localhost on the default port')
  eq(h.net.listening, true, 'listening')
end

function T.a_request_runs_the_command_and_answers_with_the_state()
  local h, M = H.setup()
  M.select('A01')
  local c = h.request(get('/next'))
  M.onUpdate(0.016, 0.016)
  eq(h.lastState().selected, 'A02', 'Next drill ran')
  local status, body = reply(c.sent)
  eq(status, 200, 'HTTP 200')
  eq(body.state.drill, 'A02', 'reply has the new state')
  eq(c.closed, true, 'connection closed')
  has(h.logText('rallyAcademy'), 'remote: /next')
end

function T.a_request_arriving_in_pieces_waits_for_its_head_and_body()
  local h, M = H.setup()
  M.select('A01')
  local c = h.request('POST /next HTTP/1.1\r\nContent-Length: 2\r\n', '\r\n', '{}')
  M.onUpdate(0.016, 0.016)
  eq(c.sent, '', 'head not finished yet')
  M.onUpdate(0.016, 0.016)
  eq(c.sent, '', 'body not here yet')
  M.onUpdate(0.016, 0.016)
  eq(h.lastState().selected, 'A02', 'ran once the body arrived')
  eq(reply(c.sent), 200, 'answered')
end

function T.a_stalled_client_is_dropped_without_running_anything()
  local h, M = H.setup()
  M.select('A01')
  local c = h.request('GET /next HTTP/1.1\r\n')
  for _ = 1, 30 do M.onUpdate(0.1, 0.1) end
  eq(c.closed, true, 'dropped after the timeout')
  eq(c.sent, '', 'no answer')
  eq(h.lastState().selected, 'A01', 'nothing ran')
end

function T.state_endpoint_reports_the_session()
  local h, M = H.setup()
  M.select('A01')
  local c = h.request(get('/state'))
  M.onUpdate(0.016, 0.016)
  local _, body = reply(c.sent)
  eq(body.state.drill, 'A01', 'drill')
  eq(body.state.title, 'Steering and spatial awareness', 'title')
  eq(body.state.autoRetry, true, 'auto-retry')
end

function T.remote_can_be_turned_off_and_survives_a_busy_port()
  local h, M = H.setup()
  M.setRemote(false)
  eq(h.net.listening, false, 'stopped')
  eq(jsonReadFile('settings/rallyAcademy/prefs.json').remote, false, 'saved')
  local M2 = H.reloadExtension()
  eq(h.net.listening, false, 'stays off after a reload')
  M2.setRemote(true)
  eq(h.net.listening, true, 'back on')
  M2.onExtensionUnloaded()
  eq(h.net.listening, false, 'unloading frees the port')
  local h2 = H.stubs.install()
  h2.net.bindError = 'address already in use'
  local M3 = H.stubs.loadExtension('rallyAcademy')
  M3.onExtensionLoaded()
  has(h2.logText('rallyAcademy'), 'remote commands off: could not listen on 127.0.0.1:29393 (address already in use)')
  M3.onUpdate(0.016, 0.016) -- and the mod still runs
end

return T
