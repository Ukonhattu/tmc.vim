
if exists('g:loaded_tmc_spinner')
  finish
endif
let g:loaded_tmc_spinner = 1

" Spinner frames
let s:frames = ['⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏']
let s:index = 0

" Store global spinner state
let s:timer = -1
let s:bufnr = -1
let s:message = ''

" ===========================
" Start spinner in given buffer
" ===========================
function! tmc#spinner#start(buf, message) abort
  let s:bufnr = a:buf
  let s:message = a:message
  let s:index = 0

  if bufloaded(a:buf)
    call setbufline(a:buf, 1, s:frames[0] . ' ' . a:message)
  endif

  if s:timer != -1
    call timer_stop(s:timer)
  endif

  let s:timer = timer_start(100, 'tmc#spinner#tick', {'repeat': -1})
endfunction

" ===========================
" Stop spinner and clear line
" ===========================
function! tmc#spinner#stop() abort
  if exists('s:timer') && s:timer != -1
    let l:t = s:timer
    let s:timer = -1
    call timer_stop(l:t)
  endif

  if s:bufnr != -1 && bufloaded(s:bufnr)
    " Delete spinner line if it exists
    call deletebufline(s:bufnr, 1)
  endif

  let s:bufnr = -1
  let s:message = ''
endfunction


" ===========================
" Internal tick handler
" ===========================
function! tmc#spinner#tick(timer) abort
  " Stop if spinner is no longer active
  if s:timer == -1 || s:bufnr == -1 || !bufloaded(s:bufnr)
    if a:timer != -1
      call timer_stop(a:timer)
    endif
    return
  endif

  let frame = s:frames[s:index]
  let s:index = (s:index + 1) % len(s:frames)
  call setbufline(s:bufnr, 1, frame . ' ' . s:message)
endfunction

