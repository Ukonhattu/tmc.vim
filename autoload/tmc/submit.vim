
if exists('g:loaded_tmc_submit')
  finish
endif
let g:loaded_tmc_submit = 1

let s:last_result = {}
let s:logs = []

" ===========================
" Public: Submit current exercise
" ===========================
function! tmc#submit#current() abort
  call tmc#cli#ensure()

  let l:root = tmc#core#find_exercise_root()
  if empty(l:root)
    call tmc#core#error('Could not locate exercise root (.tmcproject.yml not found)')
    return
  endif

  let l:id = tmc#core#get_exercise_id(l:root)
  if empty(l:id)
    let l:id = input('Exercise ID: ')
    if empty(l:id)
      call tmc#core#error('Submission cancelled: no exercise ID provided')
      return
    endif
  endif

  let s:last_result = {}
  let s:logs = []

  " Open scratch buffer
  tabnew
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  file tmc-submit
  setlocal syntax=tmcresult
  let l:buf = bufnr('%')

  " Spinner
  call tmc#spinner#start(l:buf, 'Submitting exercise...')

  let l:cmd = [g:cli_path, 'tmc',
        \ '--client-name', g:client_name,
        \ '--client-version', g:client_version,
        \ 'submit',
        \ '--exercise-id', l:id,
        \ '--submission-path', l:root]

  if exists('*jobstart')
    call jobstart(l:cmd, {
          \ 'stdout_buffered': v:false,
          \ 'stderr_buffered': v:false,
          \ 'on_stdout': function('s:on_stdout_nvim'),
          \ 'on_stderr': function('s:on_stdout_nvim'),
          \ 'on_exit':   {j, code, e -> s:on_exit(l:buf, code)},
          \ })
  elseif exists('*job_start')
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
" Neovim stdout
" ===========================
function! s:on_stdout_nvim(job_id, data, event) abort
  call s:handle_stdout(a:data)
endfunction

" ===========================
" Vim8 stdout
" ===========================
function! s:on_stdout_vim(channel, msg) abort
  if empty(a:msg) | return | endif
  call s:handle_stdout(split(a:msg, "\n"))
endfunction

" ===========================
" Shared stdout handler
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

    if get(obj, 'output-kind', '') ==# 'status-update'
      call add(s:logs, printf('⏳ %3.0f%% %s', obj['percent-done'] * 100, obj['message']))
    elseif get(obj, 'output-kind', '') ==# 'output-data'
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
  call s:print_results(a:buf)
endfunction

" ===========================
" Print results
" ===========================
function! s:print_results(buf) abort
  if !bufloaded(a:buf)
    return
  endif

  if !empty(s:logs)
    call appendbufline(a:buf, '$', '--- Progress ---')
    call appendbufline(a:buf, '$', s:logs)
  endif

  if empty(s:last_result)
    call appendbufline(a:buf, '$', '❌ Submission ended without result')
    execute 'normal! G'
    return
  endif

  let dat = s:last_result['data']['output-data']
  call appendbufline(a:buf, '$', '--- Results ---')

  let test_cases = get(dat, 'test_cases', [])
  let failed = 0
  let total = len(test_cases)

  if total > 0
    for tc in test_cases
      if get(tc, 'successful', v:false)
        call appendbufline(a:buf, '$', '✅ ' . tc['name'])
      else
        let failed += 1
        call appendbufline(a:buf, '$',
              \ printf('❌ %s:\n%s',
              \ tc['name'],
              \ substitute(get(tc, 'message', ''), '\n', "\n", 'g')))
      endif
    endfor
  endif

  if get(dat, 'all_tests_passed', v:false)
    call appendbufline(a:buf, '$', '✅ All tests passed!')
  else
    call appendbufline(a:buf, '$',
          \ printf('❌ %d tests failed (out of %d)', failed, total))
  endif

  if has_key(dat, 'submission_url')
    call appendbufline(a:buf, '$', '🔗 Submission URL: ' . dat['submission_url'])
  endif

  execute 'normal! G'
endfunction


