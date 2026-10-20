-- Surface variants (docs/decisions/0009-surface-variants.md): a drill's `variants` become drills of their own,
-- id '<drill>-<variant>' (A01-snow), so progress, medals, saved setups and fixtures stay per surface with no
-- other change. A variant names its venue and may override rules: an override replaces every base rule of the
-- same type (or is added), in the base rules and in each medal tier, the way a tier rule replaces base rules.
-- Pure Lua: no engine calls (tests/lua/test_variants.lua).
local V = {}

local function copy(t)
  if type(t) ~= 'table' then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = copy(v) end
  return out
end

-- Base rules with each override replacing the rules of its type (in place of the first one), or appended.
function V.mergeRules(base, overrides)
  local byType = {}
  for _, r in ipairs(overrides or {}) do byType[r.type] = byType[r.type] or {}; table.insert(byType[r.type], r) end
  local out, used = {}, {}
  for _, r in ipairs(base or {}) do
    local over = byType[r.type]
    if not over then
      table.insert(out, copy(r))
    elseif not used[r.type] then
      used[r.type] = true
      for _, o in ipairs(over) do table.insert(out, copy(o)) end
    end
  end
  for _, r in ipairs(overrides or {}) do
    if not used[r.type] then table.insert(out, copy(r)) end
  end
  return out
end

-- The family's surfaces for the UI: {{id = 'A01', name = 'Dirt'}, {id = 'A01-snow', name = 'Snow'}, ...}.
function V.surfaces(lesson)
  local out = {{id = lesson.id, name = lesson.surface or 'Standard'}}
  for _, v in ipairs(lesson.variants or {}) do table.insert(out, {id = lesson.id .. '-' .. v.id, name = v.name}) end
  return out
end

-- The variants of a drill as full drills (an empty list when it has none).
function V.expand(lesson)
  local out = {}
  if type(lesson.variants) ~= 'table' then return out end
  local surfaces = V.surfaces(lesson)
  for _, v in ipairs(lesson.variants) do
    local d = copy(lesson)
    d.variants = nil
    d.id, d.variantOf, d.surface, d.surfaces = lesson.id .. '-' .. v.id, lesson.id, v.name, surfaces
    d.environment = d.environment or {}
    d.environment.venue = v.venue or d.environment.venue
    if v.areaHint then d.environment.areaHint = v.areaHint end
    if v.vehicle then d.vehicle = copy(v.vehicle) end
    local a = d.assessment or {}
    d.assessment = a
    a.rules = V.mergeRules(a.rules, v.rules)
    local tierOver = {}
    for _, t in ipairs(v.tiers or {}) do tierOver[t.name] = t.rules end
    for _, t in ipairs(a.tiers or {}) do t.rules = V.mergeRules(t.rules, tierOver[t.name]) end
    if v.successDefinition then a.successDefinition = v.successDefinition end
    table.insert(out, d)
  end
  return out
end

return V
