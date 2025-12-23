# just.nvim
[Just](https://github.com/casey/just) task runner for neovim

## TOC
- [Configuration](#configuration)
- [API](#api)
- [Commands](#commands)
- [Old features notice](#old-features-notice)
    - [Telescope](#telescope)
    - [Completion Jingle](#completion-jingle)
- [Screenshots](#screenshots)
- [Misc](#misc)

## Installation
Using [lazy](https://github.com/folke/lazy.nvim) (as example)
```lua
{
    "al1-ce/just.nvim",
    dependencies = {
        'nvim-lua/plenary.nvim', -- async jobs
        'j-hui/fidget.nvim', -- task progress (optional)
    },
    config = true
}
```

## Configuration
Default config is
```lua
require("just").setup({
    fidget_message_limit = 32, -- limit for length of fidget progress message
    open_qf_on_error = true,   -- opens quickfix when task fails
    open_qf_on_run = true,     -- opens quickfix when running `run` task (`:JustRun`)
    open_qf_on_any = false;    -- opens quickfix when running any task (overrides other open_qf options)
    autoscroll_qf = true,      -- automatically scroll quickfix window on output
    register_commands = true,  -- if set to true then commands (:Just*) will be registered
    notify = vim.notify,       -- what to use to show messages/errors
})
```

## API
```lua
local just = require("just")

--- Runs vim.ui.select on list of tasks defined in justfile
just.run_task_select()

--- Runs specified task in defined
--- @param task_name string
just.run_task_name(task_name)

--- Force stops currently running task
just.stop_current_task()

--- Creates minimal justfile that contains shebang,
--- a link to just's reference manual and a default task
just.add_task_template()

--- Adds callback that will be called on
--- successful (return code is 0) completion of task
--- @param callback function
just.add_callback_on_done(callback)

--- Adds callback that will be called on
--- task failure (return code is not 0)
--- @param callback function
just.add_callback_on_fail(callback)

--- Applies user config and optionally (by default) creates user commands
--- @param opts table
just.setup(options)
```

## Commands:
- `Just` - If 0 args supplied runs `default` task, if 1 arg supplied runs task passes as that arg. If ran with bang (`!`) then stops currently running task before executing new one.
- `JustSelect` - Gives you selection of all tasks in `justfile` (optionally see [picker support](#Telescope)).
- `JustStop` - Stops currently running task.
- `JustCreateTemplate` - Creates template `justfile`.

> **IMPORTANT** - only one task can be executed at same time.

## Old features notice

### Telescope
Previously just.nvim was dependant on Telescope, it's not the case anymore. Now to use specific picker you need look up how to register it as `vim.ui.select` (with three most common ones listed here).

- Fzf-Lua setup:
```lua
local fzf = require("fzf-lua")
fzf.setup({ --[[ your setup ]] })
fzf.register_ui_select()
```
- Telescope requires to use [telescope-ui-select.nvim](https://github.com/nvim-telescope/telescope-ui-select.nvim) instead.
- Mini.Pick automatically registers itself as your ui select method after setup.
- For everything else see [how to register my plugin as ui select](https://www.google.com/search?q=nvim+register+PLUGIN+as+vim.ui.select&udm=14).

### Completion Jingle
I've removed option to play sound in favor of using your own callbacks and doing whatever you would want with them, including playing sounds on completion or failure of the task.

```lua
-- Example of replicating old behavior
-- async:new creates non-blocking system process
local just = require("just")
local async = require("plenary.job")
just.add_callback_on_fail(function()
    async:new({
        command = "aplay",
        args = {"/home/user/music/fail_sound.wav", "-q"}
    }):start()
end)
just.add_callback_on_done(function()
    async:new({
        command = "aplay",
        args = {"/home/user/music/done_sound.wav", "-q"}
    }):start()
end)
```

## Screenshots
- Example just file (*old* default JustCreateTemplate with added build task)

<img src="readme/just-file.png" width=50%>

- Fidget hint

<img src="readme/just-fidget.png" width=50%>

- Output of `:Just build` in quickfix

<img src="readme/just-qf.png" width=50%>

- `:JustSelect` using telescope

<img src="readme/just-select.png" width=50%>

## Misc

A quick primer on [just.nvim flavor](https://github.com/nxuv/just.nvim/blob/master/primer.md) of just (most important part is argument keywords).

