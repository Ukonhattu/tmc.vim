"
" Author: Daniel Koch (github: Ukonhattu)
" License:GPL-3.0
"
"
" This file implements helper functions for the Vim‑TMC plugin.  The functions
" execute `tmc‑langs‑cli` via system() and parse its JSON output using
" json_decode().  Error handling is centralized in the s:echo_error helper.


" Scriptscope helep vars
let s:ui_callbacks = {}
let s:ui_cb_next_id = 1



function! tmc#ui_call_callback(id, value) abort
  if exists('s:ui_callbacks') && has_key(s:ui_callbacks, a:id)
    call call(s:ui_callbacks[a:id], [a:value])
    unlet s:ui_callbacks[a:id]
  endif
endfunction


" Determine the path to the CLI.  Users can override g:tmc_cli_path in their
" vimrc to point to a custom binary location.  If no path is provided, the
" plugin will attempt to download a suitable prebuilt binary into a cache
" directory.  See tmc#ensure_cli() and s:download_cli() below.
if exists('g:tmc_cli_path')
  let s:cli_path = g:tmc_cli_path
else
  " Default to empty; will be filled by tmc#ensure_cli() on first use
  let s:cli_path = ''
endif

" Define client name and version for identification when interacting with
" TMC‑Core.  These are sent with every command via --client-name and
" --client-version flags.  Users may override them with g:tmc_client_name
" and g:tmc_client_version in their vimrc.
if exists('g:tmc_client_name')
  let s:client_name = g:tmc_client_name
else
  " Default client name identifying this plugin when interacting with the CLI.
  " Use underscore rather than dash as requested.
  let s:client_name = 'tmc_vim'
endif
if exists('g:tmc_client_version')
  let s:client_version = g:tmc_client_version
else
  let s:client_version = '0.1.0'
endif

" Default organisation (slug) used when listing courses.  Users may override
" g:tmc_organization in their vimrc or via :TmcSetOrg.  The organisation
" corresponds to the slug accepted by the GetCourses command of the CLI
" (e.g. "mooc", "hy").
if !exists('g:tmc_organization')
  let g:tmc_organization = 'mooc'
endif

" Helper to display error messages consistently
function! s:echo_error(msg) abort
  echohl ErrorMsg
  echom a:msg
  echohl None
endfunction


" Async UI selector:
" Usage: call tmc#ui_select(items, prompt, {result -> echom result})

function! tmc#ui_select(items, prompt, cb) abort
  let l:list = copy(a:items)
  for i in range(len(l:list))
    let l:list[i] = string(l:list[i])
  endfor
  let l:prompt = a:prompt

  " Register callback
  let l:cb_id = s:ui_cb_next_id
  let s:ui_callbacks[l:cb_id] = a:cb
  let s:ui_cb_next_id += 1

  " Telescope (Neovim)
  if has('nvim') && exists(':Telescope')
    let g:TMC_UI_CB_ID = l:cb_id
    let g:tmc_ui_select_items = l:list
    let g:tmc_ui_select_prompt = l:prompt
    lua <<EOF
local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf    = require('telescope.config').values
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')

pickers.new({}, {
  prompt_title = vim.g.tmc_ui_select_prompt,
  finder = finders.new_table { results = vim.g.tmc_ui_select_items },
  sorter = conf.generic_sorter({}),
  attach_mappings = function(_, map)
    actions.select_default:replace(function(bufnr)
      local entry = action_state.get_selected_entry()
      vim.schedule(function()
        vim.fn['tmc#ui_call_callback'](vim.g.TMC_UI_CB_ID, entry and entry[1] or '')
      end)
      actions.close(bufnr)
    end)
    return true
  end,
}):find()
EOF
    unlet g:tmc_ui_select_items
    unlet g:tmc_ui_select_prompt
    return v:null

  " vim.ui.select (Neovim)
  elseif has('nvim')
    let g:TMC_UI_CB_ID = l:cb_id
    let g:tmc_ui_select_items = l:list
    let g:tmc_ui_select_prompt = l:prompt
    lua <<EOF
if vim.ui and type(vim.ui.select) == 'function' then
  vim.ui.select(vim.g.tmc_ui_select_items, { prompt = vim.g.tmc_ui_select_prompt }, function(choice)
    vim.schedule(function()
      vim.fn['tmc#ui_call_callback'](vim.g.TMC_UI_CB_ID, choice or '')
    end)
  end)
end
EOF
    unlet g:tmc_ui_select_items
    unlet g:tmc_ui_select_prompt
    return v:null

  " fzf.vim
  elseif exists('*fzf#run')
    call fzf#run({
          \ 'source': l:list,
          \ 'sink*': { lines -> call(tmc#ui_call_callback, [l:cb_id, get(lines, 0, '')]) },
          \ 'options': ['--prompt='.l:prompt.'> '],
          \ })
    return v:null

  " Vim popup_menu()/inputlist() fallback
  else
    let l:choice = ''
    if exists('*popup_menu')
      let l:idx = popup_menu(l:list, {'title': l:prompt})
      if l:idx >= 1 && l:idx <= len(l:list)
        let l:choice = l:list[l:idx - 1]
      endif
    else
      let l:choices = [l:prompt]
      for i in range(len(l:list))
        call add(l:choices, printf('%d. %s', i+1, l:list[i]))
      endfor
      let l:res = inputlist(l:choices)
      if l:res >= 1 && l:res <= len(l:list)
        let l:choice = l:list[l:res - 1]
      endif
    endif
    call tmc#ui_call_callback(l:cb_id, l:choice)
    return v:null
  endif
endfunction


" Determine a directory where the CLI binary will be stored.  When the
" stdpath() function is available (Vim 8.2+/Neovim), use the data
" directory; otherwise fall back to ~/.vim/tmc.  This directory will be
" created on demand by s:download_cli().
function! s:get_cli_storage_dir() abort
  if exists('*stdpath')
    return stdpath('data') . '/tmc'
  endif
  return expand('~/.vim/tmc')
endfunction

" Compute the path to the CLI binary within the storage directory.  On
" Windows the executable suffix .exe is appended.  The resulting path is
" returned as a string but not created.
function! s:get_cli_binary_path() abort
  let l:dir = s:get_cli_storage_dir()
  let l:exe = 'tmc-langs-cli'
  if has('win32') || has('win64')
    let l:exe .= '.exe'
  endif
  return l:dir . '/' . l:exe
