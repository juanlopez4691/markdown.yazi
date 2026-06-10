--- @since 26.1.22
local M = {}

local PANDOC = "pandoc"
local PDFTOPPM = "pdftoppm"
local CONFIG = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local VENV_WEASY = CONFIG .. "/yazi/plugins/markdown.yazi/venv/bin/weasyprint"
local weasy
local last_skip = { url = nil, skip = 0 }

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

local function pre_render(job, pdf, page)
	if page < 0 then
		return
	end
	local cache = ya.file_cache({ file = job.file, skip = page })
	if not cache or fs.cha(cache) then
		return
	end
	local dst = tostring(cache)
	if fs.cha(Url(dst .. ".jpg")) then
		return
	end
	local q = rt.preview.image_quality
	Command(PDFTOPPM):arg({
		"-f", tostring(page + 1),
		"-l", tostring(page + 1),
		"-singlefile",
		"-jpeg", "-jpegopt", "quality=" .. q,
		pdf, dst,
	}):env("LC_ALL", "C"):stdout(Command.NULL):stderr(Command.NULL):spawn()
end

local function render_neighbors(job, pdf, prev)
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
		pre_render(job, pdf, p)
	end
end

function M:peek(job)
	local start, cache = os.clock(), ya.file_cache(job)
	if not cache then
		return
	end

	local ok, err, bound = self:preload(job)
	if bound and bound > 0 then
		return ya.emit("peek", { bound - 1, only_if = job.file.url, upper_bound = true })
	elseif not ok or err then
		return ya.preview_widget(job, err)
	end

	ya.sleep(math.max(0, rt.preview.image_delay / 1000 + start - os.clock()))
	local src = fs.cha(cache) and cache or Url(tostring(cache) .. ".jpg")
	local _, err = ya.image_show(src, job.area)
	ya.preview_widget(job, err)
end

function M:seek(job)
	local h = cx.active.current.hovered
	if h and h.url == job.file.url then
		local step = ya.clamp(-1, job.units, 1)
		ya.emit("peek", { math.max(0, cx.active.preview.skip + step), only_if = job.file.url })
	end
end

function M:preload(job)
	local cache = ya.file_cache(job)
	if not cache or fs.cha(cache) then
		return true
	end

	local url_str = tostring(job.file.url)
	local prev = last_skip.url == url_str and last_skip.skip or job.skip
	last_skip = { url = url_str, skip = job.skip }
	local pdf = tostring(ya.file_cache({ file = job.file, skip = 0 })) .. ".pdf"
	local jpg = tostring(cache) .. ".jpg"

	if fs.cha(Url(jpg)) then
		render_neighbors(job, pdf, prev)
		return ya.image_precache(Url(jpg), cache)
	end

	if not fs.cha(Url(pdf)) then
		if not weasy then
			weasy = fs.cha(Url(VENV_WEASY)) and VENV_WEASY or "weasyprint"
		end
		local path = tostring(job.file.path)
		local dir = path:match("^(.*)/[^/]*$") or "."
		local qpdf = ya.quote(pdf)
		local cmd = string.format(
			'set -o pipefail && tmp=%s.$$.tmp && trap \'rm -f "$tmp"\' EXIT && %s -f markdown -t html -s %s | %s --base-url %s - "$tmp" && mv -f "$tmp" %s',
			qpdf, PANDOC, ya.quote(path), ya.quote(weasy), ya.quote(dir .. "/"), qpdf
		)
		local err = exec("sh", { "-c", cmd })
		if err then
			return true, Err("pandoc → weasyprint: %s", err)
		end
	end

	local q = rt.preview.image_quality
	-- stylua: ignore
	local output, err = Command(PDFTOPPM):arg({
		"-f", tostring(job.skip + 1),
		"-l", tostring(job.skip + 1),
		"-singlefile",
		"-jpeg", "-jpegopt", "quality=" .. q,
		pdf, tostring(cache),
	}):env("LC_ALL", "C"):output()

	if not output then
		return true, Err("pdftoppm: %s", err)
	elseif not output.status.success then
		local pages = job.skip > 0 and tonumber(output.stderr:match("the last page %((%d+)%)"))
		return true, Err("pdftoppm: %s", output.stderr), pages
	end

	render_neighbors(job, pdf, prev)
	return ya.image_precache(Url(jpg), cache)
end

return M