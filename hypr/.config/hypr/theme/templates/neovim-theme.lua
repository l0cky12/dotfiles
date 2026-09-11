-- {{ theme_name }} -- generated Neovim colorscheme. Do not edit.
vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
  vim.cmd("syntax reset")
end

vim.g.colors_name = nil
vim.o.background = "{{ theme_mode }}"
vim.g.colors_name = "{{ theme_slug }}"

vim.g.terminal_color_0 = "{{ ansi.black }}"
vim.g.terminal_color_1 = "{{ ansi.red }}"
vim.g.terminal_color_2 = "{{ ansi.green }}"
vim.g.terminal_color_3 = "{{ ansi.yellow }}"
vim.g.terminal_color_4 = "{{ ansi.blue }}"
vim.g.terminal_color_5 = "{{ ansi.magenta }}"
vim.g.terminal_color_6 = "{{ ansi.cyan }}"
vim.g.terminal_color_7 = "{{ ansi.white }}"
vim.g.terminal_color_8 = "{{ ansi.bright_black }}"
vim.g.terminal_color_9 = "{{ ansi.bright_red }}"
vim.g.terminal_color_10 = "{{ ansi.bright_green }}"
vim.g.terminal_color_11 = "{{ ansi.bright_yellow }}"
vim.g.terminal_color_12 = "{{ ansi.bright_blue }}"
vim.g.terminal_color_13 = "{{ ansi.bright_magenta }}"
vim.g.terminal_color_14 = "{{ ansi.bright_cyan }}"
vim.g.terminal_color_15 = "{{ ansi.bright_white }}"

local highlights = {
  Normal = { fg = "{{ foreground }}", bg = "{{ background }}" },
  Visual = { fg = "{{ fg_on(selection) }}", bg = "{{ selection }}" },
  StatusLine = { fg = "{{ fg_on(accent) }}", bg = "{{ accent }}", bold = true },
  StatusLineNC = { fg = "{{ muted }}", bg = "{{ surface }}" },
  Comment = { fg = "{{ muted }}", italic = true },
}

for group, opts in pairs(highlights) do
  vim.api.nvim_set_hl(0, group, opts)
end
