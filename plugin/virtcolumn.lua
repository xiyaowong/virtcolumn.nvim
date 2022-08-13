--- Options:
--- vim.g.virtcolumn_char = "▕"
--- vim.g.virtcolumn_priority = 10

local api, fn = vim.api, vim.fn
local ffi = require('ffi')

ffi.cdef('int curwin_col_off(void);')
local function curwin_col_off()
  return ffi.C.curwin_col_off()
end

local NS = api.nvim_create_namespace('virtcolumn')

---@param cc string
---@return number[]
local function parse_items(cc)
  local textwidth = vim.o.textwidth
  ---@type number[]
  local items = {}
  for _, c in ipairs(vim.split(cc, ',')) do
    local item
    if c and c ~= '' then
      if vim.startswith(c, '+') then
        if textwidth ~= 0 then item = textwidth + tonumber(c:sub(2)) end
      elseif vim.startswith(cc, '-') then
        if textwidth ~= 0 then item = textwidth - tonumber(c:sub(2)) end
      else
        item = tonumber(c)
      end
    end
    if item and item > 0 then table.insert(items, item) end
  end
  table.sort(items, function(a, b)
    return a > b
  end)
  return items
end

local function _refresh()
  local curbuf = api.nvim_get_current_buf()
  if not api.nvim_buf_is_loaded(curbuf) then return end

  local items = vim.b.virtcolumn_items or vim.w.virtcolumn_items
  local local_cc = api.nvim_get_option_value('cc', { scope = 'local' })
  if not items or local_cc ~= '' then
    items = parse_items(local_cc)
    api.nvim_set_option_value('cc', '', { scope = 'local' })
  end
  vim.b.virtcolumn_items = items
  vim.w.virtcolumn_items = items

  local win_width = api.nvim_win_get_width(0) - curwin_col_off()
  items = vim.tbl_filter(function(item)
    return win_width > item
  end, items)

  if #items == 0 then
    api.nvim_buf_clear_namespace(curbuf, NS, 0, -1)
    return
  end

  local debounce = math.floor(api.nvim_win_get_height(0) * 0.6)
  local visible_first, visible_last = fn.line('w0'), fn.line('w$')
  -- Avoid flickering caused by winscrolled_timer
  local offset = (visible_first <= debounce and 1 or visible_first - debounce) - 1 -- convert to 0-based

  --                                                Avoid flickering caused by timer
  --                                                                ↓↓↓↓↓↓↓↓↓↓↓
  local lines = api.nvim_buf_get_lines(curbuf, offset, visible_last + debounce, false)
  local rep = string.rep(' ', vim.opt.tabstop:get())
  local char = vim.g.virtcolumn_char or '▕'
  local priority = vim.g.virtcolumn_priority or 10

  local line, lnum, strwidth
  for idx = 1, #lines do
    line = lines[idx]:gsub('\t', rep)
    lnum = idx - 1 + offset
    strwidth = api.nvim_strwidth(line)
    api.nvim_buf_clear_namespace(curbuf, NS, lnum, lnum + 1)
    for _, item in ipairs(items) do
      if strwidth < item or fn.strpart(line, item - 1, 1) == ' ' then
        api.nvim_buf_set_extmark(curbuf, NS, lnum, 0, {
          virt_text = { { char, 'VirtColumn' } },
          hl_mode = 'combine',
          virt_text_win_col = item - 1,
          priority = priority,
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
  local event = args.event or ''
  if event == 'WinScrolled' then
    if winscrolled_timer and winscrolled_timer:is_active() then
      winscrolled_timer:stop()
      winscrolled_timer:close()
    end
    winscrolled_timer = vim.defer_fn(_refresh, 100)
  elseif event:match('TextChanged') then
    if textchanged_timer and textchanged_timer:is_active() then
      textchanged_timer:stop()
      textchanged_timer:close()
    end
    local lines_count = vim.fn.line('$')
    local delay
    if lines_count ~= vim.b.virtcolumn_lines_count then
      vim.b.virtcolumn_lines_count = lines_count
      delay = 15
    else
      delay = 150
    end
    textchanged_timer = vim.defer_fn(_refresh, delay)
  else
    _refresh()
  end
end

local function set_hl()
  local cc_bg = api.nvim_get_hl_by_name('ColorColumn', true).background
  if cc_bg then
    api.nvim_set_hl(0, 'VirtColumn', { fg = cc_bg, default = true })
  else
    vim.cmd([[hi default link VirtColumn NonText]])
  end
end

local group = api.nvim_create_augroup('virtcolumn', {})
api.nvim_create_autocmd({
  'WinScrolled',
  'TextChanged',
  'TextChangedI',
  'BufWinEnter',
  'InsertLeave',
  'InsertEnter',
  'FileChangedShellPost',
}, { group = group, callback = refresh })
api.nvim_create_autocmd('OptionSet', {
  group = group,
  callback = function()
    vim.b.virtcolumn_items = nil
    vim.w.virtcolumn_items = nil
    _refresh()
  end,
  pattern = 'colorcolumn',
})
api.nvim_create_autocmd('ColorScheme', { group = group, callback = set_hl })

pcall(set_hl)
pcall(_refresh)