endfunction

" Detect the Rust compilation target triple appropriate for the current
" platform.  This determines which prebuilt binary to download.  The
" detection is heuristic: on Windows return x86_64-pc-windows-msvc;
" on macOS detect Apple Silicon (aarch64) vs x86_64; otherwise on
" Linux return the architecture combined with unknown-linux-gnu.  If an
" unsupported architecture is encountered, fallback to x86_64-unknown-linux-gnu.
function! s:detect_target() abort
  let l:uname_s = substitute(system('uname -s'), '\n', '', 'g')
  let l:uname_m = substitute(system('uname -m'), '\n', '', 'g')

  " Windows
  if has('win32') || has('win64')
    if l:uname_m =~# '^i686'
      return 'i686-pc-windows-msvc'
    else
      return 'x86_64-pc-windows-msvc'
    endif

  " macOS
  elseif l:uname_s ==# 'Darwin'
    if l:uname_m ==# 'x86_64'
      return 'x86_64-apple-darwin'
    else
      return 'aarch64-apple-darwin'
    endif

  " Linux
  elseif l:uname_s ==# 'Linux'
    if l:uname_m =~# '^x86_64'
      let l:ldd = system('ldd --version 2>&1')
      if l:ldd =~? 'musl'
        return 'x86_64-unknown-linux-musl'
      else
        return 'x86_64-unknown-linux-gnu'
      endif
    elseif l:uname_m =~# '^\(i686\|i386\)$'
      return 'i686-unknown-linux-gnu'
    elseif l:uname_m ==# 'aarch64'
      return 'aarch64-unknown-linux-gnu'
    elseif l:uname_m =~# '^armv7'
      return 'armv7-unknown-linux-gnueabihf'
    endif
  endif

  " Fallback
  return 'x86_64-unknown-linux-gnu'
endfunction


" Download the tmc-langs-cli binary into the given path.  The function
" constructs a download URL based on the detected target triple and a
" version number (configurable via g:tmc_cli_version, defaulting to
" 0.38.1).  It uses curl to fetch the binary, verifies its SHA‑256 checksum
" using a companion .sha256 file, and makes it executable.  On failure
" the user is notified via s:echo_error().
function! s:download_cli(bin_path) abort
  " Use version from g:tmc_cli_version or default to 0.38.1.  If you change
  " this default, also update the README accordingly.
  let l:version = get(g:, 'tmc_cli_version', '0.38.1')
  let l:target  = s:detect_target()
  " Windows executables have .exe suffix in the filename
  let l:fname = 'tmc-langs-cli-' . l:target . '-' . l:version
  if has('win32') || has('win64')
    let l:fname .= '.exe'
  endif
  " The official builds are hosted on download.mooc.fi under tmc-langs-rust.
  let l:url = 'https://download.mooc.fi/tmc-langs-rust/' . l:fname
  " Ensure destination directory exists
  let l:dir = fnamemodify(a:bin_path, ':h')
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
  " Build curl command.  -L follows redirects, -f fails on HTTP errors.
  let l:cmd = 'curl -L -f -o ' . shellescape(a:bin_path) . ' ' . shellescape(l:url)
  let l:out = system(l:cmd)
  if v:shell_error
    call s:echo_error('Failed to download tmc-langs-cli from ' . l:url . ': ' . l:out)
    return
  endif
  " Verify checksum by downloading the .sha256 file and comparing to the local file.
  let l:sha_url = l:url . '.sha256'
  let l:expected_out = system('curl -L -s -f ' . shellescape(l:sha_url))
  if v:shell_error || empty(l:expected_out)
    call s:echo_error('Failed to fetch checksum from ' . l:sha_url)
  else
    " The .sha256 file may contain the checksum followed by filename. Extract the
    " first token (hex string).
    let l:expected = matchstr(l:expected_out, '^\x\+\>')
    " Compute actual checksum with Vim’s built‑in sha256file().  Fallback to
    " system sha256sum if the function is unavailable.
    if exists('*sha256file')
      let l:actual = sha256file(a:bin_path)
    else
      let l:shasum = system('sha256sum ' . shellescape(a:bin_path))
      let l:actual = matchstr(l:shasum, '^\x\+')
    endif
    if tolower(l:actual) !=# tolower(l:expected)
      call s:echo_error('Checksum mismatch for downloaded tmc-langs-cli. Expected ' . l:expected . ', got ' . l:actual)
      " Remove the invalid binary
      call delete(a:bin_path)
      return
    endif
  endif
  " Make executable on Unix
  if !has('win32') && !has('win64') && filereadable(a:bin_path)
    call system('chmod +x ' . shellescape(a:bin_path))
  endif
endfunction

" Ensure that the CLI binary exists and s:cli_path points to it.  This
" function is called automatically by tmc#run_cli() when s:cli_path is
" unset or unreadable.  It checks g:tmc_cli_path first and uses it if
" readable.  Otherwise, downloads a suitable binary into the cache.  The
" resolved path is stored in s:cli_path for subsequent invocations.
function! tmc#ensure_cli() abort
  " If the user explicitly set a path, honour it if readable
  if exists('g:tmc_cli_path') && filereadable(g:tmc_cli_path)
    let s:cli_path = g:tmc_cli_path
    return s:cli_path
  endif
  let l:bin = s:get_cli_binary_path()
  if !filereadable(l:bin)
    call s:download_cli(l:bin)
  endif
  if filereadable(l:bin)
    let s:cli_path = l:bin
    return l:bin
  endif
  " As a last resort use the bare command name; may rely on system PATH
  let s:cli_path = 'tmc-langs-cli'
  return s:cli_path
endfunction

