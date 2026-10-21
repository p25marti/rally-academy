"""Surface variants, as the mod expands them (mod/lua/ge/extensions/rallyAcademy/variants.lua; ADR 0009): a drill's
`variants` become drills of their own, id '<drill>-<variant>', each on its own venue; a variant's rule overrides
replace every base rule of the same type (or are added), in the base rules and in each medal tier.
Stdlib only (dev.py validates with it; academy.py drives variants with it). Keep in step with variants.lua."""
import copy


def merge_rules(base, overrides):
    by_type = {}
    for r in overrides or []:
        by_type.setdefault(r["type"], []).append(r)
    out, used = [], set()
    for r in base or []:
        over = by_type.get(r.get("type"))
        if over is None:
            out.append(copy.deepcopy(r))
        elif r["type"] not in used:
            used.add(r["type"])
            out += copy.deepcopy(over)
    out += [copy.deepcopy(r) for r in overrides or [] if r["type"] not in used]
    return out


def surfaces(drill):
    return [{"id": drill["id"], "name": drill.get("surface", "Standard")}] + [
        {"id": f"{drill['id']}-{v['id']}", "name": v["name"]} for v in drill.get("variants") or []]


def expand(drill):
    """The drill's variants as full drills ([] when it has none)."""
    out = []
    for v in drill.get("variants") or []:
        d = copy.deepcopy(drill)
        d.pop("variants", None)
        d.update(id=f"{drill['id']}-{v['id']}", variantOf=drill["id"], surface=v["name"], surfaces=surfaces(drill))
        env = d.setdefault("environment", {})
        env["venue"] = v.get("venue", env.get("venue"))
        if "areaHint" in v:
            env["areaHint"] = v["areaHint"]
        if "vehicle" in v:
            d["vehicle"] = copy.deepcopy(v["vehicle"])
        a = d.setdefault("assessment", {})
        a["rules"] = merge_rules(a.get("rules"), v.get("rules"))
        tier_over = {t["name"]: t.get("rules") for t in v.get("tiers") or []}
        for t in a.get("tiers") or []:
            t["rules"] = merge_rules(t.get("rules"), tier_over.get(t["name"]))
        if "successDefinition" in v:
            a["successDefinition"] = v["successDefinition"]
        if "aiDemo" in v:
            a["aiDemo"] = v["aiDemo"]
        out.append(d)
    return out


def all_drills(exercises):
    """Every drill, each base followed by its variants."""
    out = []
    for d in exercises:
        if d.get("variants"):
            d = dict(d, surfaces=surfaces(d))  # as the mod does: the base lists its family too
        out.append(d)
        out += expand(d)
    return out
