# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.2] - 2026-11-05

### Fixed

Documentation only — no behaviour changes:

- The Requirements section claimed Yazi 26.9.1+; the plugin targets 26.1.22 (`--- @since`), and `rt.term.cell_size()`, the reason the claim was raised, exists since 25.12.29

## [1.0.1] - 2026-11-05

### Fixed

Documentation only — no behaviour changes:

- Installation pointed at `yazi-rs/plugins:markdown` instead of this repository (`ya pkg add juanlopez4691/markdown`)
- The performance notes claimed a fixed 150 DPI and ~1240×1754 px per A4 page; the raster is produced at the preview pane's device pixels and A4 is not used
- The page-boundaries caveat said WeasyPrint paginates to A4, when the page size is derived from the preview pane
- Page navigation was documented as `Shift+J`/`Shift+K`; the keys are `J`/`K` (`seek 5`/`-5` in Yazi's default keymap, clamped to one page per press)

### Added

- A Requirements section: Yazi 26.9.1+, `pandoc`, `weasyprint`, `pdftoppm`/`pdfinfo`
- A cache/geometry caveat: the PDF and page caches are keyed by pane geometry and cell size, so a resize or a terminal font change re-renders the current file once
- A note that the plugin-local venv is machine-local, and that `ya pkg` deploys read-only files (edit from a clone, then redeploy)

## [1.0.0] - 2026-11-05

### Changed

- Preview geometry now follows the pane: the `@page` aspect ratio is exactly the preview pane's (from `job.area` and `rt.term.cell_size()`), and Pandoc's `max-width: 36em` body cap is overridden, so a page fills 100% of the column width instead of being letterboxed by Yazi's fit-to-area scaling
- The raster is generated at the pane's *device* pixel size (DPI derived from the terminal's cell size) instead of a fixed 150 DPI — Yazi never upscales a preview, so a smaller raster is drawn narrower than the column
- PDF/JPEG caches are keyed by pane geometry and cell size, so a resize or font change re-renders instead of reusing a stale raster
- Pandoc's HTML is cached per file: it does not depend on the pane geometry, so re-renders after a resize skip Pandoc (~50ms, ~300ms on a cold process)
- `ya.image_precache` is no longer called: the raster already matches the pane's device pixels, so it only decoded and re-encoded the page (~0.2s for a 16 MP raster)
- `yazi.log` gains a hint when `preview.max_width`/`max_height` are what limits the preview size

### Fixed

- Pages could render partially, with a grey band at the bottom: pdftoppm wrote straight to the final cache path, so a reader (a quick `J` while the neighbour pre-render was still running, or the preloader racing the peek) could open a half-written JPEG, and the decoder pads the missing bytes with grey. Pages are now written to a temp file and atomically renamed
- Concurrent renders could collide on a shared temp name (`$$` was inside a shell-quoted path, so it stayed literal) and fail with `mv: rename … No such file or directory`
- `seek` read the plugin context (`cx`) outside `ya.sync()`, which aborts the call in Yazi 26.x — `J`/`K` paging did nothing

## [0.1.0] - 2026-06-10

### Added

- Image-based markdown preview via `pandoc → weasyprint → pdftoppm` pipeline
- Single shared PDF per file, cached at a stable path
- Per-page JPEG cache with directional neighbor pre-rendering (covers ±1–3 pages in scroll direction for instant sequential navigation)
- `weasyprint` resolved from PATH; plugin-local venv at `venv/bin/weasyprint` used as fallback if present
- `--base-url` passed to weasyprint so relative images and local CSS in markdown resolve correctly
- Atomic PDF write (tmp file + `mv`) prevents corrupt output under concurrent previewer/preloader access
- `LC_ALL=C` on pdftoppm for locale-independent last-page detection
- Support for `.md`, `.mdx`, and `.markdown` file extensions

[1.0.2]: https://github.com/juanlopez4691/markdown.yazi/releases/tag/v1.0.2
[1.0.1]: https://github.com/juanlopez4691/markdown.yazi/releases/tag/v1.0.1
[1.0.0]: https://github.com/juanlopez4691/markdown.yazi/releases/tag/v1.0.0
[0.1.0]: https://github.com/juanlopez4691/markdown.yazi/releases/tag/v0.1.0
