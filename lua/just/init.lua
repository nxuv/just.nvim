---@diagnostic disable: undefined-global, undefined-doc-param
local _M = {}

local function split_string(s, delimiter)
    local res = {}
    for part in string.gmatch(s, "([^"..delimiter.."]+)") do
        table.insert(res, part)
    end
    return res
end

local function find_justfile()
    for name, type in vim.fs.dir(".") do
        if type == "file" and string.match(name, "^%.?[Jj][Uu][Ss][Tt][Ff][Ii][Ll][Ee]$") then
            local justfile = string.format("%s/%s", vim.fn.getcwd(), name)
            if vim.fn.filereadable(justfile) == 1 then
                return justfile
            end
        end
    end
end

local config = {
    message_limit = 32,
    copen_on_error = true,
    copen_on_run = true,
    copen_on_any = false,
    autoscroll_qf = true,
    register_commands = true,
    notify = vim.notify,
    on_done_callbacks = {},
    on_fail_callbacks = {},
}

local function can_load(module) local ok, _ = pcall(require, module); return ok end

local async = require("plenary.job")

local progress = nil
if can_load("fidget") then progress = require("fidget.progress") end

local async_worker = nil

local function popup(message, errlvl, title)
    if errlvl == nil then errlvl = "info" end
    if title == nil then title = "Info" end
    config.notify(message, errlvl, {title = title})
end

local function info(message) popup(message, "info", "Just") end
local function error(message) popup(message, "error", "Just") end
local function warning(message) popup(message, "warning", "Just") end
-- local function inspect(val) print(vim.inspect(val)) end

-- returns `string[] names`
local function get_task_names(lang)
    if lang == nil then lang = "" end

    local arr = {}
    local justfile = find_justfile()

    if justfile ~= nil then
        local taskList = vim.fn.system(string.format("just -f %s --list", justfile))
        local taskArray = split_string(taskList, "\n")

        if vim.startswith(taskArray[1], "error") then
            error(taskList)
            return {}
        end

        table.remove(taskArray, 1)
        arr = taskArray
    else
        error("Justfile not found in project directory")
        return {}
    end

    local tbl = {}
    local i = 0
    while i < #arr do
        local options = split_string(split_string(arr[i + 1], "#")[1], " ")
        options = vim.tbl_filter(function(a) return a ~= "" end, options)
        if #options == 0 then goto continue end
        table.insert(tbl, options[1])
        ::continue::
        i = i + 1
    end
    return tbl
end

local function check_keyword_arg(arg)
    if arg == "FILEPATH"  then return vim.fn.expand("%:p") end
    if arg == "FILENAME"  then return vim.fn.expand("%:t") end
    if arg == "FILEDIR"   then return vim.fn.expand("%:p:h") end
    if arg == "FILEEXT"   then return vim.fn.expand("%:e") end
    if arg == "FILENOEXT" then return vim.fn.expand("%:t:r") end
    if arg == "CWD"       then return vim.fn.getcwd() end
    if arg == "RELPATH"   then return vim.fn.expand("%") end
    if arg == "RELDIR"    then return vim.fn.expand("%:h") end
    if arg == "TIME"      then return os.date("%H:%M:%S") end
    if arg == "DATE"      then return os.date("%d/%m/%Y") end
    if arg == "USDATE"    then return os.date("%m/%d/%Y") end
    if arg == "USERNAME"  then return os.getenv("USER") end
    if arg == "PCNAME"    then return split_string(vim.fn.system("uname -a"), " ")[2] end
    if arg == "OS"        then return split_string(vim.fn.system("uname"), "\n")[1] end
    return " "
end