" Run the CLI with the given argument list.  Returns a Vim dictionary on
" success or an empty dictionary on failure.  If the CLI exits non‑zero or
" JSON parsing fails, an error is echoed.
function! tmc#run_cli(args) abort
  " Ensure that the CLI binary is available before running.  If the user has
  " not provided g:tmc_cli_path, tmc#ensure_cli() will download a prebuilt
  " binary into a cache directory and update s:cli_path accordingly.
  if s:cli_path ==# '' || !filereadable(s:cli_path)
    call tmc#ensure_cli()
  endif
  " Determine how to build the command based on the first argument.
  " Some top-level commands (e.g. run-tests, checkstyle) are invoked
  " directly on the CLI without the 'tmc' subcommand or client flags.  Commands
  " that communicate with the TMC server (e.g. login, get-courses) are
  " dispatched under the 'tmc' subcommand and include --client-name and
  " --client-version flags.
  " Ensure the argument list is not empty.  a:args is expected to be a List
  " of strings.  If it is empty or not a List, nothing can be executed.
  if type(a:args) != type([]) || len(a:args) == 0
    call s:echo_error('No command provided to run_cli')
    return {}
  endif
  let l:first = a:args[0]
  " List of top-level commands that do not require the 'tmc' subcommand or
  " client identification flags.  These operate purely on local files.
  let l:top_level = ['run-tests', 'checkstyle', 'clean', 'compress-project',
        \ 'extract-project', 'fast-available-points', 'find-exercises',
        \ 'get-exercise-packaging-configuration', 'list-local-tmc-course-exercises',
        \ 'prepare-solution', 'prepare-stub', 'prepare-submission',
        \ 'refresh-course', 'settings', 'scan-exercise', 'help']
  " If the first arg is one of the top-level commands, build the command
  " without the 'tmc' subcommand and without client flags.
  if index(l:top_level, l:first) >= 0
    let l:cmd_parts = [s:cli_path]
    call extend(l:cmd_parts, a:args)
  elseif l:first ==# 'tmc' || l:first ==# 'mooc'
    " When the user explicitly specifies 'tmc' or 'mooc' as the first
    " argument, preserve it and inject client flags after it.
    let l:cmd_parts = [s:cli_path, l:first, '--client-name', s:client_name, '--client-version', s:client_version]
    call extend(l:cmd_parts, a:args[1:])
  else
    " Otherwise assume a server subcommand and prefix with 'tmc' plus flags.
    let l:cmd_parts = [s:cli_path, 'tmc', '--client-name', s:client_name, '--client-version', s:client_version]
    call extend(l:cmd_parts, a:args)
  endif
  " Quote parts containing whitespace to prevent splitting, but avoid quoting
  " simple identifiers such as slugs.  If a part contains spaces or tabs,
  " wrap it in double quotes, escaping any double quotes within.
  let l:escaped_parts = []
  for part in l:cmd_parts
    if match(part, '\\s') != -1
      let l:escaped = substitute(part, '"', '\\"', 'g')
      call add(l:escaped_parts, '"' . l:escaped . '"')
    else
      call add(l:escaped_parts, part)
    endif
  endfor
  let l:cmd = join(l:escaped_parts, ' ')
  let l:out = system(l:cmd)
  if v:shell_error
    call s:echo_error('tmc-langs-cli failed: ' . l:out)
    return {}
  endif
  try
    let l:json = json_decode(l:out)
  catch
    call s:echo_error('Failed to parse tmc-langs-cli output')
    return {}
  endtry
  " If the CLI signals an error result, surface the message to the user.
  if type(l:json) == type({}) && has_key(l:json, 'result') && l:json['result'] ==# 'error'
    if has_key(l:json, 'message')
      call s:echo_error('tmc-langs-cli: ' . l:json['message'])
    else
      call s:echo_error('tmc-langs-cli reported an error')
    endif
    " Still return the json so callers can inspect
  endif
  return l:json
endfunction

function! tmc#run_cli_streaming(args) abort
  call tmc#ensure_cli()

  if type(a:args) != type([]) || empty(a:args)
    call s:echo_error('No command provided to run_cli_streaming')
    return []
  endif

  let l:first = a:args[0]
  let l:top_level = ['run-tests','checkstyle','clean','compress-project',
        \ 'extract-project','fast-available-points','find-exercises',
        \ 'get-exercise-packaging-configuration',
        \ 'list-local-tmc-course-exercises','prepare-solution',
        \ 'prepare-stub','prepare-submission','refresh-course','settings',
        \ 'scan-exercise','help']
  if index(l:top_level, l:first) >= 0
    let l:cmd_parts = [s:cli_path]
    call extend(l:cmd_parts, a:args)
  elseif l:first ==# 'tmc' || l:first ==# 'mooc'
    let l:cmd_parts = [s:cli_path, l:first, '--client-name', s:client_name, '--client-version', s:client_version]
    call extend(l:cmd_parts, a:args[1:])
  else
    let l:cmd_parts = [s:cli_path, 'tmc', '--client-name', s:client_name, '--client-version', s:client_version]
    call extend(l:cmd_parts, a:args)
  endif

  let l:escaped = []
  for p in l:cmd_parts
    if match(p, '\s') != -1
      call add(l:escaped, '"' . substitute(p, '"', '\\"', 'g') . '"')
    else
      call add(l:escaped, p)
    endif
  endfor
  let l:cmd = join(l:escaped, ' ')

  let l:lines = systemlist(l:cmd)
  let l:objs = []
  for ln in l:lines
    try
      call add(l:objs, json_decode(ln))
    catch
      " ignore non-JSON
    endtry
  endfor

  return l:objs
endfunction

" Login to the TMC server.  Optionally accepts an email address; if omitted
" the user is prompted.  Password is always prompted via inputsecret().
function! tmc#login(...) abort
  " Prompt for email and password.  Email may be provided as a command
  " argument; password is always prompted via inputsecret().
  let l:email = ''
  if a:0 >= 1
    let l:email = a:1
  else
    let l:email = input('TMC email: ')
  endif
  let l:password = inputsecret('Password: ')
  " Build the login command manually so we can pass the password via stdin.
  " Ensure CLI is available and client flags are included.  Use the 'tmc'
  " subcommand and do not call tmc#run_cli() because that uses system()
  " without input redirection.
  call tmc#ensure_cli()
  let l:cmd_list = [s:cli_path, 'tmc', '--client-name', s:client_name, '--client-version', s:client_version,
        \ 'login', '--email', l:email, '--stdin']
  let l:cmd = join(l:cmd_list, ' ')
  " Pass the password via stdin with a trailing newline so the CLI reads it.
  let l:out = system(l:cmd, l:password . "\n")
  if v:shell_error
    call s:echo_error('tmc-langs-cli login failed: ' . l:out)
    return
  endif
  try
    let l:json = json_decode(l:out)
  catch
    echom 'Login response: ' . l:out
    return
  endtry
  if has_key(l:json, 'status') && has_key(l:json, 'message')
    echom l:json['status'] . ': ' . l:json['message']
  else
    echom 'Login command executed'
  endif
endfunction

