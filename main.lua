--- @since 26.1.22
local M = {}

local PANDOC = "pandoc"
local PDFTOPPM = "pdftoppm"
local CONFIG = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local VENV_WEASY = CONFIG .. "/yazi/plugins/markdown.yazi/venv/bin/weasyprint"
local weasy
local last_skip = { url = nil, skip = 0 }

-- Page typography: CSS pixels per cell. 8 keeps roughly 50-60 characters per
-- line at the default 16px body font, no matter how wide the pane is.
local CSS_CELL_W = 8
-- Pane geometry is quantized to these cell steps, so that resizing the pane
-- does not re-render the document on every single cell change.
local QW, QH = 8, 4
-- Cell size in device pixels, used only if the terminal doesn't report one.
local FALLBACK_CW, FALLBACK_CH = 8, 16
-- Below this raster width the preview looks blurry; a hint is logged instead.
local MIN_DPI = 60

local function cell_size()
	local cw, ch = rt.term.cell_size()
	cw, ch = tonumber(cw), tonumber(ch)
	if cw and ch and cw > 1 and ch > 1 then
		return cw, ch
	end
	return FALLBACK_CW, FALLBACK_CH
end

-- One render geometry. The page aspect ratio is made identical to the preview
-- pane's, so Yazi's fit-to-area scaling fills the whole column width instead of
-- letterboxing it; and the raster is sized to the pane's *device* pixels, so
-- Yazi never has to shrink the image below the column width (it never upscales).
local function geometry(area)
	local w = math.max(QW, math.floor(area.w / QW + 0.5) * QW)
	local h = math.max(QH, math.floor(area.h / QH + 0.5) * QH)
	local cw, ch = cell_size()

	local css_w = w * CSS_CELL_W
	local css_h = css_w * (h * ch) / (w * cw)
	local want = 96 * (w * cw) / css_w

	local maxw, maxh = tonumber(rt.preview.max_width), tonumber(rt.preview.max_height)
	local dpi = want
	if maxw and maxh and maxw > 0 and maxh > 0 then
		dpi = math.min(dpi, 96 * math.min(maxw / css_w, maxh / css_h))
	end

	return {
		w = w,
		h = h,
		cw = cw,
		ch = ch,
		css_w = css_w,
		css_h = css_h,
		dpi = math.max(24, math.floor(dpi + 0.5)),
		ideal = math.floor(want + 0.5),
	}
end

local function page_css(g)
	local margin = math.max(8, math.min(40, math.floor(g.css_w * 0.06)))
	return string.format(
		[[@page { size: %dpx %dpx; margin: %dpx }
html, body { max-width: none !important; margin: 0 !important; padding: 0 !important }]],
		math.floor(g.css_w + 0.5),
		math.floor(g.css_h + 0.5),
		margin
	)
end

local function suffix(g)
	-- The `v3` tag invalidates anything written by an older rendering policy.
	return string.format("-v3-%dx%d-c%dx%d", g.w, g.h, g.cw, g.ch)
end

-- Display file for one page. Always the JPEG itself: it is written atomically by
-- pdftoppm (see page_cmd), so its presence means it is complete.
local function page_url(job, skip, g)
	local c = ya.file_cache({ file = job.file, skip = skip })
	return c and Url(tostring(c) .. suffix(g) .. ".jpg")
end

local function pdf_path(job, g)
	local c = ya.file_cache({ file = job.file, skip = 0 })
	return c and (tostring(c) .. suffix(g) .. ".pdf")
end

-- Rasterize one page. pdftoppm writes straight to its output path, so writing to
-- the final name races with any reader (a half-written JPEG decodes into a page
-- that is only partly rendered — the grey band). Render to a temp name and rename
-- instead; the rename is atomic, so a visible page file is always complete.
local function page_cmd(pdf, g, page, dst)
	-- `$$` must stay outside the quotes, otherwise it is a literal "$" rather than
	-- the shell's PID and two concurrent renders share one temp file.
	return string.format(
		[[t=%s.tmp.$$; trap 'rm -f "$t.jpg"' EXIT; %s -r %d -f %d -l %d -singlefile -jpeg -jpegopt quality=%d %s "$t" && mv -f "$t.jpg" %s]],
		ya.quote(dst),
		PDFTOPPM,
		g.dpi,
		page + 1,
		page + 1,
		rt.preview.image_quality,
		ya.quote(pdf),
		ya.quote(dst)
	)
end

local function exec(cmd, args)
	-- stylua: ignore
	local o, e = Command(cmd):arg(args):output()
	if not o then
		return e
	end
	if not o.status.success then
		return o.stderr ~= "" and o.stderr or "command failed"
	end
end

local function warn_if_capped(g)
	if g.dpi < g.ideal then
		ya.dbg(
			"markdown: rasterizing at %d DPI instead of %d — pane exceeds preview.max_width/max_height (%sx%s); raise them to fill the column",
			g.dpi,
			g.ideal,
			tostring(rt.preview.max_width),
			tostring(rt.preview.max_height)
		)
	end