-- returns {args = string[], all = bool, fail = bool}
local function get_task_args(task_name)
    local justfile = find_justfile()

    if justfile == nil then
        error("Justfile not found in project directory")
    end

    local task_info = vim.fn.system(string.format("just -f %s -s %s", justfile, task_name))

    if vim.startswith(task_info, "alias") then
        task_info = task_info:sub(task_info:find("\n") + 1)
    end

    if vim.startswith(task_info, "#") then
        task_info = task_info:sub(task_info:find("\n") + 1)
    end

    local task_signature = split_string(task_info, ":")[1]
    local task_args = split_string(task_signature, " ")

    table.remove(task_args, 1)

    if #task_args == 0 then return {args = {}, all = true, fail = false} end

    local out_args = {}
    local i = 0
    while i < #task_args do
        local arg = task_args[i + 1]
        local keyword = check_keyword_arg(arg)

        if keyword == " " then
            local ask = ""
            if arg:find("=") ~= nil then
                local arg_comp = split_string(arg, "=")
                ask = vim.fn.input(string.format("%s: ", arg_comp[1]), arg_comp[2])
            else
                ask = vim.fn.input(string.format("%s: ", arg), "")
            end

            if string.format("%s", ask) == "" then
                error("Must provide a valid argument")
                return {args = {}, all = false, fail = true}
            end

            table.insert(out_args, string.format("%s", ask))
        else
            if keyword == "" then keyword = " " end
            table.insert(out_args, string.format("%s", keyword))
        end
        i = i + 1
    end

    return {args = out_args, all = #out_args == #task_args, fail = false}
end

local function task_runner(task_name)
    if async_worker ~= nil then error("Task is already running"); return end
    if task_name == nil then return end

    local arg_obj = get_task_args(task_name)

    if arg_obj.all ~= true or arg_obj.fail then
        error("Failed to get all arguments or not enough arguments supplied")
        return
    end

    local args = arg_obj.args

    local justfile = find_justfile()

    if justfile == nil then
        error("Justfile not found in project directory")
        return
    end

    local handle = nil
    if progress ~= nil then
        handle = progress.handle.create({
            title = "",
            message = string.format("Starting task \"%s\"", task_name),
            lsp_client = {name = "Just"},
            percentage = 0
        })
    end

    local command = string.format("just -f %s -d . %s %s", justfile, task_name, table.concat(args, " "))

    local should_open_qf = (config.copen_on_run and task_name == "run") or config.copen_on_any
    if should_open_qf then vim.cmd("copen") end

    vim.fn.setqflist({{text = string.format("Starting task: %s", command)}, {text = ""}}, "r")

    if should_open_qf then vim.cmd("wincmd p") end

    local qfid  = vim.fn.getqflist({winid=0}).winid
    local qfbuf = vim.api.nvim_win_get_buf(qfid)

    local start_time = os.clock()

    local append_qf_data = function(data)
        if async_worker == nil then return end
        if data == nil then data = "" end
        if data == "" then data = " " end

        data = data:gsub("warning", "Warning", 1)
        data = data:gsub("info", "Info", 1)
        data = data:gsub("error", "Error", 1)
        data = data:gsub("note", "Note", 1)
        data = data:gsub("'", "''")
        data = data:gsub("%z", "")

        vim.cmd(string.format("caddexpr '%s'", data))

        if #data > config.message_limit then
            data = string.format("%s...", data:sub(1, config.message_limit))
        end

        if handle ~= nil then handle.message = data end

        if config.autoscroll_qf then
            local is_valid_qf = vim.api.nvim_win_is_valid(qfid) and vim.api.nvim_buf_is_valid(qfbuf)
            if qfid ~= 0 and is_valid_qf then
                local qflen = vim.api.nvim_buf_line_count(qfbuf)
                vim.api.nvim_win_set_cursor(qfid, {qflen, 0})
            else
                qfid  = vim.fn.getqflist({winid=0}).winid
                qfbuf = vim.api.nvim_win_get_buf(qfid)
            end
        end
    end

    local on_stdout_func = function(_, data)
        vim.schedule( function() return append_qf_data(data) end )
    end

    local on_stderr_func = function(_, data)
        vim.schedule( function() return append_qf_data(data) end )
    end

    local just_args = {"-f", justfile, "-d", ".", task_name}
    for _, arg in ipairs(args) do
        table.insert(just_args, arg)
    end

    async_worker = async:new({
        command = "just",
        args = just_args,
        env = vim.fn.environ(),
        cwd = vim.fn.getcwd(),

        on_exit = function(_, ret)
            local end_time = os.clock() - start_time
            vim.defer_fn( function()
                local status = ""
                if async_worker == nil then
                    if handle ~= nil then handle.message = "Cancelled"; handle:cancel() end
                    status = "Cancelled"
                else
                    if ret == 0 then
                        if handle ~= nil then handle.message = "Finished"; handle:finish() end
                        status = "Finished"
                        for _, func in pairs(config.on_done_callbacks) do
                            if func ~= nil and type(func) == "function" then
                                func()
                            end
                        end
                    else
                        if handle ~= nil then handle.message = "Failed"; handle:finish() end
                        if config.copen_on_error then vim.cmd("copen"); vim.cmd("wincmd p") end
                        status = "Failed"
                        for _, func in pairs(config.on_fail_callbacks) do
                            if func ~= nil and type(func) == "function" then
                                func()
                            end
                        end
                    end
                end

                vim.fn.setqflist( { {text = ""}, {text = string.format("%s in %s seconds", status, string.format("%.2f", end_time))} }, "a")
                vim.cmd("cbottom")

                async_worker = nil
            end, 50)
        end,
        on_stdout = on_stdout_func,
        on_stderr = on_stderr_func,
        on_start = function() if handle ~= nil then handle.message = string.format("Executing task %s", task_name) end end
    })

    if async_worker ~= nil then async_worker:start() end
end

local function task_select()
    local tasks = get_task_names()
    if #tasks == 0 then return end
    vim.ui.select(tasks, {prompt = "Select task: "}, function(choice) task_runner(choice) end)
end

local function run_task_select()
    local tasks = get_task_names()
    if #tasks == 0 then warning("There are no tasks defined in justfile"); return end
    task_select()
end

local function run_task_name(task_name)
    local tasks = get_task_names()
    if #tasks == 0 then warning("There are no tasks defined in justfile"); return end
    local i = 0
    while i < #tasks do
        local opts = split_string(tasks[i + 1], "_")
        -- info(vim.inspect(opts))
        if #opts == 1 then
            if opts[1]:lower() == task_name then
                task_runner(tasks[i + 1])
                return
            end
        end
        i = i + 1
    end
    warning("Could not find just task named '" .. task_name .. "'.")
    -- run_task_select()
end

local function stop_current_task()
    if async_worker ~= nil then async_worker:shutdown() end
    async_worker = nil
end

local function run_task_cmd(args)
    if args.bang then stop_current_task() end
    if #args.fargs == 0 then
        run_task_name("default")
    else
        run_task_name(args.fargs[1])
    end
end

local function add_task_template()
    local justfile = find_justfile()
    if justfile == nil then
				justfile = string.format("%s/%s", vim.fn.getcwd(), "justfile")
		else
        local opt = vim.fn.confirm("Justfile already exists in this project, create anyway?", "&Yes\n&No", 2)
        if opt ~= 1 then return end
		end

    local f = io.open(justfile, "w")
    if f == nil then error("Unable to write '" .. justfile .. "'"); return end
    f:write([=[#!/usr/bin/env -S just --justfile
# just reference  : https://just.systems/man/en/

@default:
    just --list
]=])
    f:close()
    info("Template justfile created")
end

local function add_callback_on_done(callback)
    table.insert(config.on_done_callbacks, callback)
end

local function add_callback_on_fail(callback)
    table.insert(config.on_fail_callbacks, callback)
end

local function table_to_dict(tbl)
    local out = {}
    for key, value, _ in pairs(tbl) do out[key] = value end
    return out
end

local function get_bool_option(opts, key, p_default)
    if opts[key] ~= nil then
        if opts[key] == true then return true end
        if opts[key] == false then return false end
    end
    return p_default
end

local function get_any_option(opts, key, p_default)
    if opts[key] ~= nil then return opts[key] end
    return p_default
end

-- local function get_subtable_option(opts, key, sub_key, p_default)
--     if opts[key] ~= nil then
--         local o = opts[key]
--         if o[sub_key] ~= nil then
--             return o[sub_key]
--         end
--     end
--     return p_default
-- end

local function setup(opts)
    opts = table_to_dict(opts)
    config.message_limit  = get_any_option(opts, "fidget_message_limit", config.message_limit)
    config.copen_on_error = get_bool_option(opts, "open_qf_on_error", config.copen_on_error)
    config.copen_on_run   = get_bool_option(opts, "open_qf_on_run", config.copen_on_run)
    config.copen_on_any   = get_bool_option(opts, "open_qf_on_any", config.copen_on_any)
    config.autoscroll_qf  = get_bool_option(opts, "autoscroll_qf", config.autoscroll_qf)
    config.register_commands = get_bool_option(opts, "register_commands", config.register_commands)
    config.notify = get_any_option(opts, "notify", config.notify)
    if config.register_commands then
        vim.api.nvim_create_user_command("Just", run_task_cmd, {nargs = "?", bang = true, desc = "Run task"})
        vim.api.nvim_create_user_command("JustSelect", run_task_select, {nargs = 0, desc = "Open task picker"})
        vim.api.nvim_create_user_command("JustStop", stop_current_task, {nargs = 0, desc = "Stops current task"})
        vim.api.nvim_create_user_command("JustCreateTemplate", add_task_template, {nargs = 0, desc = "Creates template for just"})
    end
end

-- print(vim.inspect(vim.api.nvim_buf_line_count(0)))
-- print(vim.fn.bufnr("%"))
-- print(vim.fn.winnr())
-- print(vim.fn.win_getid())
-- 1000
-- 0
-- 1
-- 444
-- 2

--- Runs vim.ui.select on list of tasks defined in justfile
_M.run_task_select = run_task_select
--- Runs specified task in defined
--- @param task_name string
_M.run_task_name = run_task_name
--- Force stops currently running task
_M.stop_current_task = stop_current_task
--- Creates minimal justfile containing shebang,
--- link to just's reference manual and default task
_M.add_task_template = add_task_template
--- Adds callback that will be called on
--- successful (return code is 0) completion of task
--- @param callback function
_M.add_callback_on_done = add_callback_on_done
--- Adds callback that will be called on
--- task failure (return code is not 0)
--- @param callback function
_M.add_callback_on_fail = add_callback_on_fail
--- Applies user config and optionally (by default) creates user commands
--- @param opts table
_M.setup = setup

return _M
