
" autoload/tmc/cli.vim
" CLI bootstrap, download (with SHA-256 verification), generic exec helpers,
" settings helpers, and group-aware wrappers for `tmc` and `options`.

if exists('g:loaded_tmc_cli')
  finish
endif
let g:loaded_tmc_cli = 1

" ===========================
" Configuration (defaults)
" ===========================
let g:tmc_client_name    = get(g:, 'tmc_client_name', 'tmc_vim')
let g:tmc_client_version = get(g:, 'tmc_client_version', '0.1.0')
let g:tmc_cli_path       = get(g:, 'tmc_cli_path', '')
let g:tmc_cli_version    = get(g:, 'tmc_cli_version', '0.38.1')

" ===========================
" Locate / install tmc-langs-cli
" ===========================
function! s:get_storage_dir() abort
  if exists('*stdpath')
    return stdpath('data') . '/tmc'
  endif
  return expand('~/.vim/tmc')
endfunction

function! s:get_binary_path() abort
  let l:dir = s:get_storage_dir()
  let l:exe = 'tmc-langs-cli'
  if has('win32') || has('win64')
    let l:exe .= '.exe'
  endif
  return l:dir . '/' . l:exe
endfunction

function! s:detect_target() abort
  let l:uname_s = substitute(system('uname -s'), '\n', '', 'g')
  let l:uname_m = substitute(system('uname -m'), '\n', '', 'g')

  if has('win32') || has('win64')
    return (l:uname_m =~# '^i686') ? 'i686-pc-windows-msvc' : 'x86_64-pc-windows-msvc'
  elseif l:uname_s ==# 'Darwin'
    return (l:uname_m ==# 'x86_64') ? 'x86_64-apple-darwin' : 'aarch64-apple-darwin'
  elseif l:uname_s ==# 'Linux'
    if l:uname_m =~# '^x86_64'
      return 'x86_64-unknown-linux-gnu'
    elseif l:uname_m =~# '^\(i686\|i386\)$'
      return 'i686-unknown-linux-gnu'
    elseif l:uname_m ==# 'aarch64'
      return 'aarch64-unknown-linux-gnu'
    endif
  endif
  return 'x86_64-unknown-linux-gnu'
endfunction

" Download helper (tries versioned URL first, then legacy filename form)
function! s:download_cli(bin_path) abort
  let l:version = g:tmc_cli_version
  let l:target  = s:detect_target()
  let l:base_v  = 'https://download.mooc.fi/tmc-langs-rust/' . l:version . '/tmc-langs-cli-' . l:target
  let l:base_f  = 'https://download.mooc.fi/tmc-langs-rust/tmc-langs-cli-' . l:target . '-' . l:version
  if has('win32') || has('win64')
    let l:base_v .= '.exe'
    let l:base_f .= '.exe'
  endif

  " Ensure directory exists
  let l:dir = fnamemodify(a:bin_path, ':h')
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif

  " Try candidates in order
  for l:url in [l:base_v, l:base_f]
    if s:_download_one(l:url, a:bin_path) == 0
      " Verify checksum using matching .sha256 next to chosen URL
      let l:ok = s:_verify_sha256(l:url . '.sha256', a:bin_path)
      if !l:ok
        call delete(a:bin_path)
        call tmc#core#echo_error('tmc-langs-cli checksum verification failed.')
        return
      endif
      " Make it executable on POSIX
      if !has('win32') && !has('win64')
        call system('chmod +x ' . shellescape(a:bin_path))
      endif
      return
    endif
  endfor

  call tmc#core#echo_error('Failed to download tmc-langs-cli from known locations.')
endfunction

" Download a single URL into dst; returns 0 on success, non-zero on failure
function! s:_download_one(url, dst) abort
  if executable('curl')
    call system(['curl', '-fL', '-o', a:dst, a:url])
    return v:shell_error
  elseif has('win32') || has('win64')
    let l:ps = 'powershell -NoProfile -Command "(New-Object Net.WebClient).DownloadFile('''
          \ . a:url . ''', ''' . a:dst . ''')"'
    call system(l:ps)
    return v:shell_error
  else
    return 1
  endif
endfunction

" Verify downloaded file against a remote *.sha256; returns 1 on match, 0 otherwise
function! s:_verify_sha256(sha_url, path) abort
  if !executable('curl')
    " If we can't fetch checksum at all, treat as failure to be safe.
    return 0
  endif
  let l:tmp = tempname()
  try
    call system(['curl', '-fL', '-o', l:tmp, a:sha_url])
    if v:shell_error || !filereadable(l:tmp)
      return 0
    endif
    let l:expected = matchstr(join(readfile(l:tmp), "\n"), '\v^[0-9a-f]{64}')
    if empty(l:expected)
      return 0
    endif
    " Compute actual sha256
    if exists('*sha256')
      let l:data = join(readfile(a:path, 'b'), "\n")
      let l:actual = sha256(l:data)
    elseif executable('sha256sum')
      let l:actual = matchstr(system(['sha256sum', a:path]), '\v^[0-9a-f]{64}')
    elseif executable('shasum')
      let l:actual = matchstr(system(['shasum', '-a', '256', a:path]), '\v^[0-9a-f]{64}')
    else
      return 0
    endif
    return tolower(l:actual) == tolower(l:expected)
  finally
    if filereadable(l:tmp) | call delete(l:tmp) | endif
  endtry
endfunction

function! tmc#cli#ensure() abort
  if !empty(g:tmc_cli_path) && filereadable(g:tmc_cli_path)
    return g:tmc_cli_path
  endif
  let l:bin = s:get_binary_path()
  if !filereadable(l:bin)
    call s:download_cli(l:bin)
  endif
  if filereadable(l:bin)
    let g:tmc_cli_path = l:bin
  else
    let g:tmc_cli_path = 'tmc-langs-cli' " fallback to PATH
  endif
  return g:tmc_cli_path
endfunction

" ===========================
" Generic execution helpers (TMC + any external program)
" ===========================
function! tmc#cli#exec_json(args) abort
  let l:cli = tmc#cli#ensure()
  let l:cmd = [l:cli] + a:args
  let l:out = systemlist(l:cmd)
  if v:shell_error
    call tmc#core#echo_error('tmc-langs-cli failed: ' . join(l:out, "\n"))
    return {}
  endif
  try
    return json_decode(join(l:out, "\n"))
  catch
    call tmc#core#echo_error('Failed to parse tmc-langs-cli JSON output')
    return {}
  endtry
endfunction

function! tmc#cli#exec_raw(args) abort
  let l:cli = tmc#cli#ensure()
  let l:cmd = [l:cli] + a:args
  let l:out = systemlist(l:cmd)
  if v:shell_error
    call tmc#core#echo_error('tmc-langs-cli failed: ' . join(l:out, "\n"))
    return []
  endif
  return l:out
endfunction

" Run ANY external program in a uniform way.
" opts: { 'expect_json': v:true/v:false }
function! tmc#cli#exec_program(prog, args, opts) abort
  let l:cmd = [a:prog] + a:args
  let l:out = systemlist(l:cmd)
  if get(a:opts, 'expect_json', 0)
    try
      return {'ok': v:shell_error == 0, 'json': json_decode(join(l:out, "\n")), 'raw': l:out}
    catch
      return {'ok': 0, 'json': {}, 'raw': l:out}
    endtry
  endif
  return {'ok': v:shell_error == 0, 'raw': l:out}
endfunction

" ===========================
" Settings helpers (JSON)
" ===========================
" Example:
"   tmc#cli#settings_get('projects-dir', 'tmc_vim')
function! tmc#cli#settings_get(key, client) abort
  let l:client = empty(a:client) ? g:tmc_client_name : a:client
  let l:res = tmc#cli#exec_json(['settings', '--client-name', l:client, 'get', a:key])
  " Expected shape: { data: { "output-data": "<value>" } }
  if type(l:res) == type({}) && has_key(l:res, 'data')
    let l:data = l:res['data']
    if type(l:data) == type({}) && has_key(l:data, 'output-data')
      let l:val = l:data['output-data']
      if type(l:val) == type('') && !empty(l:val)
        return l:val
      endif
    endif
  endif
  return ''
endfunction

" Example:
"   let cfg = tmc#cli#settings_list('tmc_vim')
"   echo cfg['projects_dir']
function! tmc#cli#settings_list(client) abort
  let l:client = empty(a:client) ? g:tmc_client_name : a:client
  let l:res = tmc#cli#exec_json(['settings', '--client-name', l:client, 'list'])
  " Expected shape: { data: { "output-data": { ... } } }
  if type(l:res) == type({}) && has_key(l:res, 'data')
    let l:data = l:res['data']
    if type(l:data) == type({}) && has_key(l:data, 'output-data') && type(l:data['output-data']) == type({})
      return l:data['output-data']
    endif
  endif
  return {}
endfunction

" ===========================
" Group-aware wrappers: `tmc` and `options`
" ===========================
" NOTE:
"  - For the `tmc` group, inject --client-name and --client-version
"    immediately after `tmc`.
"  - For the `options` group, inject --client-name (but NOT version)
"    immediately after `options`.
"  - No --pretty flags here; JSON is parsed as-is.

function! tmc#cli#tmc_json(args) abort
  let l:pref = ['tmc', '--client-name', g:tmc_client_name, '--client-version', g:tmc_client_version]
  return tmc#cli#exec_json(l:pref + a:args)
endfunction

function! tmc#cli#tmc_raw(args) abort
  let l:pref = ['tmc', '--client-name', g:tmc_client_name, '--client-version', g:tmc_client_version]
  return tmc#cli#exec_raw(l:pref + a:args)
endfunction

function! tmc#cli#options_json(args) abort
  let l:pref = ['options', '--client-name', g:tmc_client_name]
  return tmc#cli#exec_json(l:pref + a:args)
endfunction

function! tmc#cli#options_raw(args) abort
  let l:pref = ['options', '--client-name', g:tmc_client_name]
  return tmc#cli#exec_raw(l:pref + a:args)
endfunction

" ===========================
" Convenience helpers for common `tmc` paths
" ===========================

" Organizations
function! tmc#cli#get_organizations() abort
  " tmc --client-name ... --client-version ... get-organizations
  return tmc#cli#tmc_json(['get-organizations'])
endfunction

" Courses for an org
function! tmc#cli#list_courses(org) abort
  " tmc ... get-courses --organization <org>
  return tmc#cli#tmc_json(['get-courses', '--organization', a:org])
endfunction

" Exercises for a course id
function! tmc#cli#list_exercises(course_id) abort
  " tmc ... get-course-exercises --course-id <id>
  return tmc#cli#tmc_json(['get-course-exercises', '--course-id', a:course_id])
endfunction


" ===========================
" Back-compat shim(s)
" ===========================
function! tmc#cli#run(args) abort
  " Older code may still call this; keep it working.
  return tmc#cli#exec_json(a:args)
endfunction

function! tmc#cli#run_streaming(args) abort
  " Return list of decoded JSON lines when CLI prints JSONL.
  let l:lines = tmc#cli#exec_raw(a:args)
  let l:objs = []
  for ln in l:lines
    try
      call add(l:objs, json_decode(ln))
    catch
    endtry
  endfor
  return l:objs
endfunction

