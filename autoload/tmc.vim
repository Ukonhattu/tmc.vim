"
" This file implements helper functions for the Vim‑TMC plugin.  The functions
" execute `tmc‑langs‑cli` via system() and parse its JSON output using
" json_decode().  Error handling is centralized in the s:echo_error helper.

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
  if has('win32') || has('win64')
    return 'x86_64-pc-windows-msvc'
  endif
  let l:uname_s = substitute(system('uname -s'), '\n', '', 'g')
  let l:uname_m = substitute(system('uname -m'), '\n', '', 'g')
  if l:uname_s ==# 'Darwin'
    if l:uname_m ==# 'x86_64'
      return 'x86_64-apple-darwin'
    else
      " Assume Apple Silicon (aarch64)
      return 'aarch64-apple-darwin'
    endif
  endif
  " Linux – map known architectures
  if l:uname_m ==# 'x86_64'
    return 'x86_64-unknown-linux-gnu'
  elseif l:uname_m ==# 'i686' || l:uname_m ==# 'i386'
    return 'i686-unknown-linux-gnu'
  elseif l:uname_m ==# 'aarch64'
    return 'aarch64-unknown-linux-gnu'
  endif
  " Fallback to x86_64-unknown-linux-gnu
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
  " according to the GetCourses definition【419357596652847†L351-L357】.
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
" characters replaced by hyphens.  The resulting path follows the systems
" default layout: <data_path>/tmc/<client-name>/<slug>.  If the
" course name is unknown, this function does nothing.  The computed path
" is stored in g:tmc_course_path.
" Compute a probable course path based on the organisation slug and the
" selected course name stored in g:tmc_course_name.  Returns the path as a
" string.  This does not create the directory on disk.  The CLI stores
" courses <data_path>/tmc/<client-name>/<course-name-slug>.
function! s:compute_course_path(org) abort
  if !exists('g:tmc_course_name') || empty(g:tmc_course_name)
    return ''
  endif
  " Convert the course name to a slug.  Do not prepend the organisation slug
  " because the course name already includes it (e.g. 'mooc-data-analysis').
  let l:name_slug = substitute(tolower(g:tmc_course_name), '[^A-Za-z0-9]', '-', 'g')
  " Collapse consecutive hyphens and trim leading/trailing hyphens
  let l:name_slug = substitute(l:name_slug, '-\+', '-', 'g')
  let l:name_slug = substitute(l:name_slug, '^-\|-$', '', 'g')
  let l:slug = l:name_slug
  " Determine the base directory used by tmc‑langs‑cli for storing courses.
  " On Unix systems it is ~/.local/share/tmc/tmc_vim, and on Windows it
  " should be %LOCALAPPDATA%\tmc\tmc_vim.  We avoid using stdpath('data')
  " because Vim/Neovim's data path differs from the CLI's data path.
  if has('win32') || has('win64')
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
  " Ensure CLI binary is available
  call tmc#ensure_cli()
  let l:root = s:find_exercise_root()
  if empty(l:root)
    call s:echo_error('Could not locate exercise root (.tmcproject.yml not found)')
    return
  endif
  " Build the command for running tests.  The run-tests command is a
  " top-level CLI command (not under the 'tmc' subcommand) and does not
  " require client identification flags.  Construct the command accordingly.
  let l:cmd_list = [s:cli_path, 'run-tests', '--exercise-path', shellescape(l:root)]
  let l:cmd = join(l:cmd_list, ' ')
  let l:out = system(l:cmd)
  " Open a new scratch buffer to display the raw output.  Populate it with
  " the lines from the test output.  Avoid using split() directly in the
  " :put command to prevent E116 errors on some Vim versions.
  tabnew
  setlocal buftype=nofile bufhidden=wipe noswapfile
  let l:lines = split(l:out, "\n")
  if !empty(l:lines)
    call setline(1, l:lines)
  endif
  execute 'file tmc-test-results'
  redraw!
endfunction

" Submit the exercise containing the current buffer.  Uses the CLI's
" tmc submit command, which takes both a --submission-path (the exercise
" directory) and an --exercise-id.  The exercise id is
" read from course_config.toml if present; otherwise the user is prompted for it.

