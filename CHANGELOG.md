# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.0]: https://github.com/juanlopez4691/markdown.yazi/releases/tag/v0.1.0
