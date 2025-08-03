
" autoload/tmc/download.vim
"
" Handles downloading of course exercises asynchronously with
" pretty-printing, progress logs, and summary.

if exists('g:autoloaded_tmc_download')
  finish
endif
let g:autoloaded_tmc_download = 1

let s:last_result = {}

" ================================
" Public: Download all exercises
" ================================

function! tmc#download#course_exercises(course_id, org, cb) abort
  let l:cli = tmc#cli#ensure()
  if empty(a:course_id)
    call tmc#ui#error('No course ID provided')
    call a:cb('')
    return
  endif

  let l:exercise_ids = tmc#core#get_exercise_ids(a:course_id)
  if empty(l:exercise_ids)
    echom 'No exercises to download for course ' . a:course_id
    call a:cb('')
    return
  endif

  " Initialize logs
  let g:tmc_download_logs = []

  " Open scratch buffer
  tabnew
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  file tmc-download
  setlocal syntax=tmcresult
  let g:tmc_download_buf = bufnr('%')

  " Build CLI command
  let l:args = [l:cli, 'tmc',
        \ '--client-name', g:client_name,
        \ '--client-version', g:client_version,
        \ 'download-or-update-course-exercises']
  for id in l:exercise_ids
    call extend(l:args, ['--exercise-id', id])
  endfor

  " Start spinner
  call tmc#spinner#start(g:tmc_download_buf, 'Downloading exercises...')

  if exists('*jobstart') " Neovim
    call jobstart(l:args, {
          \ 'stdout_buffered': v:false,
          \ 'on_stdout': function('s:Download_on_stdout_nvim'),
          \ 'on_exit':   {j, code, e -> s:Download_on_exit(j, code, e, a:course_id, a:cb)},
          \ 'stderr':    'ignore',
          \ })
  elseif exists('*job_start') " Vim8
    call job_start(l:args, {
          \ 'out_cb': function('s:Download_on_stdout_vim'),
          \ 'exit_cb': {ch, code -> s:Download_on_exit(ch, code, '', a:course_id, a:cb)},
          \ })
  else
    call s:download_fallback(l:args, a:course_id, a:cb)
  endif
endfunction

" ================================
" Output handlers
" ================================

function! s:Download_on_stdout_nvim(job_id, data, event) abort
  for line in a:data
    if empty(line) | continue | endif
    try
      let obj = json_decode(line)
    catch
      continue
    endtry

    if get(obj, 'output-kind', '') ==# 'status-update' && has_key(obj, 'message')
      call add(g:tmc_download_logs, '⏳ ' . obj['message'])
      if exists('g:tmc_download_buf') && bufloaded(g:tmc_download_buf)
        call appendbufline(g:tmc_download_buf, '$', '⏳ ' . obj['message'])
        normal! G
      endif
    elseif get(obj, 'output-kind', '') ==# 'output-data'
      let s:last_result = obj
    endif
  endfor
endfunction

function! s:Download_on_stdout_vim(channel, msg) abort
  call s:Download_on_stdout_nvim(0, split(a:msg, "\n"), '')
endfunction

" ================================
" Exit handlers
" ================================

function! s:Download_on_exit(job_id, code, event, course_id, cb) abort
  call tmc#spinner#stop()
  call s:print_summary(a:course_id)
  call a:cb(a:course_id)
endfunction

function! s:download_fallback(args, course_id, cb) abort
  let l:objs = tmc#cli#run_streaming(a:args)
  for obj in l:objs
    if get(obj, 'output-kind', '') ==# 'output-data'
      let s:last_result = obj
    endif
  endfor
  call s:print_summary(a:course_id)
  call a:cb(a:course_id)
endfunction

" ================================
" Print results summary
" ================================

function! s:print_summary(course_id) abort
  if !exists('g:tmc_download_buf') || !bufloaded(g:tmc_download_buf)
    return
  endif

  let downloaded_count = 0
  let skipped_count = 0
  let failed_count = 0
  let failed_due_to_permission = 0

  call appendbufline(g:tmc_download_buf, '$', '✅ Download completed successfully')

  if !empty(s:last_result)
    let obj = s:last_result
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
    let s:last_result = {}
  endif

  " Summary
  call appendbufline(g:tmc_download_buf, '$', '--- Summary ---')
  call appendbufline(g:tmc_download_buf, '$',
        \ printf('✅ %d downloaded, ⚠️  %d skipped, ❌ %d failed',
        \ downloaded_count, skipped_count, failed_count))

  if failed_due_to_permission > 0
    call appendbufline(g:tmc_download_buf, '$',
          \ '💡 Note: Some failures may be due to exercises requiring you to submit previous ones first.')
  endif

  execute 'normal! G'
endfunction