function! tmc#submit_current() abort
  " Ensure we have a working CLI binary
  call tmc#ensure_cli()

  " Find exercise root
  let l:root = s:find_exercise_root()
  if empty(l:root)
    call s:echo_error('Could not locate exercise root (.tmcproject.yml not found)')
    return
  endif

  " Determine the exercise ID
  let l:id = s:get_exercise_id(l:root)
  if empty(l:id)
    let l:id = input('Exercise ID: ')
    if empty(l:id)
      call s:echo_error('Submission cancelled: no exercise ID provided')
      return
    endif
  endif

  " Build and run the CLI submit command, capturing every JSON line
  let l:cmd_parts = [
        \ s:cli_path,
        \ 'tmc', '--client-name', s:client_name, '--client-version', s:client_version,
        \ 'submit',
        \ '--exercise-id', l:id,
        \ '--submission-path', shellescape(l:root)
        \ ]
  let l:lines = systemlist(join(l:cmd_parts, ' '))

  " Parse only the final “output-data” JSON object
  let l:result = {}
  for l:ln in l:lines
    try
      let l:obj = json_decode(l:ln)
      if has_key(l:obj, 'output-kind') && l:obj['output-kind'] ==# 'output-data'
        let l:result = l:obj
      endif
    catch
      " skip non-JSON or status-update lines
    endtry
  endfor

  if empty(l:result)
    call s:echo_error('Failed to parse submission result')
    return
  endif

  " Extract the payload and echo a summary
  let l:data = l:result['data']['output-data']
  echom printf('Submission %s: %s', l:result['status'], l:result['message'])
  if get(l:data, 'all_tests_passed', v:false)
    echom '✅ All tests passed!'
  else
    echom '❌ Some tests failed. See details above.'
  endif
  echom 'Submission URL: ' . l:data['submission_url']
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

" Utility: present a list of choices to the user and return the selected
" string.  Uses popup_menu() when available (Vim 8.2+) to display a popup
" window.  On Neovim or older Vim versions without popup support, falls back
" to inputlist().  The optional prompt is displayed as the popup title or
" prepended to the inputlist.  Returns an empty string if the user aborts.
function! s:select_from_list(items, prompt) abort
  let l:list = copy(a:items)
  " Convert numbers to strings
  for i in range(len(l:list))
    let l:list[i] = string(l:list[i])
  endfor
  if exists('*popup_menu')
    " Use popup_menu() which returns the index of the selection or 0 on abort
    let l:opts = {'title': a:prompt}
    let l:idx = popup_menu(l:list, l:opts)
    if l:idx < 1 || l:idx > len(l:list)
      return ''
    endif
    return l:list[l:idx - 1]
  else
    " Fallback: inputlist() – present numbered choices
    let l:choices = [a:prompt]
    for i in range(len(l:list))
      call add(l:choices, printf('%d. %s', i+1, l:list[i]))
    endfor
    let l:res = inputlist(l:choices)
    if l:res < 1 || l:res > len(l:list)
      return ''
    endif
    return l:list[l:res - 1]
  endif
endfunction

" Fetch a list of organisations from the TMC server and prompt the user to
" choose one.  Returns the selected organisation slug or an empty string on
" cancellation.  The organisations are fetched via the CLI's
" get-organizations command (part of the GetOrganizations subcommand).  If
" fetching fails or no organisations are returned, an error is displayed.
function! tmc#pick_organization() abort
  let l:json = tmc#run_cli(['get-organizations'])
  if empty(l:json)
    return ''
  endif
  " Extract organisations from the result.  The API typically returns an
  " array of objects with slug/name properties.  We display the slug and
  " optionally the name for clarity.
  let l:orgs = []
  " Newer CLI versions return organizations under data.output-data when
  " output-data-kind == 'organizations'.  Fallback to data.organizations for
  " older versions.
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
    return ''
  endif
  let l:choice = s:select_from_list(l:orgs, 'Select organisation:')
  if empty(l:choice)
    return ''
  endif
  " Extract the slug (part before space) if we appended name.
  " Some shells may insert stray quotes when invoking commands via
  " system().  Remove any single or double quotes anywhere in the slug
  " and trim whitespace from both ends.  Without this, a slug like
  " 'mooc would be passed to the CLI, causing a 404 error.
  let l:slug = split(l:choice)[0]
  let l:slug = trim(l:slug)
  let l:slug = substitute(l:slug, "['\"]", '', 'g')
  return l:slug
endfunction

