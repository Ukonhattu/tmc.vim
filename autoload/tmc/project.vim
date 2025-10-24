scriptencoding utf-8

" autoload/tmc/project.vim
" Project and exercise root management functions

if exists('g:loaded_tmc_project')
  finish
endif
let g:loaded_tmc_project = 1

" ===========================
" Project Directory Management
" ===========================

" Get the TMC projects directory
function! tmc#project#get_dir() abort
  if exists('$TMC_LANGS_DEFAULT_PROJECTS_DIR') && !empty($TMC_LANGS_DEFAULT_PROJECTS_DIR)
    return fnamemodify(expand($TMC_LANGS_DEFAULT_PROJECTS_DIR), ':p')
  endif

  try
    let l:client = get(g:, 'tmc_client_name', 'tmc_vim')
    let l:val = tmc#cli#settings_get('projects-dir', l:client)
    if empty(l:val)
      " Some builds might use underscore – try list() as fallback
      let l:cfg = tmc#cli#settings_list(l:client)
      if has_key(l:cfg, 'projects_dir')
        let l:val = l:cfg['projects_dir']
      elseif has_key(l:cfg, 'projects-dir')
        let l:val = l:cfg['projects-dir']
      endif
    endif
    if !empty(l:val)
      return fnamemodify(expand(l:val), ':p')
    endif
  catch
  endtry

  call tmc#util#echo_error(
        \ 'Could not determine TMC projects directory. '
        \ . 'Set $TMC_LANGS_DEFAULT_PROJECTS_DIR or run: '
        \ . '!tmc-langs-cli settings move-projects-dir --client-name '
        \ . get(g:, 'tmc_client_name', 'tmc_vim') . ' <path>')
  return ''
endfunction

" Change to course directory
function! tmc#project#cd_course() abort
  let l:root = tmc#project#get_dir()
  if empty(l:root)
    return
  endif

  " If you track current course dir globally, prefer it.
  if exists('g:tmc_selected_course_dir') && !empty(g:tmc_selected_course_dir)
    let l:target = fnamemodify(l:root . '/' . g:tmc_selected_course_dir, ':p')
  else
    " Derive from current buffer: find nearest course_config.toml and cd to its dir
    let l:cfg = findfile('course_config.toml', expand('%:p:h') . ';')
    if empty(l:cfg)
      call tmc#util#echo_error('Not inside a course; open a file within a downloaded exercise first.')
      return
    endif
    let l:target = fnamemodify(fnamemodify(l:cfg, ':h'), ':p')
  endif

  try
    execute 'cd' fnameescape(l:target)
    call tmc#util#echo_info('cd ' . l:target)
  catch
    call tmc#util#echo_error('Failed to cd into ' . l:target)
  endtry
endfunction

" ===========================
" Exercise Root Finding
" ===========================

" Find the root directory of the current exercise by locating .tmcproject.yml
function! tmc#project#find_exercise_root() abort
  let l:buf_path = expand('%:p')
  if empty(l:buf_path)
    return ''
  endif
  let l:dir = isdirectory(l:buf_path) ? l:buf_path : fnamemodify(l:buf_path, ':h')
  while 1
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

" ===========================
" Exercise ID Extraction
" ===========================

" Reads course_config.toml to find exercise ID
" - Supports [exercises.slug], [exercises."slug"], [exercises.'slug']
" - Accepts id = 123, id = "123", id = '123', with any spaces/comments
function! tmc#project#get_exercise_id(root) abort
  let l:slug = fnamemodify(a:root, ':t')

  " Build exact headers and escape for regex (allow leading/trailing ws)
  let l:sec1 = '^\s*' . escape('[exercises.' . l:slug . ']', '\.^$*~[]') . '\s*$'
  let l:sec2 = '^\s*' . escape('[exercises."' . l:slug . '"]', '\.^$*~[]') . '\s*$'
  let l:sec3 = '^\s*' . escape("[exercises.'" . l:slug . "']", '\.^$*~[]') . '\s*$'

  let l:dir = a:root
  while 1
    let l:toml_file = l:dir . '/course_config.toml'
    if filereadable(l:toml_file)
      let l:lines = readfile(l:toml_file)
      for l:idx in range(len(l:lines))
        if l:lines[l:idx] =~# l:sec1 || l:lines[l:idx] =~# l:sec2 || l:lines[l:idx] =~# l:sec3
          let l:i = l:idx + 1
          " scan until next [section]
          while l:i < len(l:lines) && l:lines[l:i] !~# '^\s*\['
            " Simple: find 'id =' then extract first number on the line
            if l:lines[l:i] =~# '^\s*id\s*='
              let l:num = matchstr(l:lines[l:i], '\d\+')
              if !empty(l:num)
                return l:num
              endif
            endif
            let l:i += 1
          endwhile
        endif
      endfor
      break
    endif
    let l:parent = fnamemodify(l:dir, ':h')
    if l:parent ==# l:dir | break | endif
    let l:dir = l:parent
  endwhile
  return ''
endfunction