end

local function pre_render(job, pdf, page, g)
	if page < 0 then
		return
	end
	local dst = page_url(job, page, g)
	if not dst or fs.cha(dst) then
		return
	end
	Command("sh"):arg({ "-c", page_cmd(pdf, g, page, tostring(dst)) }):env("LC_ALL", "C"):stdout(Command.NULL):stderr(Command.NULL):spawn()
end

local function render_neighbors(job, pdf, prev, g)
	local skip = job.skip
	local delta = skip - prev
	local pages
	if delta == 1 then
		pages = { skip + 1, skip + 2, skip + 3, skip - 1 }
	elseif delta == -1 then
		pages = { skip - 1, skip - 2, skip - 3, skip + 1 }
	else
		pages = { skip - 1, skip + 1 }
	end
	for _, p in ipairs(pages) do
		pre_render(job, pdf, p, g)
	end
end

function M:peek(job)
	local start = os.clock()
	local g = geometry(job.area)
	local src = page_url(job, job.skip, g)
	if not src then
		return
	end

	local ok, err, bound = self:preload(job)
	if bound and bound > 0 then
		return ya.emit("peek", { bound - 1, only_if = job.file.url, upper_bound = true })
	elseif not ok or err then
		return ya.preview_widget(job, err)
	end

	ya.sleep(math.max(0, rt.preview.image_delay / 1000 + start - os.clock()))
	local shown, err = ya.image_show(src, job.area)
	if shown and shown.w and shown.w < job.area.w then
		ya.dbg(
			"markdown: preview occupies %d of %d columns — raster too small, raise preview.max_width/max_height (%sx%s)",
			shown.w,
			job.area.w,
			tostring(rt.preview.max_width),
			tostring(rt.preview.max_height)
		)
	end
	ya.preview_widget(job, err)
end

local preview_skip = ya.sync(function(state)
	return cx.active.preview.skip
end)

function M:seek(job)
	local step = ya.clamp(-1, job.units, 1)
	ya.emit("peek", { math.max(0, preview_skip() + step), only_if = job.file.url })
end

function M:preload(job)
	local g = geometry(job.area)
	local dst = page_url(job, job.skip, g)
	if not dst or fs.cha(dst) then
		return true
	end

	local url_str = tostring(job.file.url)
	local prev = last_skip.url == url_str and last_skip.skip or job.skip
	last_skip = { url = url_str, skip = job.skip }
	local pdf = pdf_path(job, g)

	if not fs.cha(Url(pdf)) then
		if not weasy then
			weasy = fs.cha(Url(VENV_WEASY)) and VENV_WEASY or "weasyprint"
		end
		warn_if_capped(g)
		local path = tostring(job.file.path)
		local dir = path:match("^(.*)/[^/]*$") or "."
		local css = pdf .. ".css"
		local ok, err = fs.write(Url(css), page_css(g))
		if not ok then
			return true, Err("css: %s", tostring(err))
		end
		-- The Pandoc HTML does not depend on the pane geometry, so it is cached
		-- per file: a re-render only has to run WeasyPrint (~0.3s vs ~0.4s), and
		-- `-u` skips PDF stream compression, which is another third of its cost.
		local html = (tostring(ya.file_cache({ file = job.file, skip = 0 })) or "") .. ".html"
		local qpdf, qhtml = ya.quote(pdf), ya.quote(html)
		local cmd = string.format(
			[[html=%s
tmp=%s.$$.tmp
trap 'rm -f "$tmp" "$html.$$.tmp"' EXIT
if [ ! -s "$html" ]; then %s -f markdown -t html -s %s -o "$html.$$.tmp" && mv -f "$html.$$.tmp" "$html"; fi
%s --base-url %s -s %s "$html" "$tmp" && mv -f "$tmp" %s]],
			qhtml,
			qpdf,
			PANDOC,
			ya.quote(path),
			ya.quote(weasy),
			ya.quote(dir .. "/"),
			ya.quote(css),
			qpdf
		)
		local err = exec("sh", { "-c", cmd })
		if err then
			return true, Err("pandoc → weasyprint: %s", err)
		end
	end

	local cmd = page_cmd(pdf, g, job.skip, tostring(dst))
	ya.dbg("md: CMD %s", cmd)
	local output, err = Command("sh"):arg({ "-c", cmd }):env("LC_ALL", "C"):output()

	if not output then
		return true, Err("pdftoppm: %s", err)
	elseif not output.status.success then
		local pages = job.skip > 0 and tonumber(output.stderr:match("the last page %((%d+)%)"))
		return true, Err("pdftoppm: %s", output.stderr), pages
	end

	render_neighbors(job, pdf, prev, g)
	return true
end

return M
