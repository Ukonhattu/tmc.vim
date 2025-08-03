
if exists('g:loaded_tmc_cli')
  finish
endif
let g:loaded_tmc_cli = 1

" ===========================
" CLI Management
" ===========================

" Default values
let g:cli_path = get(g:, 'tmc_cli_path', '')
let g:client_name = get(g:, 'tmc_client_name', 'tmc_vim')
let g:client_version = get(g:, 'tmc_client_version', '0.1.0')

" Detect CLI binary storage path
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

" Detect target triple
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

" Download CLI if missing
function! s:download_cli(bin_path) abort
  let l:version = get(g:, 'tmc_cli_version', '0.38.1')
  let l:target = s:detect_target()
  let l:fname = 'tmc-langs-cli-' . l:target . '-' . l:version
  if has('win32') || has('win64')
    let l:fname .= '.exe'
  endif
  let l:url = 'https://download.mooc.fi/tmc-langs-rust/' . l:fname

  " Create directory
  let l:dir = fnamemodify(a:bin_path, ':h')
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif

  let l:cmd = 'curl -L -f -o ' . shellescape(a:bin_path) . ' ' . shellescape(l:url)
  let l:out = system(l:cmd)
  if v:shell_error
    call tmc#core#echo_error('Failed to download tmc-langs-cli: ' . l:out)
    return
  endif

  " Make it executable
  if !has('win32') && !has('win64')
    call system('chmod +x ' . shellescape(a:bin_path))
  endif
endfunction

" Ensure CLI is installed
function! tmc#cli#ensure() abort
  if !empty(g:cli_path) && filereadable(g:cli_path)
    return g:cli_path
  endif

  let l:bin = s:get_binary_path()
  if !filereadable(l:bin)
    call s:download_cli(l:bin)
  endif

  if filereadable(l:bin)
    let g:cli_path = l:bin
  else
    let g:cli_path = 'tmc-langs-cli'
  endif
  return g:cli_path
endfunction

" ===========================
" CLI Runners
" ===========================

" Run CLI synchronously
function! tmc#cli#run(args) abort
  call tmc#cli#ensure()

  if type(a:args) != type([]) || empty(a:args)
    call tmc#core#echo_error('No command provided to run()')
    return {}
  endif

  let l:cmd_parts = s:build_command(a:args)
  let l:cmd = join(l:cmd_parts, ' ')
  let l:out = system(l:cmd)
  if v:shell_error
    call tmc#core#echo_error('tmc-langs-cli failed: ' . l:out)
    return {}
  endif

  try
    return json_decode(l:out)
  catch
    call tmc#core#echo_error('Failed to parse CLI output')
    return {}
  endtry
endfunction

" Run CLI streaming (returns list of JSON objects)
function! tmc#cli#run_streaming(args) abort
  call tmc#cli#ensure()

  let l:cmd_parts = s:build_command(a:args)
  let l:cmd = join(l:cmd_parts, ' ')
  let l:lines = systemlist(l:cmd)

  let l:objs = []
  for ln in l:lines
    try
      call add(l:objs, json_decode(ln))
    catch
    endtry
  endfor
  return l:objs
endfunction

" Build CLI command, adding client name/version automatically
function! s:build_command(args) abort
  let l:first = a:args[0]
  let l:top_level = [
        \ 'run-tests', 'checkstyle', 'clean', 'compress-project',
        \ 'extract-project', 'fast-available-points', 'find-exercises',
        \ 'get-exercise-packaging-configuration',
        \ 'list-local-tmc-course-exercises', 'prepare-solution',
        \ 'prepare-stub', 'prepare-submission', 'refresh-course', 'settings',
        \ 'scan-exercise', 'help'
        \ ]

  if index(l:top_level, l:first) >= 0
    return [g:cli_path] + a:args
  elseif l:first ==# 'tmc'
    return [g:cli_path, l:first, '--client-name', g:client_name, '--client-version', g:client_version] + a:args[1:]
  else
    return [g:cli_path, 'tmc', '--client-name', g:client_name, '--client-version', g:client_version] + a:args
  endif
endfunction