" List available courses.  Uses organisation "mooc" by default.  Prints
" course id and name on separate lines.
function! tmc#list_courses() abort
  " Use the configured organisation slug when listing courses.  The CLI expects
  " an organisation slug (for example 'mooc' or 'hy') via --organization
  " according to the GetCourses definition.
  let l:org = get(g:, 'tmc_organization', 'mooc')
  let l:json = tmc#run_cli(['get-courses','--organization', l:org])
  if empty(l:json)
    return
  endif
  if has_key(l:json, 'data')
    let l:data = l:json['data']
    let l:courses_list = []
    " Prefer output-data if it is an array of course objects.  Some CLI
    " versions populate output-data regardless of output-data-kind.  Fallback
    " to data.courses for older formats.
    if has_key(l:data, 'output-data') && type(l:data['output-data']) == type([])
      let l:courses_list = l:data['output-data']
    elseif has_key(l:data, 'courses')
      let l:courses_list = l:data['courses']
    elseif has_key(l:data, 'output-data-kind') && l:data['output-data-kind'] ==# 'courses' && has_key(l:data, 'output-data')
      let l:courses_list = l:data['output-data']
    endif
    if !empty(l:courses_list)
      let l:lines = []
      for course in l:courses_list
        if has_key(course, 'id') && has_key(course, 'name')
          call add(l:lines, printf('%s: %s', course['id'], course['name']))
        endif
      endfor
      if !empty(l:lines)
        echo join(l:lines, "\n")
        return
      endif
    endif
  endif
  echom 'No courses found'
endfunction

" List exercises for a given course id.  Prints id and name for each exercise.
function! tmc#list_exercises(course_id) abort
  if empty(a:course_id)
    call s:echo_error('Usage: :TmcExercises <course-id>')
    return
  endif
  let l:json = tmc#run_cli(['get-course-exercises','--course-id', a:course_id])
  if empty(l:json)
    return
  endif
  if has_key(l:json, 'data')
    let l:data = l:json['data']
    let l:ex_list = []
    " Use output-data if it is a list of exercises; otherwise fallback to exercises key.  Some
    " CLI versions return exercises under output-data regardless of output-data-kind.
    if has_key(l:data, 'output-data') && type(l:data['output-data']) == type([])
      let l:ex_list = l:data['output-data']
    elseif has_key(l:data, 'exercises')
      let l:ex_list = l:data['exercises']
    elseif has_key(l:data, 'output-data-kind') && l:data['output-data-kind'] ==# 'exercises' && has_key(l:data, 'output-data')
      let l:ex_list = l:data['output-data']
    endif
    if !empty(l:ex_list)
      for ex in l:ex_list
        if has_key(ex, 'id') && has_key(ex, 'name')
          echom ex['id'] . ': ' . ex['name']
        endif
      endfor
      return
    endif
  endif
  echom 'No exercises found for course ' . a:course_id
endfunction

" Internal helper: fetch exercise ids for a given course.  Returns a list of
" strings representing exercise identifiers.  Uses the same parsing logic as
" tmc#list_exercises() but returns the ids instead of printing them.
function! s:get_exercise_ids(course_id) abort
  let l:json = tmc#run_cli(['get-course-exercises','--course-id', a:course_id])
  let l:ids = []
  if !empty(l:json) && has_key(l:json, 'data')
    let l:data = l:json['data']
    let l:list = []
    if has_key(l:data, 'output-data') && type(l:data['output-data']) == type([])
      let l:list = l:data['output-data']
    elseif has_key(l:data, 'exercises')
      let l:list = l:data['exercises']
    elseif has_key(l:data, 'output-data-kind') && l:data['output-data-kind'] ==# 'exercises' && has_key(l:data, 'output-data')
      let l:list = l:data['output-data']
    endif
    for ex in l:list
      if has_key(ex, 'id')
        call add(l:ids, string(ex['id']))
      endif
    endfor
  endif
  return l:ids
endfunction

" Compute a fallback path for the current course when the CLI does not report
" any downloaded or skipped exercises (for example when everything was
" already downloaded).  Uses the course name to
" construct a slug like <course-name> with non-alphanumeric
" characters replaced by hyphens.  Default path is get from env var, or if not
" found, the resulting path follows the systems
" default layout: <data_path>/tmc/<client-name>/<slug>.  If the
" course name is unknown, this function does nothing.  The computed path
" is stored in g:tmc_course_path.
" Compute a probable course path based on the organisation slug and the
" selected course name stored in g:tmc_course_name.  Returns the path as a
" string.  This does not create the directory on disk. 
function! s:compute_course_path(org) abort
  if !exists('g:tmc_course_name') || empty(g:tmc_course_name)
    return ''
  endif

  " Convert the course name to a slug
  let l:name_slug = substitute(tolower(g:tmc_course_name), '[^A-Za-z0-9]', '-', 'g')
  let l:name_slug = substitute(l:name_slug, '-\+', '-', 'g')
  let l:name_slug = substitute(l:name_slug, '^-\|-$', '', 'g')
  let l:slug = l:name_slug

  " Determine base directory
  if exists('$TMC_LANGS_DEFAULT_PROJECTS_DIR') && !empty($TMC_LANGS_DEFAULT_PROJECTS_DIR)
    let l:base = $TMC_LANGS_DEFAULT_PROJECTS_DIR . '/tmc_vim'
  elseif has('win32') || has('win64')
    let l:base = $LOCALAPPDATA . '/tmc/tmc_vim'
  else
    let l:base = expand('~/.local/share/tmc/tmc_vim')
  endif

  return l:base . '/' . l:slug
endfunction

" Download or update one or more exercises.  Accepts a list of exercise IDs.
function! tmc#download(...) abort
  if a:0 == 0
    call s:echo_error('Usage: :TmcDownload <exercise-id> ...')
    return
  endif
  let l:args = ['download-or-update-course-exercises']
  for id in a:000
    call extend(l:args, ['--exercise-id', id])
  endfor
  let l:json = tmc#run_cli(l:args)
  if empty(l:json)
    return
  endif
  " Display downloaded exercises
  if has_key(l:json, 'data') && has_key(l:json['data'], 'output-data-kind') &&
        \ l:json['data']['output-data-kind'] ==# 'tmc-exercise-download'
    let info = l:json['data']['output-data']
    if has_key(info, 'downloaded')
      for item in info['downloaded']
        echom 'Downloaded ' . item['exercise-slug'] . ' to ' . item['path']
      endfor
    endif
    if has_key(info, 'skipped')
      for item in info['skipped']
        echom 'Skipped ' . item['exercise-slug']
      endfor
    endif
  else
    echom 'Download completed'
  endif
