
if exists('g:loaded_tmc_run_tests')
  finish
endif
let g:loaded_tmc_run_tests = 1

let s:last_result = {}
let s:logs = []

" ===========================
" Public: Run tests for current exercise
" ===========================
function! tmc#run_tests#current() abort
  call tmc#cli#ensure()

  let l:root = tmc#core#find_exercise_root()
  if empty(l:root)
    call tmc#core#error('Could not locate exercise root (.tmcproject.yml not found)')
    return
  endif

  let s:last_result = {}
  let s:logs = []

  " Open scratch buffer
  tabnew
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  file tmc-test
  setlocal syntax=tmcresult
  let l:buf = bufnr('%')

  " Start spinner
  call tmc#spinner#start(l:buf, 'Running tests...')

  " Build CLI command
  let l:cmd = [g:tmc_cli_path, 'run-tests', '--exercise-path', l:root]

  if exists('*jobstart')  " Neovim
    call jobstart(l:cmd, {
          \ 'stdout_buffered': v:false,
          \ 'stderr_buffered': v:false,
          \ 'on_stdout': function('s:on_stdout_nvim'),
          \ 'on_stderr': function('s:on_stdout_nvim'),
          \ 'on_exit':   {j, code, e -> s:on_exit(l:buf, code)},
          \ })
  elseif exists('*job_start')  " Vim8
    call job_start(l:cmd, {
          \ 'out_cb': function('s:on_stdout_vim'),
          \ 'err_cb': function('s:on_stdout_vim'),
          \ 'exit_cb': {ch, code -> s:on_exit(l:buf, code)},
          \ })
  else
    call s:run_fallback(l:cmd, l:buf)
  endif
endfunction

" ===========================
" Neovim stdout handler
" ===========================
function! s:on_stdout_nvim(job_id, data, event) abort
  call s:handle_stdout(a:data)
endfunction

" ===========================
" Vim8 stdout handler
" ===========================
function! s:on_stdout_vim(channel, msg) abort
  if empty(a:msg) | return | endif
  call s:handle_stdout(split(a:msg, "\n"))
endfunction

" ===========================
" Common stdout handler
" ===========================
function! s:handle_stdout(lines) abort
  for line in a:lines
    if empty(line) | continue | endif
    try
      let obj = json_decode(line)
    catch
      call add(s:logs, line)
      continue
    endtry

    if get(obj, 'output-kind', '') ==# 'status-update' && has_key(obj, 'message')
      call add(s:logs, '⏳ ' . obj['message'])
    elseif get(obj, 'output-kind', '') ==# 'output-data' &&
          \ get(obj, 'data', {})['output-data-kind'] ==# 'test-result'
      let s:last_result = obj
    endif
  endfor
endfunction

" ===========================
" Exit handler
" ===========================
function! s:on_exit(buf, code) abort
  call tmc#spinner#stop()
  call s:print_results(a:buf)
endfunction

" ===========================
" Fallback (sync)
" ===========================
function! s:run_fallback(cmd, buf) abort
  let l:objs = tmc#cli#run_streaming(a:cmd)
  for obj in l:objs
    if get(obj, 'output-kind', '') ==# 'output-data'
      let s:last_result = obj
    endif
  endfor
  call tmc#spinner#stop()
  call s:print_results(a:buf)
endfunction

" ===========================
" Print results
" ===========================
function! s:print_results(buf) abort
  if !bufloaded(a:buf)
    return
  endif

  " Print logs
  if !empty(s:logs)
    call appendbufline(a:buf, '$', '--- Logs ---')
    call appendbufline(a:buf, '$', s:logs)
  endif

  if empty(s:last_result)
    call appendbufline(a:buf, '$', '❌ No test results found')
    execute 'normal! G'
    return
  endif

  let dat = s:last_result['data']['output-data']
  let results = get(dat, 'testResults', [])
  let failed = 0
  let total = len(results)

  call appendbufline(a:buf, '$', '--- Results ---')

  " Show each test result individually
  for tc in results
    if get(tc, 'successful', v:false)
      call appendbufline(a:buf, '$', '✅ ' . tc['name'])
    else
      let failed += 1
      call appendbufline(a:buf, '$', '❌ ' . tc['name'] . ':')
      let msg = substitute(get(tc, 'message', ''), '\\n', "\n", 'g')
      call appendbufline(a:buf, '$', split(msg, "\n"))
    endif
  endfor

  " Summary
  if failed == 0 && total > 0
    call appendbufline(a:buf, '$', printf('✅ All %d tests passed!', total))
  elseif total > 0
    call appendbufline(a:buf, '$', printf('❌ %d of %d tests failed', failed, total))
  else
    call appendbufline(a:buf, '$', '⚠️  No tests were run')
  endif

  execute 'normal! G'
endfunction

