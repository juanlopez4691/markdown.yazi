# markdown.yazi

Image-based Markdown previewer for [Yazi](https://github.com/sxyazi/yazi). Renders `.md`, `.mdx`, and `.markdown` files as full-resolution JPEG images — matching the graphical fidelity of Yazi's built-in PDF preview.

<!-- TODO: add demo GIF -->
<!-- https://github.com/user-attachments/assets/... -->

## Installation

```sh
ya pkg add yazi-rs/plugins:markdown
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

Each step caches its output (Pandoc's HTML per file, the PDF per file + pane geometry, one JPEG per page). The PDF is cached per-file and per preview-pane geometry; JPEGs are cached per-page. Adjacent pages are pre-rendered in the background so navigation is instant. Every page (and PDF) is written to a temp file and renamed into place, so a cached page is never read while it is still being written.

The page size is not fixed: WeasyPrint is given an `@page` size whose aspect ratio is exactly the preview pane's (from `job.area` and `rt.term.cell_size()`), and the raster is produced at the pane's *device* pixel size, so Yazi's fit-to-area scaling fills the full column width instead of being letterboxed. Resizing the pane re-renders at the new geometry (quantized to 8×4 cells to avoid thrashing while dragging).

> Yazi never upscales a preview: if `preview.max_width`/`max_height` are smaller than the pane's device pixels, the rendered page is shrunk and the preview ends up narrower than the column. Keep them generous (e.g. `4096`); the plugin logs a hint to `yazi.log` when the cap kicks in.

## Usage

- **Preview**: Select a markdown file in Yazi. The first page renders after ~0.5–1s, subsequent navigation is instant.
- **Page navigation**: `Shift+J` (next page), `Shift+K` (previous page) — same keys as Yazi's built-in PDF plugin.

## Performance

| Action                  | Time     | Notes                               |
| ----------------------- | -------- | ----------------------------------- |
| First page (cold)       | ~0.5s    | pandoc + weasyprint + pdftoppm      |
| Re-render after resize  | ~0.4s    | weasyprint + pdftoppm (HTML cached) |
| First page (PDF cached) | ~0.07s   | pdftoppm only                       |
| Subsequent pages        | instant  | pre-rendered JPEG from cache        |

Pre-rendering covers 3 pages ahead in your travel direction, so sequential J/K navigation never hits a cold render. pdftoppm runs at 150 DPI, producing ~1240×1754px JPEG per A4 page — matching Yazi's built-in PDF plugin.

## Caveats

### Python version (venv setups only)

If you use the optional plugin-local venv instead of a packaged WeasyPrint, the venv is bound to the Python version used to create it. If you upgrade Python, recreate it:

```sh
rm -rf ~/.config/yazi/plugins/markdown.yazi/venv
python3 -m venv ~/.config/yazi/plugins/markdown.yazi/venv
~/.config/yazi/plugins/markdown.yazi/venv/bin/pip install weasyprint
```

### Page boundaries

WeasyPrint paginates HTML to A4 pages. Markdown content does not naturally map to pages — breaks may occur mid-paragraph. Use `Shift+J`/`Shift+K` to scroll between pages.

### PATH

`pandoc`, `pdftoppm`, and `weasyprint` (unless using the venv) must be on `PATH` when Yazi starts.

### Very large files

Very long markdown files produce many PDF pages (~150–250KB JPEG per page). Directional pre-rendering keeps sequential navigation smooth; only random jumps incur a cold pdftoppm call.

## License

This plugin is MIT-licensed. For more information check the [LICENSE](LICENSE) file.