" Prompt the user to select a course from the given organisation.  First
" fetches courses via get-courses, then displays them in a popup.  Returns
" the selected course id as a string or an empty string on cancellation.
function! tmc#pick_course(org) abort
  if empty(a:org)
    return ''
  endif
  " The 'get-courses' command should be passed directly to tmc#run_cli().
  " Do not prefix with 'tmc', since tmc#run_cli() already prepends the
  " 'core' subcommand and client flags.  Passing 'tmc' here would result
  " in an invalid command line.
  let l:json = tmc#run_cli(['get-courses','--organization', a:org])
  if empty(l:json)
    return ''
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
    return ''
  endif
  let l:choice = s:select_from_list(l:courses, 'Select course:')
  if empty(l:choice)
    return ''
  endif
  " Extract the id and name parts from the selection.  The format is
  " "<id>: <name>".  Store the course name globally so that other functions
  " (e.g. download_course_exercises) can derive the course path if needed.
  let l:parts = split(l:choice, ':', 2)
  let l:cid = ''
  let l:cname = ''
  if len(l:parts) >= 1
    let l:cid = trim(l:parts[0])
    let l:cid = substitute(l:cid, "['\"]", '', 'g')
  endif
  if len(l:parts) >= 2
    let l:cname = trim(l:parts[1])
  endif
  if !empty(l:cname)
    let g:tmc_course_name = l:cname
  endif
  let g:tmc_course_id = l:cid
  return l:cid
endfunction

" Command: TmcPickCourse.  Presents a two‑stage selection to choose an
" organisation and then a course.  Updates g:tmc_organization to the
" selected organisation, echoes the selected course id and name, and runs
" tmc#list_exercises for the chosen course.  This simplifies starting a new
" exercise session.
function! tmc#pick_course_command() abort
  " Pick an organisation only if none has been selected yet.  Use the
  " configured g:tmc_organization as the current organisation.  If it is
  " empty or unset, prompt the user via tmc#pick_organization().
  let l:org = get(g:, 'tmc_organization', '')
  if empty(l:org)
    let l:org = tmc#pick_organization()
    if empty(l:org)
      return
    endif
    " Persist the selected organisation for subsequent picks
    let g:tmc_organization = l:org
  endif
  " Prompt for a course within the current organisation
  let l:course_id = tmc#pick_course(l:org)
  if empty(l:course_id)
    return
  endif
  echom 'Selected organisation: ' . l:org
  echom 'Selected course: ' . l:course_id
  " Automatically download all exercises for the selected course into
  " a dedicated directory under the user’s data folder.  Then list
  " exercises for the course.
  call tmc#download_course_exercises(l:course_id, l:org)
  call tmc#list_exercises(l:course_id)
endfunction

" Command: Pick an organisation and store it in g:tmc_organization.  This
" allows the user to change the active organisation without immediately
" selecting a course.  See tmc#pick_organization() for implementation.
function! tmc#pick_organization_command() abort
  let l:org = tmc#pick_organization()
  if empty(l:org)
    return
  endif
  let g:tmc_organization = l:org
  echom 'Selected organisation: ' . l:org
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
function! tmc#download_course_exercises(course_id, org) abort
  if empty(a:course_id)
    call s:echo_error('No course id provided')
    return
  endif
  " The TMC CLI downloads exercises into its own data path (typically
  " ~/.local/share/tmc/tmc_vim/<course-slug>).  
  try
    " Fetch the list of exercise IDs for this course.  We need individual
    " exercise ids because the download command does not support --course-id.
    let l:exercise_ids = s:get_exercise_ids(a:course_id)
    if empty(l:exercise_ids)
      echom 'No exercises to download for course ' . a:course_id
      return
    endif
    " Build arguments: download-or-update-course-exercises repeated for each id
    let l:args = ['download-or-update-course-exercises']
    for id in l:exercise_ids
      call extend(l:args, ['--exercise-id', id])
    endfor
    let l:json = tmc#run_cli(l:args)
    if empty(l:json)
      return
    endif
    if has_key(l:json, 'data') && has_key(l:json['data'], 'output-data-kind') && l:json['data']['output-data-kind'] ==# 'tmc-exercise-download'
      let info = l:json['data']['output-data']
      " Determine the course path from the first downloaded or skipped exercise.
      let l:path_candidate = ''
      if has_key(info, 'downloaded') && len(info['downloaded']) > 0
        let l:path_candidate = info['downloaded'][0]['path']
      elseif has_key(info, 'skipped') && len(info['skipped']) > 0
        let l:path_candidate = info['skipped'][0]['path']
      endif
      
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
      echom 'Downloaded exercises for course ' . a:course_id
    endif
  finally
  endtry
endfunction