endfunction

" Submit an exercise.  Expects two arguments: exercise id and submission path.
function! tmc#submit(...) abort
  if a:0 < 2
    call s:echo_error('Usage: :TmcSubmit <exercise-id> <submission-path>')
    return
  endif
  let l:id   = a:1
  let l:path = a:2
  let l:json = tmc#run_cli(['submit','--exercise-id', l:id,
        \ '--submission-path', l:path])
  if empty(l:json)
    return
  endif
  if has_key(l:json, 'status') && has_key(l:json, 'message')
    echom l:json['status'] . ': ' . l:json['message']
  else
    echom 'Submitted exercise ' . l:id
  endif
endfunction

" Set the active organisation slug for course listing.  This value is stored
" in g:tmc_organization and will be used by tmc#list_courses.  The slug
" corresponds to the organisation parameter of the CLI's GetCourses command.
function! tmc#set_organization(org) abort
  let g:tmc_organization = a:org
  echom 'Set TMC organisation to ' . a:org
endfunction

" Find the root directory of the current exercise by looking for known TMC
" metadata files.  Each exercise contains a `.tmcproject.yml` file in its
" root directory.  Starting from the directory of the current buffer, ascend
" the directory tree until this marker file is found or the filesystem root
" is reached.  Returns an empty string if no marker is found.
function! s:find_exercise_root() abort
  let l:buf_path = expand('%:p')
  if empty(l:buf_path)
    return ''
  endif
  let l:dir = isdirectory(l:buf_path) ? l:buf_path : fnamemodify(l:buf_path, ':h')
  while 1
    " Marker file that identifies an exercise root.  The presence of
    " `.tmcproject.yml` indicates an exercise root.
    if filereadable(l:dir . '/.tmcproject.yml')
      return l:dir
    endif
    let l:parent = fnamemodify(l:dir, ':h')
    if l:parent ==# l:dir
      break
    endif
    let l:dir = l:parent
  endwhile
  return ''
endfunction

" Attempt to read the exercise id from course_config.toml.  Each course
" contains a course_config.toml file in its root directory that maps
" exercise slugs to numeric IDs.  This function searches upward from
" the exercise directory for course_config.toml, finds the section
" corresponding to the current exercise slug, and returns the id value
" as a string.  If no id is found, returns an empty string.
function! s:get_exercise_id(root) abort
  " Determine the slug of the current exercise by taking the last directory name.
  let l:slug = fnamemodify(a:root, ':t')
  " Ascend directories looking for course_config.toml and parse the id for this slug.
  let l:dir = a:root
  while 1
    let l:toml_file = l:dir . '/course_config.toml'
    if filereadable(l:toml_file)
      " Parse the toml file manually: find [exercises.<slug>] section and id
      let l:lines = readfile(l:toml_file)
      let l:section = '[exercises.' . l:slug . ']'
      for l:idx in range(len(l:lines))
        if l:lines[l:idx] =~# '^\s*' . escape(l:section, '[]') . '\s*$'
          " Scan subsequent lines until next section
          let l:i = l:idx + 1
          while l:i < len(l:lines) && l:lines[l:i] !~# '^\s*\['
            if l:lines[l:i] =~# '^\s*id\s*=\s*\d\+'
              let l:idstr = matchstr(l:lines[l:i], '\d\+')
              return l:idstr
            endif
            let l:i += 1
          endwhile
        endif
      endfor
      " If section not found in this file, stop searching upward
      break
    endif
    let l:parent = fnamemodify(l:dir, ':h')
    if l:parent ==# l:dir
      break
    endif
    let l:dir = l:parent
  endwhile
  " If we didn't find the id, prompt the user; there is no legacy metadata fallback.
  return ''
endfunction

" Run tests for the exercise containing the current buffer.  The CLI provides
" a RunTests command which accepts --exercise-path to specify the exercise
" directory.  This function finds the exercise root and
" then invokes the CLI directly via system().  The output is displayed in a
" scratch buffer.
function! tmc#run_tests_current() abort
  call tmc#ensure_cli()

  let l:root = s:find_exercise_root()
  if empty(l:root)
    call s:echo_error('Could not locate exercise root (.tmcproject.yml not found)')
    return
  endif

  " Open scratch buffer
  tabnew
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  file tmc-test
  let g:tmc_test_buf = bufnr('%')
  let g:tmc_test_json = ''
  let g:tmc_test_logs = []

  " Enable syntax highlighting for test results
  setlocal syntax=tmcresult

  " Spinner
  let g:tmc_spinner_frames = ['⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏']
  let g:tmc_spinner_index = 0
  call setline(1, '⠋ Running tests...')
  let g:tmc_spinner_timer = timer_start(100, 's:RunTests_spinner_tick', {'repeat': -1})

  " CLI command
  let l:cmd = [s:cli_path,
        \ 'run-tests', '--exercise-path', l:root
        \ ]

  call jobstart(l:cmd, {
        \ 'stdout_buffered': v:false,
        \ 'stderr_buffered': v:false,
        \ 'on_stdout': {j, d, e -> s:RunTests_on_output(j, d)},
        \ 'on_stderr': {j, d, e -> s:RunTests_on_output(j, d)},
        \ 'on_exit':   function('s:RunTests_finalize'),
        \ })
endfunction

function! s:RunTests_spinner_tick(timer) abort
  if !exists('g:tmc_test_buf') || !bufloaded(g:tmc_test_buf)
    call timer_stop(a:timer)
    return
  endif
  let frame = g:tmc_spinner_frames[g:tmc_spinner_index]
  let g:tmc_spinner_index = (g:tmc_spinner_index + 1) % len(g:tmc_spinner_frames)
  call setbufline(g:tmc_test_buf, 1, frame . ' Running tests...')
endfunction

" Collect logs and final JSON
function! s:RunTests_on_output(job_id, data) abort
  for line in a:data
    if empty(line) | continue | endif

    if line =~ '{' && line =~ 'output-data-kind' && line =~ 'test-result'
      let g:tmc_test_json = line
    else
      " Replace literal \n with real line breaks for logs
      let cleaned = substitute(line, '\\n', "\n", 'g')
      call extend(g:tmc_test_logs, split(cleaned, "\n"))
    endif
  endfor
