-- Minimal, dependency-free test runner for LuaJIT (the Lua BeamNG uses).
-- Usage: luajit tests/lua/run.lua <repo-root>
-- Discovers tests/lua/test_*.lua; each file returns a table of name -> function.

local root = arg[1] or '.'
package.path = table.concat({
  root .. '/tests/lua/?.lua',
  root .. '/tests/vendor/?.lua',
  root .. '/mod/lua/?.lua',
  package.path,
}, ';')

local function listTests()
  local files = {}
  local sep = package.config:sub(1, 1)
  local cmd = sep == '\\'
    and ('dir /b "' .. root .. '\\tests\\lua\\test_*.lua" 2>nul')
    or ('ls "' .. root .. '/tests/lua/" 2>/dev/null')
  local p = io.popen(cmd)
  for name in p:lines() do
    if name:match('^test_.*%.lua$') then table.insert(files, name) end
  end
  p:close()
  table.sort(files)
  return files
end

local passed, failed = 0, 0
for _, file in ipairs(listTests()) do
  local modname = file:gsub('%.lua$', '')
  local ok, suite = pcall(require, modname)
  if not ok then
    failed = failed + 1
    print(('FAIL %s (load error)\n     %s'):format(file, tostring(suite)))
  else
    local names = {}
    for name in pairs(suite) do table.insert(names, name) end
    table.sort(names)
    for _, name in ipairs(names) do
      local tok, err = xpcall(suite[name], debug.traceback)
      if tok then
        passed = passed + 1
        print(('ok   %s :: %s'):format(modname, name))
      else
        failed = failed + 1
        print(('FAIL %s :: %s\n     %s'):format(modname, name, tostring(err):gsub('\n', '\n     ')))
      end
    end
  end
end

print(('\n%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
