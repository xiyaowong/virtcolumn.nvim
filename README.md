# virtcolumn.nvim

**Display a character as the colorcolumn.**

![image](https://user-images.githubusercontent.com/47070852/163523348-ad949d3f-4fc4-461f-98ee-0291af613396.png)

This plugin is based on [lukas-reineke/virt-column.nvim](https://github.com/lukas-reineke/virt-column.nvim),
then why not submit pr, but a new repository, because the content of the modification of this plugin
and the original use of the way completely incompatible, and can even be considered two completely different plugins

## Install

requires nvim0.7+nightly which has `nvim_create_autocmd`

Same as other normal plugins, use your favourite plugin manager to install.

## Configuration

This plugin is aiming for zero configuration, you just need to install and make
sure this plugin loaded and it will automatically handle `colorcolumn`
e.g. `set cc=80` `au FileType gitcommit setl cc=50,72`

by default

```lua
vim.g.virtcolumn_char = '▕' -- char to display the line
vim.g.virtcolumn_priority = 10 -- priority of extmark
```

### highlight

**`VirtColumn`**

Highlight of virtual column character.

Use `ColorColumn`s background color by default, otherwise link to `NonText`
