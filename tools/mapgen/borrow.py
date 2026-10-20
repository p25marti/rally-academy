"""Borrow definitions from the game's stock levels for generated levels (tools/mapgen/build.py).

Meshes and textures in the shared packs (/assets/...) are always mounted, but the material definitions that tie a
mesh to its textures, and setups such as grass cover, live inside each stock level. This finds them by name in the
stock levels' files and checks that everything they reference is in the shared packs, so a borrowed definition
can't point into a level that isn't loaded. Read-only; needs the game install.
"""
import glob
import json
import re
import zipfile
from pathlib import Path


def lenient_json(text):
    """BeamNG's JSON files allow trailing commas and // comments."""
    text = re.sub(r"(?m)^\s*//[^\n]*", "", text)
    return json.loads(re.sub(r",\s*([}\]])", r"\1", text))


class Stock:
    def __init__(self, game):
        self.game = Path(game)
        self._packs = None
        self._levels = {}

    def packs(self):
        """Every file path in the shared packs, lowercase and without extension (a .png reference loads the .dds)."""
        if self._packs is None:
            self._packs = set()
            for zp in glob.glob(str(self.game / "content" / "assets" / "**" / "*.zip"), recursive=True):
                for n in zipfile.ZipFile(zp).namelist():
                    self._packs.add("/" + n.rsplit(".", 2)[0].lower())
        return self._packs

    def shared(self, path):
        return path.rsplit(".", 2)[0].lower() in self.packs()

    def level(self, name):
        if name not in self._levels:
            self._levels[name] = zipfile.ZipFile(self.game / "content" / "levels" / f"{name}.zip")
        return self._levels[name]

    def objects(self, level, cls):
        """{name: object} of a class from a stock level's items.level.json files."""
        z, out = self.level(level), {}
        for n in z.namelist():
            if n.endswith("items.level.json"):
                for line in z.read(n).decode("utf-8", "replace").splitlines():
                    if f'"class":"{cls}"' in line:
                        o = json.loads(line)
                        out[o.get("name")] = o
        return out

    def materials(self, level):
        """{mapTo: definition} from every materials file of a stock level."""
        z, out = self.level(level), {}
        for n in z.namelist():
            if n.endswith("materials.json"):
                try:
                    data = lenient_json(z.read(n).decode("utf-8", "replace"))
                except ValueError:
                    continue
                for k, v in data.items():
                    if isinstance(v, dict) and v.get("class") == "Material":
                        out.setdefault(v.get("mapTo", k), v)
        return out

    def material(self, level, name):
        """A material from a stock level whose textures are all in the shared packs; raises otherwise."""
        m = self.materials(level).get(name)
        if m is None:
            raise SystemExit(f"material {name} not found in {level}")
        bad = [t for t in re.findall(r'"(/[^"]+\.(?:png|dds|jpg))"', json.dumps(m)) if not self.shared(t)]
        if bad:
            raise SystemExit(f"material {name} ({level}) uses textures outside the shared packs: {bad}")
        return m
