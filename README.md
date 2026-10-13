# Rally Academy

A BeamNG.drive mod for training rally driving on a sim rig.

## Layout

The repo root is the mod root, so it mirrors BeamNG's virtual filesystem:

```
scripts/rally_academy/modScript.lua   # auto-loads the extension when the mod is enabled
lua/ge/extensions/rallyAcademy.lua    # main game-engine extension
```

## Development setup (Windows)

Link the repo into BeamNG's unpacked mods folder so edits show up in game without zipping:

```bat
mklink /J "%LOCALAPPDATA%\BeamNG.drive\<version>\mods\unpacked\rally-academy" "%USERPROFILE%\Documents\git\rally-academy"
```

Then in game open the console (`~`) and run `extensions.reload("rallyAcademy")` (or press Ctrl+L to reload Lua).

## Packaging

Zip the contents of the repo root (not the folder itself), excluding `.git`, `README.md` and other dev files.
