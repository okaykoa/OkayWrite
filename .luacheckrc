std = "lua51"
-- KOReader globals available to userpatches at runtime.
globals = { "G_reader_settings" }
read_globals = { "require", "dofile" }
-- Patches intentionally shadow/extend module methods; allow it.
ignore = { "212", "213" } -- unused arg / unused loop var