endfunction

" Finalize: write logs + results
function! s:RunTests_finalize(job_id, code, event) abort
  if exists('g:tmc_spinner_timer')
    call timer_stop(g:tmc_spinner_timer)
    unlet g:tmc_spinner_timer
  endif

  if !exists('g:tmc_test_buf') || !bufloaded(g:tmc_test_buf)
    return
  endif

  " Clear spinner line
  call deletebufline(g:tmc_test_buf, 1)

  " Write logs
  if !empty(g:tmc_test_logs)
    call appendbufline(g:tmc_test_buf, '$', '--- Logs ---')
    call appendbufline(g:tmc_test_buf, '$', g:tmc_test_logs)
    call appendbufline(g:tmc_test_buf, '$', ' ')
    execute 'normal! G'
  endif

  " Parse final JSON
  if empty(g:tmc_test_json)
    call appendbufline(g:tmc_test_buf, '$', '❌ No test results found')
    execute 'normal! G'
    normal! G
    return
  endif

  try
    let obj = json_decode(g:tmc_test_json)
  catch
    call appendbufline(g:tmc_test_buf, '$', '❌ Failed to parse test results')
    execute 'normal! G'
    normal! G
    return
  endtry

  let dat = obj['data']['output-data']
  let results = get(dat, 'testResults', [])
  let failed = 0
  let total = len(results)

  call appendbufline(g:tmc_test_buf, '$', '--- Results ---')
  execute 'normal! G'
  for tc in results
    let name = get(tc, 'name', 'Unnamed test')
    let message = substitute(get(tc, 'message', ''), '\\n', "\n", 'g')
    if get(tc, 'successful', v:false)
      call appendbufline(g:tmc_test_buf, '$', '✅ ' . name)
      execute 'normal! G'
    else
      let failed += 1
      call appendbufline(g:tmc_test_buf, '$', '❌ ' . name)
      execute 'normal! G'
      if !empty(message)
        for l in split(message, "\n")
          call appendbufline(g:tmc_test_buf, '$', '    ' . l)
          execute 'normal! G'
        endfor
      endif
    endif
  endfor

  call appendbufline(g:tmc_test_buf, '$', ' ')
  if failed == 0 && total > 0
    call appendbufline(g:tmc_test_buf, '$', '✅ All tests passed!')
    execute 'normal! G'
  else
    call appendbufline(g:tmc_test_buf, '$',
          \ printf('❌ %d tests failed (out of %d)', failed, total))
    execute 'normal! G'
  endif

  normal! G
  unlet g:tmc_test_json g:tmc_test_logs
endfunction



" Submit the exercise containing the current buffer.  Uses the CLI's
" tmc submit command, which takes both a --submission-path (the exercise
" directory) and an --exercise-id.  The exercise id is
" read from course_config.toml if present; otherwise the user is prompted for it.
" Results streaming progress into a scratch buffer,
" with async jobs if available, falling back to synchronous streaming.
f
function! tmc#submit_current() abort
  call tmc#ensure_cli()

  let l:root = s:find_exercise_root()
  if empty(l:root)
    call s:echo_error('Could not locate exercise root (.tmcproject.yml not found)')
    return
  endif

  let l:id = s:get_exercise_id(l:root)
  if empty(l:id)
    let l:id = input('Exercise ID: ')
    if empty(l:id)
      call s:echo_error('Submission cancelled: no exercise ID provided')
      return
    endif
  endif

  " Open scratch buffer for live output
  tabnew
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  file tmc-submit
  setlocal syntax=tmcresult
  let g:tmc_submit_buf = bufnr('%')
  let g:tmc_submit_last = {}

  " Build the CLI command
  let l:cmd = [
        \ s:cli_path, 'tmc',
        \ '--client-name', s:client_name, '--client-version', s:client_version,
        \ 'submit',
        \ '--exercise-id', l:id,
        \ '--submission-path', l:root
        \ ]

  " Async path
  if exists('*jobstart')
    call jobstart(l:cmd, {
          \ 'stdout_buffered': v:false,
          \ 'on_stdout': function('s:Submit_on_stdout_pretty'),
          \ 'on_exit':   function('s:Submit_on_exit_pretty'),
          \ 'stderr':    'ignore',
          \ })
    return
  elseif exists('*job_start')
    call job_start(l:cmd, {
          \ 'stdout_buffered': v:false,
          \ 'on_stdout': function('s:Submit_on_stdout_pretty'),
          \ 'on_exit':   function('s:Submit_on_exit_pretty'),
          \ 'stderr':    'ignore',
          \ })
    return
  endif
endfunction

function! s:Submit_on_stdout_pretty(job_id, data, event) abort
  for line in a:data
    if empty(line) | continue | endif
    try
      let obj = json_decode(line)
    catch
      continue
    endtry

    if get(obj, 'output-kind', '') ==# 'status-update'
      if exists('g:tmc_submit_buf') && bufloaded(g:tmc_submit_buf)
        call appendbufline(g:tmc_submit_buf, '$',
              \ printf('⏳ %3.0f%% %s', obj['percent-done'] * 100, obj['message']))
        execute 'normal! G'
      endif
    elseif get(obj, 'output-kind', '') ==# 'output-data'
      let g:tmc_submit_last = obj
    endif
  endfor
endfunction

function! s:Submit_on_exit_pretty(job_id, data, event) abort
  if empty(g:tmc_submit_last)
    if exists('g:tmc_submit_buf') && bufloaded(g:tmc_submit_buf)
      call appendbufline(g:tmc_submit_buf, '$', '❌ Submission ended without result')
      execute 'normal! G'
    endif
    return
  endif

  let dat = g:tmc_submit_last['data']['output-data']
  if exists('g:tmc_submit_buf') && bufloaded(g:tmc_submit_buf)
    call appendbufline(g:tmc_submit_buf, '$',
          \ printf('--- Results ---'))
    execute 'normal! G'
    if get(dat, 'all_tests_passed', v:false)
      call appendbufline(g:tmc_submit_buf, '$', '✅ All tests passed!')
      execute 'normal! G'
    else
      call appendbufline(g:tmc_submit_buf, '$', '❌ Some tests failed:')
      execute 'normal! G'
      for tc in get(dat, 'test_cases', [])
        if !tc['successful']
          call appendbufline(g:tmc_submit_buf, '$',
                \ printf('  ❌ %s: %s',
                \ tc['name'],
                \ substitute(tc['message'], '\n', '\\n', 'g')))
        else
          call appendbufline(g:tmc_submit_buf, '$',
                \ printf('  ✅ %s passed', tc['name']))
          execute 'normal! G'
        endif
      endfor
    endif
    call appendbufline(g:tmc_submit_buf, '$', '🔗 Submission URL: ' . dat['submission_url'])
  endif
