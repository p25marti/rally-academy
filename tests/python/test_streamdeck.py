"""The shared Stream Deck profile (extras/streamdeck) sends exactly the mod's default keys (docs/STREAM_DECK.md)."""
import json
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROFILE = ROOT / "extras" / "streamdeck" / "rally_academy.streamDeckProfile"
BINDINGS = ROOT / "mod" / "settings" / "inputmaps" / "keyboard_rallyAcademy.json"
VK_F13 = 0x7C  # Windows virtual-key codes: F13 to F24 are 0x7C to 0x87


def profile_keys():
    """{'column,row': 'shift f15'} for every Hotkey key in the profile."""
    keys = {}
    with zipfile.ZipFile(PROFILE) as z:
        for name in z.namelist():
            if name.count("/Profiles/") == 1 and name.endswith("/manifest.json") and name.count("/") == 4:
                for ctrl in json.loads(z.read(name)).get("Controllers") or []:  # an empty page has none
                    for pos, action in (ctrl.get("Actions") or {}).items():
                        hk = action["Settings"]["Hotkeys"][0]
                        f = hk["NativeCode"] - VK_F13 + 13
                        keys[pos] = ("shift " if hk["KeyShift"] else "") + f"f{f}"
    return keys


class StreamDeckProfileTest(unittest.TestCase):
    def test_the_profile_sends_every_default_key_once(self):
        sent = sorted(profile_keys().values())
        bound = sorted(b["control"] for b in json.loads(BINDINGS.read_text(encoding="utf-8"))["bindings"])
        self.assertEqual(sent, bound)


if __name__ == "__main__":
    unittest.main()
