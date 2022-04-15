--- vim.g.virtcolumn_char: ▕ by default

local api = vim.api
local ffi = require "ffi"

ffi.cdef "int curwin_col_off(void);"
---@diagnostic disable-next-line: undefined-field
local curwin_col_off = ffi.C.curwin_col_off

local NS = api.nvim_create_namespace "virt-column"

---@param cc string
---@return number[]
local function parse_items(cc)
    local textwidth = vim.o.textwidth
    ---@type number[]
    local items = {}
    for _, c in ipairs(vim.split(cc, ",")) do
        local item
        if c and c ~= "" then
            if vim.startswith(c, "+") then
                if textwidth ~= 0 then
                    item = textwidth + tonumber(c:sub(2))
                end
            elseif vim.startswith(cc, "-") then
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
    return items
end

local function _refresh()
    local curbuf = api.nvim_get_current_buf()
    if not api.nvim_buf_is_loaded(curbuf) then
        return
    end

    local items = vim.b.virtcolumn_items or vim.w.virtcolumn_items
    local local_cc = vim.wo.cc
    if not items or local_cc ~= "" then
        items = parse_items(local_cc)
        vim.wo.cc = ""
    end
    vim.b.virtcolumn_items = items
    vim.w.virtcolumn_items = items

    api.nvim_buf_clear_namespace(curbuf, NS, 0, -1)

    if #items == 0 then
        return
    end

    local debounce = math.floor(api.nvim_win_get_height(0) * 0.6)
    local offset = vim.fn.line "w0"
    -- Avoid flickering caused by winscrolled_timer
    offset = (offset <= debounce and 1 or offset - debounce) - 1 -- convert to 0-based

    --                                                Avoid flickering caused by winscrolled_timer
    --                                                                    ↓↓↓↓↓↓↓↓↓↓↓
    local lines = api.nvim_buf_get_lines(curbuf, offset, vim.fn.line "w$" + debounce, false)
    local width = api.nvim_win_get_width(0) - curwin_col_off()
    local tabstop = vim.opt.tabstop:get()
    local char = vim.g.virtcolumn_char or "▕"

    for i = 1, #lines do
        for _, item in ipairs(items) do
            local line = lines[i]:gsub("\t", string.rep(" ", tabstop))
            if width > item and api.nvim_strwidth(line) < item then
                api.nvim_buf_set_extmark(curbuf, NS, i + offset - 1, 0, {
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

-- Avoid unnecessary refreshing as much as possible lcoallfdafffadf
local winscrolled_timer
local textchanged_timer
local function refresh(args)
    ---@type string
    local event = args.event or ""
    if event == "WinScrolled" then
        if winscrolled_timer and winscrolled_timer:is_active() then
            winscrolled_timer:stop()
            winscrolled_timer:close()
        end
        winscrolled_timer = vim.defer_fn(_refresh, 150)
    elseif event:match "TextChanged" then
        if textchanged_timer and textchanged_timer:is_active() then
            textchanged_timer:stop()
            textchanged_timer:close()
        end
        textchanged_timer = vim.defer_fn(_refresh, 500)
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

local group = api.nvim_create_augroup("virtcolumn", {})
api.nvim_create_autocmd({
    "WinScrolled",
    "TextChanged",
    "TextChangedI",
    "BufWinEnter",
    "InsertLeave",
    "InsertEnter",
    "FileChangedShellPost",
}, { group = group, callback = refresh })
api.nvim_create_autocmd("OptionSet", {
    group = group,
    callback = function()
        vim.b.virtcolumn_items = nil
        vim.w.virtcolumn_items = nil
        _refresh()
    end,
    pattern = "colorcolumn",
})
api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_hl })

pcall(set_hl)
pcall(_refresh)
