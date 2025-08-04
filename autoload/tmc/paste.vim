if exists('g:loaded_tmc_paste')
  finish
endif
let g:loaded_tmc_paste = 1

let s:last_result = {}
let g:tmc_paste_buf = -1

function! tmc#paste#current() abort
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
      call tmc#core#error('Paste cancelled: no exercise ID provided')
      return
    endif
  endif

  let s:last_result = {}

  " Open scratch buffer
  tabnew
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  file tmc-paste
  setlocal syntax=tmcresult
  let g:tmc_paste_buf = bufnr('%')

  " Spinner
  call tmc#spinner#start(g:tmc_paste_buf, 'Creating paste...')

  let l:cmd = [g:cli_path, 'tmc',
        \ '--client-name', g:client_name,
        \ '--client-version', g:client_version,
        \ 'paste',
        \ '--exercise-id', l:id,
        \ '--submission-path', l:root]

  if exists('*jobstart')
    call jobstart(l:cmd, {
          \ 'pty': v:true,
          \ 'stdout_buffered': v:false,
          \ 'stderr_buffered': v:false,
          \ 'on_stdout': function('s:on_stdout_nvim'),
          \ 'on_stderr': function('s:on_stdout_nvim'),
          \ 'on_exit':   {j, code, e -> s:on_exit(code)},
          \ })
  elseif exists('*job_start')
    call job_start(l:cmd, {
          \ 'out_cb': function('s:on_stdout_vim'),
          \ 'err_cb': function('s:on_stdout_vim'),
          \ 'exit_cb': {ch, code -> s:on_exit(code)},
          \ })
  else
    call s:run_fallback(l:cmd)
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
      if bufloaded(g:tmc_paste_buf)
        call appendbufline(g:tmc_paste_buf, '$', 'ℹ️ ' . line)
        execute 'normal! G'
      endif
      continue
    endtry

    if get(obj, 'output-kind', '') ==# 'status-update'
      if bufloaded(g:tmc_paste_buf)
        call appendbufline(g:tmc_paste_buf, '$',
              \ printf('⏳ %3.0f%% %s', obj['percent-done'] * 100, obj['message']))
        execute 'normal! G'
      endif
      " Store paste URL if present
      if has_key(obj, 'data') && type(obj['data']) == type({})
        if has_key(obj['data'], 'paste_url')
          let s:last_result['paste_url'] = obj['data']['paste_url']
        endif
      endif
    elseif get(obj, 'output-kind', '') ==# 'output-data'
      let s:last_result = obj['data']['output-data']
    endif
  endfor
endfunction

" ===========================
" Exit handler
" ===========================
function! s:on_exit(code) abort
  call tmc#spinner#stop()
  call s:print_results()
endfunction

" ===========================
" Fallback (sync)
" ===========================
function! s:run_fallback(cmd) abort
  let l:objs = tmc#cli#run_streaming(a:cmd)
  for obj in l:objs
    if get(obj, 'output-kind', '') ==# 'output-data'
      let s:last_result = obj['data']['output-data']
    endif
  endfor
  call s:print_results()
endfunction

" ===========================
" Print results
" ===========================
function! s:print_results() abort
  if !bufloaded(g:tmc_paste_buf)
    return
  endif

  call appendbufline(g:tmc_paste_buf, '$', '--- Paste Completed ---')

  if empty(s:last_result)
    call appendbufline(g:tmc_paste_buf, '$', '❌ No paste result found')
  else
    if has_key(s:last_result, 'paste_url')
      call appendbufline(g:tmc_paste_buf, '$', '🔗 Paste URL: ' . s:last_result['paste_url'])
    else
      call appendbufline(g:tmc_paste_buf, '$', '❌ No paste URL in response')
    endif

    if has_key(s:last_result, 'show_submission_url')
      call appendbufline(g:tmc_paste_buf, '$', '🔗 Submission URL: ' . s:last_result['show_submission_url'])
    endif
  endif

  execute 'normal! G'
endfunction