endfunction


" Generic dispatcher: run an arbitrary tmc subcommand with arguments.  This
" helper simply forwards its arguments to tmc#run_cli().  Use via
" :Tmc <subcommand> [args...].  The 'tmc' subcommand itself is automatically
" inserted by tmc#run_cli(), so do not include it in the argument list.
function! tmc#run_generic(...) abort
  " Build a list from the arguments passed to the function.  a:000 is a
  " List of arguments as separate strings.  We simply forward it to
  " tmc#run_cli().  If no arguments are given, do nothing.
  if a:0 == 0
    call s:echo_error('Usage: :Tmc <subcommand> [args...]')
    return
  endif
  let l:json = tmc#run_cli(a:000)
  if empty(l:json)
    return
  endif
  " Pretty-print the JSON output as lines in the message area.
  if has_key(l:json, 'status') && has_key(l:json, 'message')
    echom l:json['status'] . ': ' . l:json['message']
  else
    echom string(l:json)
  endif
endfunction


" Fetch a list of organisations from the TMC server and prompt the user to
" choose one.  Returns the selected organisation slug or an empty string on
" cancellation.  The organisations are fetched via the CLI's
" get-organizations command (part of the GetOrganizations subcommand).  If
" fetching fails or no organisations are returned, an error is displayed.

" Async: Prompt user to pick an organization

function! tmc#pick_organization(cb) abort
  let l:json = tmc#run_cli(['get-organizations'])
  if empty(l:json)
    call a:cb('')
    return
  endif

  let l:orgs = []
  if has_key(l:json, 'data')
    if has_key(l:json['data'], 'output-data-kind') && l:json['data']['output-data-kind'] ==# 'organizations' && has_key(l:json['data'], 'output-data')
      for org in l:json['data']['output-data']
        if has_key(org, 'slug') && has_key(org, 'name')
          call add(l:orgs, printf('%s (%s)', org['slug'], org['name']))
        elseif has_key(org, 'slug')
          call add(l:orgs, org['slug'])
        endif
      endfor
    elseif has_key(l:json['data'], 'organizations')
      for org in l:json['data']['organizations']
        if has_key(org, 'slug') && has_key(org, 'name')
          call add(l:orgs, printf('%s (%s)', org['slug'], org['name']))
        elseif has_key(org, 'slug')
          call add(l:orgs, org['slug'])
        endif
      endfor
    endif
  endif

  if empty(l:orgs)
    call s:echo_error('No organisations found')
    call a:cb('')
    return
  endif

  " Async selection
  call tmc#ui_select(l:orgs, 'Select organisation:', {choice ->
        \ (empty(choice)
        \   ? call(a:cb, [''])
        \   : call(a:cb, [substitute(split(choice)[0], "['\"]", '', 'g')]))})
endfunction


" Prompt the user to select a course from the given organisation.  First
" fetches courses via get-courses, then displays them in a popup.  Returns
" the selected course id as a string or an empty string on cancellation.

" Async: Prompt user to pick a course

function! tmc#pick_course(org, cb) abort
  if empty(a:org)
    call a:cb('')
    return
  endif

  let l:json = tmc#run_cli(['get-courses','--organization', a:org])
  if empty(l:json)
    call a:cb('')
    return
  endif

  let l:courses = []
  if has_key(l:json, 'data')
    let l:data = l:json['data']
    let l:list = []
    if has_key(l:data, 'output-data-kind') && l:data['output-data-kind'] ==# 'courses' && has_key(l:data, 'output-data')
      let l:list = l:data['output-data']
    elseif has_key(l:data, 'courses')
      let l:list = l:data['courses']
    endif
    for c in l:list
      if has_key(c, 'id') && has_key(c, 'name')
        call add(l:courses, printf('%s: %s', c['id'], c['name']))
      endif
    endfor
  endif

  if empty(l:courses)
    call s:echo_error('No courses found for organisation ' . a:org)
    call a:cb('')
    return
  endif

  " Async selection
  call tmc#ui_select(l:courses, 'Select course:', {choice ->
        \ (empty(choice)
        \   ? call(a:cb, [''])
        \   : (function('s:parse_course_choice'))(choice, a:cb))})
endfunction

function! s:parse_course_choice(choice, cb) abort
  let l:parts = split(a:choice, ':', 2)
  let l:cid = ''
  let l:cname = ''
  if len(l:parts) >= 1
    let l:cid = substitute(trim(l:parts[0]), "['\"]", '', 'g')
  endif
  if len(l:parts) >= 2
    let l:cname = trim(l:parts[1])
  endif
  if !empty(l:cname)
    let g:tmc_course_name = l:cname
  endif
  let g:tmc_course_id = l:cid
  call a:cb(l:cid)
endfunction

" Command: TmcPickCourse.  Presents a two‑stage selection to choose an
" organisation and then a course.  Updates g:tmc_organization to the
" selected organisation, echoes the selected course id and name, and runs
" tmc#list_exercises for the chosen course.  This simplifies starting a new
" exercise session.
function! tmc#pick_course_command() abort
  if !exists('g:tmc_organization') || empty(g:tmc_organization)
    call tmc#pick_organization({org ->
          \ (empty(org)
          \   ? ''
          \   : s:handle_org_selection(org))})
  else
    call tmc#pick_course(g:tmc_organization, {course_id -> s:after_pick_course_async(g:tmc_organization, course_id)})
  endif
endfunction

function! s:handle_org_selection(org) abort
  let g:tmc_organization = a:org
  call tmc#pick_course(a:org, {course_id -> s:after_pick_course_async(a:org, course_id)})
endfunction


function! s:after_pick_course_async(org, course_id) abort
  if empty(a:course_id)
    return
  endif

  echom 'Selected organisation: ' . a:org
  echom 'Selected course: ' . a:course_id

  call tmc#download_course_exercises(a:course_id, a:org, {cid ->
        \ (empty(cid)
        \   ? ''
        \   : s:after_download_async(a:org, cid))})
endfunction

