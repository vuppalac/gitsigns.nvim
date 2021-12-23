local a = require('plenary.async.async')
local wrap = a.wrap
local void = a.void
local scheduler = require('plenary.async.util').scheduler

local cache = require('gitsigns.cache').cache
local config = require('gitsigns.config').config
local BlameInfo = require('gitsigns.git').BlameInfo
local util = require('gitsigns.util')

local api = vim.api

local current_buf = api.nvim_get_current_buf

local namespace = api.nvim_create_namespace('gitsigns_blame')

local timer = vim.loop.new_timer()

local M = {}





local wait_timer = wrap(vim.loop.timer_start, 4)

M.reset = function(bufnr)
   bufnr = bufnr or current_buf()
   api.nvim_buf_del_extmark(bufnr, namespace, 1)
   pcall(api.nvim_buf_del_var, bufnr, 'gitsigns_blame_line_dict')
end


local max_cache_size = 1000

local BlameCache = {Elem = {}, }








BlameCache.contents = {}

function BlameCache:init_or_invalidate(bufnr)
   if not config._blame_cache then return end
   local tick = api.nvim_buf_get_var(bufnr, 'changedtick')
   if not self.contents[bufnr] or self.contents[bufnr].tick ~= tick then
      self.contents[bufnr] = { tick = tick, cache = {}, size = 0 }
   end
end

function BlameCache:add(bufnr, lnum, x)
   if not config._blame_cache then return end
   local scache = self.contents[bufnr]
   if scache.size <= max_cache_size then
      scache.cache[lnum] = x
      scache.size = scache.size + 1
   end
end

function BlameCache:get(bufnr, lnum)
   if not config._blame_cache then return end
   return self.contents[bufnr].cache[lnum]
end


M.update = void(function()
   M.reset()
   local opts = config.current_line_blame_opts


   wait_timer(timer, opts.delay, 0)
   scheduler()

   local bufnr = current_buf()
   local bcache = cache[bufnr]
   if not bcache or not bcache.git_obj.object_name then
      return
   end

   local lnum = api.nvim_win_get_cursor(0)[1]

   BlameCache:init_or_invalidate(bufnr)
   local result = BlameCache:get(bufnr, lnum)
   if not result then
      local buftext = util.buf_lines(bufnr)
      result = bcache.git_obj:run_blame(buftext, lnum, opts.ignore_whitespace)
      BlameCache:add(bufnr, lnum, result)
   end

   scheduler()

   M.reset(bufnr)

   local lnum1 = api.nvim_win_get_cursor(0)[1]
   if bufnr == current_buf() and lnum ~= lnum1 then

      return
   end

   if not api.nvim_buf_is_loaded(bufnr) then

      return
   end

   api.nvim_buf_set_var(bufnr, 'gitsigns_blame_line_dict', result)
   if opts.virt_text then
      api.nvim_buf_set_extmark(bufnr, namespace, lnum - 1, 0, {
         id = 1,
         virt_text = config.current_line_blame_formatter(
         bcache.git_obj.repo.username,
         result,
         config.current_line_blame_formatter_opts),

         virt_text_pos = opts.virt_text_pos,
         hl_mode = 'combine',
      })
   end
end)

M.setup = function()
   vim.cmd([[
    augroup gitsigns_blame
      autocmd!
    augroup END
  ]])

   for k, _ in pairs(cache) do
      M.reset(k)
   end

   if config.current_line_blame then
      vim.cmd([[autocmd gitsigns_blame FocusGained,BufEnter,CursorMoved,CursorMovedI * lua require("gitsigns.current_line_blame").update()]])
      vim.cmd([[autocmd gitsigns_blame FocusLost,BufLeave                            * lua require("gitsigns.current_line_blame").reset()]])
      M.update()
   end
end

return M
