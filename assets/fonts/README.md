# Workspace typography

The macOS workspace pairs **Manrope** for the brand and headings (600–700) with
**Inter** for navigation, labels, and supporting text (400–600). The geometric
headings echo the rounded sidebar; restrained text weights keep dense settings readable.
Native controls use Inter while retaining native keyboard and accessibility behavior.
Monospaced receiver identifiers retain their aligned diagnostic font.

Spacing follows shared 4/8/12/16/24/28-point values: 24 between page sections,
24 inside standard cards, 16 between form groups, 12 between controls,
and 28 at page edges. Dense remote diagrams keep their geometry.

These variable TrueType fonts are bundled offline and registered only for the
app process. They are not installed into the user's font library. A system-font
fallback keeps the interface usable if a resource cannot be loaded.

Downloaded from the Google Fonts repository on 2026-10-30:

- Manrope: https://github.com/google/fonts/tree/main/ofl/manrope
- Inter: https://github.com/google/fonts/tree/main/ofl/inter
- Inter design reference: https://rsms.me/inter/

Both families use the SIL Open Font License 1.1. Keep `Manrope-OFL.txt` and
`Inter-OFL.txt` alongside the fonts when redistributing them.

SHA-256:

- `Manrope.ttf`: `3ae11c49db0455a3cc33e37d380f20fdb8c7f8b41dc07625c177e3d87a9d6ae6`
- `Inter.ttf`: `29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031`

## Windows typography

Windows uses the native **Segoe UI** family for controls and body text, with
**Segoe UI Semibold** for headings and emphasis. Labels and custom controls use
the Windows GDI text renderer for consistent metrics and small-size rendering.
Text follows the user's Windows font-smoothing settings; the app does not change
system preferences. Per-monitor DPI awareness is configured in both the manifest
and Windows Forms startup.

The static Manrope/Inter derivatives in `windows/` are retained as design assets
but are no longer loaded or distributed by the Windows app. They were generated
with `scripts/generate-windows-fonts.py`; their original license files remain here.

Windows uses the same logical spacing scale (4/8/12/16/24/28) with native DPI
scaling. Point sizes account for Windows' 96-DPI UI conventions.