function! s:after_download_async(org, course_id) abort
  " ✅ Wait a bit to ensure all files are written
  sleep 100m

  if exists('g:tmc_course_name') && !empty(g:tmc_course_name)
    call tmc#cd_course()
  endif

  call tmc#list_exercises(a:course_id)
endfunction


" Command: Pick an organisation and store it in g:tmc_organization.  This
" allows the user to change the active organisation without immediately
" selecting a course.  See tmc#pick_organization() for implementation.
function! tmc#pick_organization_command() abort
  call tmc#pick_organization({org ->
        \ execute(empty(org)
        \   ? ''
        \   : 'let g:tmc_organization = "' . org . '" | echom "Selected organisation: ' . org . '"')})
endfunction



" Change the current working directory to the last downloaded course path.
" The path is stored in g:tmc_course_path by tmc#download_course_exercises().
function! tmc#cd_course() abort
  " Compute the course path on demand.  Requires that a course name and
  " organisation have been selected.  g:tmc_course_name and g:tmc_organization
  " are set when a course is picked via TmcPickCourse.
  if !exists('g:tmc_course_name') || empty(g:tmc_course_name)
    call s:echo_error('No course selected; pick a course first')
    return
  endif
  if !exists('g:tmc_organization') || empty(g:tmc_organization)
    call s:echo_error('No organisation selected; pick an organisation first')
    return
  endif
  let l:path = s:compute_course_path(g:tmc_organization)
  if empty(l:path)
    call s:echo_error('Could not determine course directory')
    return
  endif
  execute 'cd' fnameescape(l:path)
  echom 'Changed directory to ' . l:path
endfunction

" Download all exercises for the given course id into a structured directory
" under the user's data folder.  The directory structure is
"   <system_data_path>/tmc/tmc_vim/<course-slug>/
" " on older versions.  The organisation slug is passed explicitly to avoid
" reliance on g:tmc_organization.  This function temporarily changes the
" working directory to the target folder so that the CLI writes files there.
function! tmc#download_course_exercises(course_id, org, cb) abort
  if empty(a:course_id)
    call s:echo_error('No course id provided')
    call a:cb('')
    return
  endif

  let l:exercise_ids = s:get_exercise_ids(a:course_id)
  if empty(l:exercise_ids)
    echom 'No exercises to download for course ' . a:course_id
    call a:cb('')
    return
  endif

  " Open scratch buffer
  tabnew
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  file tmc-download
  setlocal syntax=tmcresult
  let g:tmc_download_buf = bufnr('%')

  " Build CLI command
  let l:args = [s:cli_path, 'tmc',
        \ '--client-name', s:client_name, '--client-version', s:client_version,
        \ 'download-or-update-course-exercises']
  for id in l:exercise_ids
    call extend(l:args, ['--exercise-id', id])
  endfor

  call jobstart(l:args, {
        \ 'stdout_buffered': v:false,
        \ 'on_stdout': function('s:Download_on_stdout_pretty'),
        \ 'on_exit':   {j, code, e -> s:Download_on_exit_pretty(j, code, e, a:course_id, a:cb)},
        \ 'stderr':    'ignore',
        \ })
endfunction

function! s:Download_on_stdout_pretty(job_id, data, event) abort
  for line in a:data
    if empty(line) | continue | endif
    try
      let obj = json_decode(line)
    catch
      continue
    endtry

    if get(obj, 'output-kind', '') ==# 'status-update' && has_key(obj, 'message')
      if exists('g:tmc_download_buf') && bufloaded(g:tmc_download_buf)
        call appendbufline(g:tmc_download_buf, '$', '⏳ ' . obj['message'])
        execute 'normal! G'  | " keep view scrolled to bottom
      endif
    elseif get(obj, 'output-kind', '') ==# 'output-data'
      let g:tmc_last_download_result = obj
    endif
  endfor
endfunction

function! s:Download_on_exit_pretty(job_id, code, event, course_id, cb) abort
  if a:code != 0
    call s:echo_error('Failed to download exercises for course ' . a:course_id)
    call a:cb('')
    return
  endif

  if exists('g:tmc_download_buf') && bufloaded(g:tmc_download_buf)
    let downloaded_count = 0
    let skipped_count = 0
    let failed_count = 0
    let failed_due_to_permission = 0

    call appendbufline(g:tmc_download_buf, '$', '✅ Download completed successfully')

    if exists('g:tmc_last_download_result')
      let obj = g:tmc_last_download_result
      if has_key(obj, 'data') && has_key(obj['data'], 'output-data')
        let data = obj['data']['output-data']

        " Downloaded
        if has_key(data, 'downloaded')
          let downloaded_count = len(data['downloaded'])
          call appendbufline(g:tmc_download_buf, '$', '--- Downloaded ---')
          for item in data['downloaded']
            call appendbufline(g:tmc_download_buf, '$', '  ✅ ' . item['exercise-slug'])
          endfor
        endif

        " Skipped
        if has_key(data, 'skipped') && !empty(data['skipped'])
          let skipped_count = len(data['skipped'])
          call appendbufline(g:tmc_download_buf, '$', '--- Skipped ---')
          for item in data['skipped']
            call appendbufline(g:tmc_download_buf, '$', '  ⚠️  ' . item['exercise-slug'])
          endfor
        endif

        " Failed
        if has_key(data, 'failed') && !empty(data['failed'])
          let failed_count = len(data['failed'])
          call appendbufline(g:tmc_download_buf, '$', '--- Failed ---')
          for failure in data['failed']
            let ex_info = failure[0]
            let reason  = join(failure[1], ' ')
            if reason =~? '403 Forbidden'
              let failed_due_to_permission += 1
            endif
            call appendbufline(g:tmc_download_buf, '$', '  ❌ ' . ex_info['exercise-slug'] . ': ' . reason)
          endfor
        endif
      endif
      unlet g:tmc_last_download_result
    endif

    " Add summary
    call appendbufline(g:tmc_download_buf, '$', '--- Summary ---')
    call appendbufline(g:tmc_download_buf, '$',
          \ printf('✅ %d downloaded, ⚠️  %d skipped, ❌ %d failed',
          \ downloaded_count, skipped_count, failed_count))

    if failed_due_to_permission > 0
      call appendbufline(g:tmc_download_buf, '$', '💡 Note: Some failures may be due to exercises requiring you to submit previous ones first.')
    endif

    execute 'normal! G'
  endif

  sleep 200m
  call a:cb(a:course_id)
endfu

