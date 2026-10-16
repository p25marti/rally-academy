"""Client for BeamNG's in-game MCP server (JSON-RPC over HTTP, stdlib only).

The server ships with the game (0.39+) at http://127.0.0.1:29292/mcp. Some tools are
asynchronous: the first call starts the work and answers "call again", a later call
returns the result. `call` hides that.
"""
import base64
import json
import math
import time
import urllib.request

URL = "http://127.0.0.1:29292/mcp"


class GameError(RuntimeError):
    pass


def rpc(method, params=None, timeout=20):
    body = {"jsonrpc": "2.0", "id": 1, "method": method}
    if params is not None:
        body["params"] = params
    req = urllib.request.Request(URL, data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json",
                                          "Accept": "application/json, text/event-stream"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def _content(res):
    return res.get("result", {}).get("content", [])


def _text(res):
    return "".join(c.get("text", "") for c in _content(res))


def call(tool, args=None, retries=10):
    """Call a tool; retry while it answers "call again". Returns the text result."""
    res = rpc("tools/call", {"name": tool, "arguments": args or {}})
    for _ in range(retries):
        if "call again" not in json.dumps(res).lower():
            break
        time.sleep(0.4)
        res = rpc("tools/call", {"name": tool, "arguments": args or {}})
    if res.get("result", {}).get("isError"):
        raise GameError(_text(res))
    return _text(res)


def safe(fn, *args, **kw):
    """Call, but return "<ErrorName>" instead of raising (the server drops during map loads)."""
    try:
        return fn(*args, **kw)
    except Exception as e:  # noqa: BLE001 - any transport error means "not now"
        return f"<{type(e).__name__}>"


def lua(code):
    """Run GE Lua; `code` should `return` a value. Returns its text form."""
    return call("run_lua", {"code": code})


def lua_json(code):
    """Run GE Lua returning a table; decoded with the game's own jsonEncode."""
    return json.loads(lua(f"return jsonEncode((function() {code} end)())"))


def vlua(code):
    """Run Lua in the player's car. Async: the first call queues, the second reads."""
    call("run_lua_vehicle", {"code": code})
    time.sleep(1.2)
    out = call("run_lua_vehicle", {"code": code})
    try:
        return next(iter(json.loads(out).values()))
    except (ValueError, StopIteration, AttributeError):
        return out


def ui(js):
    """Run JavaScript in the UI. Avoid \\n escapes in `js`: they arrive as raw newlines."""
    out = call("ui_eval", {"js": js})
    try:
        return json.loads(out)
    except ValueError:
        return out


def inp(event, value):
    """Driver input to the player's car (throttle, brake, parkingbrake, steering)."""
    call("inject_input", {"event": event, "value": value})


def state():
    """((x, y, z), speed m/s) of the player's car."""
    s = lua("local v=be:getPlayerVehicle(0); local p=v:getPosition(); local vel=v:getVelocity(); "
            "return string.format('%.3f,%.3f,%.3f,%.3f', p.x, p.y, p.z, vel:length())")
    x, y, z, spd = (float(t) for t in s.split(","))
    return (x, y, z), spd


def dist(a, b):
    return math.dist(a[:2], b[:2])


def screenshot(path):
    """Save a small JPG of the game view (the game also keeps a copy under screenshots/mcp)."""
    for _ in range(12):
        res = rpc("tools/call", {"name": "screenshot_image", "arguments": {}})
        for c in _content(res):
            if c.get("type") == "image":
                with open(path, "wb") as f:
                    f.write(base64.b64decode(c["data"]))
                return path
        time.sleep(0.7)
    raise GameError("no screenshot")
