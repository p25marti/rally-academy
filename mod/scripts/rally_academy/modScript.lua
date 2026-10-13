-- Runs when the mod is activated: load the GE extension and keep it loaded,
-- so drills/bindings work even before the HUD app is opened.
-- `load` and `setExtensionUnloadMode` are provided by BeamNG's modScript environment.
load("rallyAcademy")
setExtensionUnloadMode("rallyAcademy", "manual")
