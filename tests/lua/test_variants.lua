-- Surface variants (variants.lua, pure; ADR 0009): expansion into drills of their own, rule overrides, and how the
-- extension lists and selects them.
local V = require('ge/extensions/rallyAcademy/variants')
local H = require('ra_helpers')
local eq, has = H.eq, H.has
local T = {}

local BASE = {
  id = 'A05', title = 'Braking accuracy', surface = 'Dirt',
  environment = {venue = 'pg-dirt-strip', areaHint = 'dirt'},
  assessment = {
    rules = {{type = 'entry_speed', minKmh = 38}, {type = 'no_sustained_lockup', maxSeconds = 0.2}, {type = 'markers_clear'}},
    tiers = {{name = 'silver', rules = {{type = 'no_sustained_lockup', maxSeconds = 0.15}}},
             {name = 'gold', rules = {{type = 'no_sustained_lockup', maxSeconds = 0.1}}}},
  },
  variants = {
    {id = 'gravel', name = 'Gravel', venue = 'pg-gravel-strip'},
    {id = 'snow', name = 'Snow', venue = 'pg-snow-strip', areaHint = 'snow',
     rules = {{type = 'entry_speed', minKmh = 30}, {type = 'no_reverse', maxM = 0.3}},
     tiers = {{name = 'gold', rules = {{type = 'no_sustained_lockup', maxSeconds = 0.3}}}}},
  },
}

function T.each_variant_becomes_a_drill_on_its_own_venue()
  local vs = V.expand(BASE)
  eq(#vs, 2, 'two variants')
  eq(vs[1].id, 'A05-gravel', 'id')
  eq(vs[1].variantOf, 'A05', 'knows its base')
  eq(vs[1].surface, 'Gravel', 'surface name')
  eq(vs[1].environment.venue, 'pg-gravel-strip', 'own venue')
  eq(vs[1].environment.areaHint, 'dirt', 'hint inherited')
  eq(vs[2].environment.areaHint, 'snow', 'hint overridden')
  eq(vs[1].variants, nil, 'no nested variants')
  eq(vs[1].title, 'Braking accuracy', 'everything else inherited')
  eq(BASE.environment.venue, 'pg-dirt-strip', 'the base is untouched')
end

function T.an_override_replaces_rules_of_its_type_or_is_added()
  local snow = V.expand(BASE)[2].assessment
  eq(#snow.rules, 4, 'three base rules, one replaced, one added')
  eq(snow.rules[1].type, 'entry_speed', 'replaced in place')
  eq(snow.rules[1].minKmh, 30, 'with the override')
  eq(snow.rules[4].type, 'no_reverse', 'new rule appended')
  eq(snow.tiers[1].rules[1].maxSeconds, 0.15, 'silver not overridden')
  eq(snow.tiers[2].rules[1].maxSeconds, 0.3, 'gold overridden')
  eq(BASE.assessment.rules[1].minKmh, 38, 'base rules untouched')
end

function T.surfaces_list_the_family_base_first()
  local s = V.surfaces(BASE)
  eq(#s, 3, 'base and two variants')
  eq(s[1].id, 'A05', 'base first')
  eq(s[1].name, 'Dirt', 'base surface name')
  eq(s[3].id, 'A05-snow', 'variant id')
  eq(V.expand(BASE)[1].surfaces[2].name, 'Gravel', 'variants carry the family')
  eq(#V.expand({id = 'B01'}), 0, 'a drill without variants has none')
end

function T.the_extension_selects_variants_but_lists_only_base_drills()
  local h, M = H.setup()
  local listed = {}
  for _, l in ipairs(h.lastState().lessons) do listed[l.id] = l end
  eq(listed['A01-snow'], nil, 'variants are not in the drop-down')
  eq(type(listed.A01.surfaces), 'table', 'the base lists its surfaces')
  M.select('A01-snow')
  local s = h.lastState()
  eq(s.selected, 'A01-snow', 'a variant can be selected')
  eq(s.lesson.variantOf, 'A01', 'and knows its base')
  has(s.lesson.environment.mapDisplayName, 'snow strip', 'on its own venue')
  M.selectNext()
  eq(h.lastState().selected, 'A02', 'next drill after a variant is the next base drill')
end

return T
