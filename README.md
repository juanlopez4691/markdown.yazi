# markdown.yazi

Image-based Markdown previewer for [Yazi](https://github.com/sxyazi/yazi). Renders `.md`, `.mdx`, and `.markdown` files as full-resolution JPEG images, scaled to the preview pane.

<!-- TODO: add demo GIF -->
<!-- https://github.com/user-attachments/assets/... -->

## Requirements

- Yazi 26.9.1 or newer (the plugin reads the terminal's cell size via `rt.term.cell_size()` to rasterize at the pane's real resolution)
- `pandoc`
- `weasyprint` — either on `PATH` or in the plugin-local venv described below
- `pdftoppm` and `pdfinfo` (poppler)

## Installation

```sh
ya pkg add juanlopez4691/markdown
```

Then install the required tools:

```sh
# macOS
brew install pandoc poppler weasyprint

# Linux (APT)
sudo apt install pandoc poppler-utils weasyprint

# Linux (Pacman)
sudo pacman -S pandoc poppler python-weasyprint
```

Any installation method that puts a `weasyprint` binary on `PATH` works (e.g. `pipx install weasyprint`). Alternatively, a plugin-local venv at `~/.config/yazi/plugins/markdown.yazi/venv` is picked up automatically if present:

```sh
python3 -m venv ~/.config/yazi/plugins/markdown.yazi/venv
~/.config/yazi/plugins/markdown.yazi/venv/bin/pip install weasyprint
```

The venv is local to your machine and is not part of the package — a `ya pkg` deploy leaves it alone, but deleting the plugin directory takes it with it.

## Setup

Add this to your `~/.config/yazi/yazi.toml`:

```toml
[[plugin.prepend_previewers]]
url = "*.md"
run = "markdown"

[[plugin.prepend_previewers]]
url = "*.mdx"
run = "markdown"

[[plugin.prepend_previewers]]
url = "*.markdown"
run = "markdown"

[[plugin.prepend_preloaders]]
url = "*.md"
run = "markdown"

[[plugin.prepend_preloaders]]
url = "*.mdx"
run = "markdown"

[[plugin.prepend_preloaders]]
url = "*.markdown"
run = "markdown"
```

If your `EDITOR` env var has a prefix (e.g. `NVIM_APPNAME=nvim-lazyvim nvim`), update the opener:

```toml
[opener]
edit = [{ run = 'export "${EDITOR%% *}" && "${EDITOR#* }" "$@"', block = true, for = "unix" }]
```

## How it works

```
markdown.md  →  pandoc  →  HTML  →  weasyprint  →  PDF  →  pdftoppm  →  JPEG
```

Each step caches its output: Pandoc's HTML per file (it does not depend on the geometry), the PDF per file and pane geometry, and one JPEG per page. Adjacent pages are pre-rendered in the background so navigation is instant. Every artefact is written to a temp file and renamed into place, so a cached page is never read while it is still being written.

The page size is not fixed. WeasyPrint is given an `@page` size whose aspect ratio is exactly the preview pane's (from `job.area` and the terminal's cell size), and the raster is produced at the pane's *device* pixel size, so Yazi's fit-to-area scaling fills the whole column width instead of letterboxing it. Resizing the pane re-renders at the new geometry, quantized to 8×4 cells so dragging the pane border does not re-render on every cell.

> Yazi never upscales a preview: if `preview.max_width`/`max_height` are smaller than the pane's device pixels, the rendered page is shrunk and the preview ends up narrower than the column. Keep them generous (e.g. `4096`); the plugin logs a hint to `yazi.log` when that cap is what limits the preview.

## Usage

- **Preview**: select a markdown file in Yazi. The first page renders in ~0.5s; revisiting a file at the same pane size is instant.
- **Page navigation**: `J` (next page), `K` (previous page) — the same keys as Yazi's built-in PDF previewer.

## Performance

Measured on macOS for a ~10 KB document:

| Action                  | Time     | Notes                               |
| ----------------------- | -------- | ----------------------------------- |
| First page (cold)       | ~0.5s    | pandoc + weasyprint + pdftoppm      |
| Re-render after resize  | ~0.5s    | weasyprint + pdftoppm (HTML cached) |
| First page (PDF cached) | ~0.06s   | pdftoppm only                       |
| Subsequent pages        | instant  | pre-rendered JPEG from cache        |

About 0.3s of every WeasyPrint run is its own Python import, which is the floor for a cold render; Yazi's preloader renders the files visible in a folder in the background, which hides most of that in practice.

Pre-rendering covers 3 pages ahead in your travel direction, so sequential `J`/`K` navigation never hits a cold render. The raster matches the pane's device pixels (DPI derived from the terminal's cell size), so a page costs whatever the pane is tall rather than a fixed 150 DPI — a large preview is around 2000×2800 px per page.

## Caveats

### Python version (venv setups only)

If you use the optional plugin-local venv instead of a packaged WeasyPrint, the venv is bound to the Python version used to create it. If you upgrade Python, recreate it:

```sh
rm -rf ~/.config/yazi/plugins/markdown.yazi/venv
python3 -m venv ~/.config/yazi/plugins/markdown.yazi/venv
~/.config/yazi/plugins/markdown.yazi/venv/bin/pip install weasyprint
```

### Caches and geometry

The PDF and page caches are keyed by the pane geometry and the terminal's cell size, so resizing the pane — or changing the terminal font size — re-renders the current file once. Cached pages live in Yazi's preview cache directory (`$TMPDIR/yazi-$UID`, e.g. `…/yazi-501`) alongside the previews of everything else.

### Page boundaries

WeasyPrint paginates the HTML to pages whose size is derived from the preview pane, so the page count depends on the pane's shape. Markdown content does not naturally map to pages — breaks may occur mid-paragraph. Use `J`/`K` to move between pages.

### PATH

`pandoc`, `pdftoppm`, and `weasyprint` (unless using the venv) must be on `PATH` when Yazi starts.

### Very large files

Very long markdown files produce many PDF pages (~150–250 KB JPEG per page at typical pane sizes). Directional pre-rendering keeps sequential navigation smooth; only random jumps incur a cold `pdftoppm` call.

### Editing the plugin

Files deployed by `ya pkg` are sealed read-only. To change anything, work in a clone and push; then `ya pkg add juanlopez4691/markdown` (or `ya pkg upgrade`) redeploys it.

## License

This plugin is MIT-licensed. For more information check the [LICENSE](LICENSE) file.
