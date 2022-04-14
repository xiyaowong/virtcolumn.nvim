--- vim.g.virtcolumn_char: ▕ by default

local api = vim.api
local fn = vim.fn
local ffi = require "ffi"

ffi.cdef "int curwin_col_off(void);"
---@diagnostic disable-next-line: undefined-field
local curwin_col_off = ffi.C.curwin_col_off

local NS = api.nvim_create_namespace "virt-column"

local function _refresh()
    local bufnr = api.nvim_get_current_buf()
    if not api.nvim_buf_is_loaded(bufnr) then
        return
    end

    local virtcolumn = vim.b.virtcolumn or vim.w.virtcolumn

    local local_cc = vim.wo.cc
    if not virtcolumn or local_cc ~= "" then
        virtcolumn = local_cc
        vim.wo.cc = ""
    end

    vim.b.virtcolumn = virtcolumn
    vim.w.virtcolumn = virtcolumn

    ---@type number[]
    local items = {}

    local textwidth = vim.opt.textwidth:get()
    for _, c in ipairs(vim.split(virtcolumn, ",")) do
        local item
        if c and c ~= "" then
            if vim.startswith(c, "+") then
                if textwidth ~= 0 then
                    item = textwidth + tonumber(c:sub(2))
                end
            elseif vim.startswith(virtcolumn, "-") then
                if textwidth ~= 0 then
                    item = textwidth - tonumber(c:sub(2))
                end
            else
                item = tonumber(c)
            end
        end
        if item and item > 0 then
            table.insert(items, item)
        end
    end
    table.sort(items, function(a, b)
        return a > b
    end)

    api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)

    if #items == 0 then
        return
    end

    local win_lines = vim.o.lines
    local offset = vim.fn.line "w0"
    -- Avoid flickering caused by winscrolled_timer
    offset = offset <= win_lines and 1 or offset - win_lines

    --                                                  Avoid flickering caused by winscrolled_timer
    --                                                                       ↓↓↓↓↓↓↓↓↓↓↓
    local lines = api.nvim_buf_get_lines(bufnr, offset - 1, vim.fn.line "w$" + win_lines, false)
    local width = api.nvim_win_get_width(0) - curwin_col_off()
    local tabstop = vim.opt.tabstop:get()
    local char = vim.g.virtcolumn_char or "▕"

    for i = 1, #lines do
        for _, item in ipairs(items) do
            local line = lines[i]:gsub("\t", string.rep(" ", tabstop))
            if width > item and api.nvim_strwidth(line) < item then
                api.nvim_buf_set_extmark(bufnr, NS, i + offset - 2, 0, {
                    virt_text = { { char, "VirtColumn" } },
                    virt_text_pos = "overlay",
                    hl_mode = "combine",
                    virt_text_win_col = item - 1,
                    priority = 0,
                })
            end
        end
    end
end

-- Avoid unnecessary refreshing as much as possible
local winscrolled_timer
local function refresh(args)
    ---@type string
    local event = args.event or ""
    if event == "WinScrolled" then
        if winscrolled_timer and winscrolled_timer:is_active() then
            winscrolled_timer:stop()
            winscrolled_timer:close()
        end
        winscrolled_timer = vim.defer_fn(_refresh, 100)
    elseif event:match "TextChanged" then
        local lines_count = fn.line "$"
        local need_refresh = vim.b.virtcolumn_lines_count ~= lines_count
        vim.b.virtcolumn_lines_count = lines_count
        if need_refresh then
            _refresh()
        end
    else
        _refresh()
    end
end

local function set_hl()
    local cc_bg = api.nvim_get_hl_by_name("ColorColumn", true).background
    if cc_bg then
        api.nvim_set_hl(0, "VirtColumn", { fg = cc_bg, default = true })
    else
        vim.cmd [[hi default link VirtColumn NonText]]
    end
end
set_hl()

local group = api.nvim_create_augroup("virtcolumn", {})
api.nvim_create_autocmd(
    { "WinScrolled", "TextChanged", "TextChangedI", "BufWinEnter", "InsertLeave", "FileChangedShellPost" },
    {
        group = group,
        callback = refresh,
    }
)
api.nvim_create_autocmd("OptionSet", { group = group, callback = refresh, pattern = "colorcolumn" })
api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_hl })

pcall(_refresh)
