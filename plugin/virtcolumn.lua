--- Options:
--- vim.g.virtcolumn_char = "▕"
--- vim.g.virtcolumn_priority = 10

local api, fn = vim.api, vim.fn

local NS = api.nvim_create_namespace('virtcolumn')

---@class WinContext
---@field textoff integer
---@field topline integer
---@field botline integer
---@field width integer
---@field height integer
---@field leftcol integer
---@field winnr integer

---@return WinContext
local function get_win_context()
  local info = fn.getwininfo(api.nvim_get_current_win())[1]
  local view = fn.winsaveview()
  return vim.tbl_extend('force', info, view)
end

---@param cc string
---@return number[]
local function parse_items(cc)
  local textwidth = vim.bo.textwidth
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

---@param line string
---@param col integer byte 0-indexed
---@return boolean
local function is_empty_at_col(line, col)
  local ok, char = pcall(fn.strpart, line, col, 1)
  return ok and char == ' '
end

local function _refresh()
  local curbuf = api.nvim_get_current_buf()
  if not api.nvim_buf_is_loaded(curbuf) then return end

  local items = vim.b.virtcolumn_items or vim.w.virtcolumn_items
  local local_cc = api.nvim_get_option_value('cc', { scope = 'local' })
  if not items or local_cc ~= '' then
    items = parse_items(local_cc)
    vim.b.virtcolumn_last_cc = local_cc
    vim.w.virtcolumn_last_cc = local_cc
    api.nvim_set_option_value('cc', '', { scope = 'local' })
  end
  vim.b.virtcolumn_items = items
  vim.w.virtcolumn_items = items

  local ctx = get_win_context()

  -- TODO: Find time to fix the bug that clears the displayed content when opening the sidebar(window)
  -- local ll = ctx.leftcol
  -- local ul = ctx.width + ctx.leftcol - ctx.textoff
  -- items = vim.tbl_filter(function(item)
  --   return item > ll and item < ul
  -- end, items)

  if #items == 0 then
    api.nvim_buf_clear_namespace(curbuf, NS, 0, -1)
    return
  end

  local extend = math.floor(ctx.height * 0.4)
  local offset = math.max(0, ctx.topline - extend)
  local lines = api.nvim_buf_get_lines(curbuf, offset, ctx.botline + extend, false)
  local rep = string.rep(' ', vim.opt.tabstop:get())

  local virt_char = vim.g.virtcolumn_char or '▕'
  local virt_priority = vim.g.virtcolumn_priority or 10

  local leftcol = ctx.leftcol
  local line, lnum, strwidth
  for idx = 1, #lines do
    line = lines[idx]:gsub('\t', rep)
    lnum = idx - 1 + offset
    strwidth = api.nvim_strwidth(line)
    api.nvim_buf_clear_namespace(curbuf, NS, lnum, lnum + 1)
    for _, item in ipairs(items) do
      if strwidth < item or is_empty_at_col(line, item - 1) then
        api.nvim_buf_set_extmark(curbuf, NS, lnum, 0, {
          virt_text = { { virt_char, 'VirtColumn' } },
          hl_mode = 'combine',
          virt_text_win_col = item - 1 - leftcol,
          priority = virt_priority,
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
    winscrolled_timer = vim.defer_fn(_refresh, 20)
  elseif event:match('TextChanged') then
    if textchanged_timer and textchanged_timer:is_active() then
      textchanged_timer:stop()
      textchanged_timer:close()
    end
    local lines_count = api.nvim_buf_line_count(0)
    local delay
    if lines_count ~= vim.b.virtcolumn_lines_count then
      vim.b.virtcolumn_lines_count = lines_count
      delay = 10
    else
      delay = 20
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
  'FileType',
  'WinScrolled',
  'WinResized',
  'TextChanged',
  'TextChangedI',
  'WinEnter',
  'BufWinEnter',
  'BufRead',
  'InsertLeave',
  'InsertEnter',
  'FileChangedShellPost',
}, { group = group, callback = refresh })
api.nvim_create_autocmd('OptionSet', {
  group = group,
  callback = function(ev)
    if ev.match == 'textwidth' then
      local curr_cc = api.nvim_get_option_value('cc', { scope = 'local' })
      local last_cc = vim.b.virtcolumn_last_cc or vim.w.virtcolumn_last_cc
      local cc = curr_cc ~= '' and curr_cc or last_cc
      if cc then api.nvim_set_option_value('cc', cc, { scope = 'local' }) end
    end
    vim.b.virtcolumn_items = nil
    vim.w.virtcolumn_items = nil
    _refresh()
  end,
  pattern = 'colorcolumn,textwidth',
})
api.nvim_create_autocmd('ColorScheme', { group = group, callback = set_hl })

pcall(set_hl)
pcall(_refresh)
