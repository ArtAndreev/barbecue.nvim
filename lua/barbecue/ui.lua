local navic = require("nvim-navic")
local devicons_ok, devicons = pcall(require, "nvim-web-devicons")
local config = require("barbecue.config")
local utils = require("barbecue.utils")
local Entry = require("barbecue.ui.entry")

local M = {}

---whether winbar is visible
---@type boolean
local visible = true

---mapping of `winnr` to its `winbar` state before being set
---@type table<number, string>
local affected_wins = {}

---returns dirname of `bufnr`
---@param bufnr number
---@return barbecue.Entry[]|nil
local function get_dirname(bufnr)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local dirname = vim.fn.fnamemodify(filename, config.user.modifiers.dirname .. ":h")

  ---@type barbecue.Entry[]
  local entries = {}

  if dirname == "." then return nil end
  if dirname ~= "/" and dirname:sub(1, 1) == "/" then
    dirname:sub(2)
    table.insert(
      entries,
      Entry.new({
        "/",
        highlight = "NavicText",
      })
    )
  end

  for _, dir in ipairs(vim.split(dirname, "/")) do
    table.insert(
      entries,
      Entry.new({
        dir,
        highlight = "NavicText",
      })
    )
  end

  return entries
end

---returns basename of `bufnr`
---@param winnr number
---@param bufnr number
---@return barbecue.Entry|nil
local function get_basename(winnr, bufnr)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local basename = vim.fn.fnamemodify(filename, config.user.modifiers.basename .. ":t")
  if basename == "" then return nil end

  local icon, icon_highlight
  if devicons_ok then
    icon, icon_highlight = devicons.get_icon_by_filetype(vim.bo[bufnr].filetype)
  end

  return Entry.new({
    basename,
    highlight = "NavicText",
  }, {
    icon,
    highlight = icon_highlight,
  }, function()
    vim.api.nvim_set_current_win(winnr)
    vim.api.nvim_win_set_cursor(winnr, { 1, 0 })
  end)
end

---returns context of `bufnr`
---@param winnr number
---@param bufnr number
---@return barbecue.Entry[]|nil
local function get_context(winnr, bufnr)
  if not navic.is_available() then return nil end

  local nestings = navic.get_data(bufnr)
  if nestings == nil then return nil end

  return vim.tbl_map(function(nesting)
    return Entry.new({
      nesting.name,
      highlight = "NavicText",
    }, {
      config.user.kinds[nesting.type],
      highlight = "NavicIcons" .. nesting.type,
    }, function()
      vim.api.nvim_set_current_win(winnr)
      vim.api.nvim_win_set_cursor(winnr, { nesting.scope.start.line, nesting.scope.start.character })
    end)
  end, nestings)
end

---computes length of visible characters of `entries`
---@param entries barbecue.Entry[]
---@return number
local function entries_length(entries)
  local length = 0

  for i, entry in ipairs(entries) do
    length = length + entry:len()
    if i < #entries then length = length + utils.str_len(config.user.symbols.separator) + 2 end
  end

  return length
end

---truncates `entries` based on `max_length`
---@param entries barbecue.Entry[]
---@param length number
---@param max_length number
local function truncate_entries(entries, length, max_length)
  local has_ellipsis, i = false, 1
  while i <= #entries do
    if length <= max_length then break end

    length = length - entries[i]:len()
    if has_ellipsis then
      if i < #entries then length = length - (utils.str_len(config.user.symbols.separator) + 2) end
      table.remove(entries, i)
    else
      length = length + utils.str_len(config.user.symbols.ellipsis)
      entries[i] = Entry.new({
        config.user.symbols.ellipsis,
        highlight = "BarbecueEllipsis",
      })

      has_ellipsis = true
      i = i + 1 -- manually increment i when not removing anything from entries
    end
  end
end

---toggles visibility
---@param shown boolean?
function M.toggle(shown)
  if shown == nil then shown = not visible end

  visible = shown
  for _, winnr in ipairs(vim.api.nvim_list_wins()) do
    M.update(winnr)
  end
end

---@async
---updates winbar on `winnr`
---@param winnr number?
function M.update(winnr)
  winnr = winnr or vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(winnr)

  if
    not vim.tbl_contains(config.user.include_buftypes, vim.bo[bufnr].buftype)
    or vim.tbl_contains(config.user.exclude_filetypes, vim.bo[bufnr].filetype)
    or vim.api.nvim_win_get_config(winnr).relative ~= ""
  then
    if affected_wins[winnr] ~= nil then
      vim.wo[winnr].winbar = affected_wins[winnr]
      affected_wins[winnr] = nil
    end

    return
  end

  if not visible then
    vim.wo[winnr].winbar = nil
    return
  end

  vim.schedule(function()
    if
      not vim.api.nvim_buf_is_valid(bufnr)
      or not vim.api.nvim_win_is_valid(winnr)
      or bufnr ~= vim.api.nvim_win_get_buf(winnr)
    then
      return
    end

    local dirname = get_dirname(bufnr)
    local basename = get_basename(winnr, bufnr)
    local context = get_context(winnr, bufnr)
    if basename == nil then return end

    ---@type barbecue.Entry[]
    local entries = {}
    utils.tbl_merge(entries, dirname or {}, { basename }, context or {})
    local custom_section = config.user.custom_section(bufnr)

    if config.user.truncation.enabled then
      local length = entries_length(entries)
        + utils.str_len(custom_section)
        + ((vim.bo[bufnr].modified and config.user.symbols.modified ~= false) and utils.str_len(
          config.user.symbols.modified
        ) + 1 or 0)
        + 2 -- heading and trailing whitespaces

      truncate_entries(entries, length, vim.api.nvim_win_get_width(winnr))
    end

    local winbar = " "
      .. (
        (vim.bo[bufnr].modified and config.user.symbols.modified ~= false)
          and "%#BarbecueMod#" .. config.user.symbols.modified .. " "
        or ""
      )
    for i, entry in ipairs(entries) do
      winbar = winbar .. entry:to_string()
      if i < #entries then winbar = winbar .. " %#NavicSeparator#" .. config.user.symbols.separator .. " " end
    end
    winbar = winbar .. "%=" .. custom_section .. " "

    affected_wins[winnr] = vim.wo[winnr].winbar
    vim.wo[winnr].winbar = winbar
  end)
end

return M
