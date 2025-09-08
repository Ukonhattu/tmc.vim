
if exists('g:loaded_tmc_core')
  finish
endif
let g:loaded_tmc_core = 1

" ===========================
" Core Shared Helper Functions
" ===========================

" Displays errors consistently
function! tmc#core#echo_error(msg) abort
  echohl ErrorMsg
  echom a:msg
  echohl None
endfunction

" ===========================
" Exercise and Course Helpers
" ===========================




function! tmc#core#cd_course() abort
  let l:root = tmc#core#projects_dir()
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
      call tmc#core#echo_error('Not inside a course; open a file within a downloaded exercise first.')
      return
    endif
    let l:target = fnamemodify(fnamemodify(l:cfg, ':h'), ':p')
  endif

  try
    execute 'cd' fnameescape(l:target)
    call tmc#core#echo_info('cd ' . l:target)
  catch
    call tmc#core#echo_error('Failed to cd into ' . l:target)
  endtry
endfunction

function! tmc#core#projects_dir() abort
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

  call tmc#core#echo_error(
        \ 'Could not determine TMC projects directory. '
        \ . 'Set $TMC_LANGS_DEFAULT_PROJECTS_DIR or run: '
        \ . '!tmc-langs-cli settings move-projects-dir --client-name '
        \ . get(g:, 'tmc_client_name', 'tmc_vim') . ' <path>')
  return ''
endfunction

" Find the root directory of the current exercise by locating .tmcproject.yml
function! tmc#core#find_exercise_root() abort
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
" Course/Exercise Listing
" ===========================


" Reads course_config.toml to find exercise ID
" - Supports [exercises.slug], [exercises."slug"], [exercises.'slug']
" - Accepts id = 123, id = "123", id = '123' (with spaces, trailing comments ok)
function! tmc#core#get_exercise_id(root) abort
  let l:slug = fnamemodify(a:root, ':t')

  " Prebuild the three possible headers
  let l:sec1 = '[exercises.' . l:slug . ']'
  let l:sec2 = '[exercises."' . l:slug . '"]'
  let l:sec3 = "[exercises.'" . l:slug . "']"

  " Prebuild safe regexes for those headers (allow leading/trailing whitespace)
  let l:hdr1 = '^\s*' . escape(l:sec1, '\.^$*~[]') . '\s*$'
  let l:hdr2 = '^\s*' . escape(l:sec2, '\.^$*~[]') . '\s*$'
  let l:hdr3 = '^\s*' . escape(l:sec3, '\.^$*~[]') . '\s*$'

  let l:dir = a:root
  while 1
    let l:toml_file = l:dir . '/course_config.toml'
    if filereadable(l:toml_file)
      let l:lines = readfile(l:toml_file)
      for l:idx in range(len(l:lines))
        if l:lines[l:idx] =~# l:hdr1 || l:lines[l:idx] =~# l:hdr2 || l:lines[l:idx] =~# l:hdr3
          let l:i = l:idx + 1
          " scan until next [section]
          while l:i < len(l:lines) && l:lines[l:i] !~# '^\s*\['
            " Accept: id = 123 | id = "123" | id = '123' (any spaces, allow trailing comments)
            if l:lines[l:i] =~# '\v^\s*id\s*=\s*[''"]?\s*\d+'
              return matchstr(l:lines[l:i], '\v\zs\d+\ze')
            endif
            let l:i += 1
          endwhile
        endif
      endfor
      break
    endif
    let l:parent = fnamemodify(l:dir, ':h')
    if l:parent ==# l:dir
      break
    endif
    let l:dir = l:parent
  endwhile
  return ''
endfunction

" Lists all courses for the current organization
function! tmc#core#list_courses() abort
  let l:org = get(g:, 'tmc_organization', 'mooc')
  let l:json = tmc#cli#list_courses(l:org)
  if empty(l:json)
    return
  endif

  if has_key(l:json, 'data')
    let l:data = l:json['data']
    let l:courses = []
    if has_key(l:data, 'output-data') && type(l:data['output-data']) == type([])
      let l:courses = l:data['output-data']
    elseif has_key(l:data, 'courses')
      let l:courses = l:data['courses']
    endif
    for course in l:courses
      if has_key(course, 'id') && has_key(course, 'name')
        echom printf('%s: %s', course['id'], course['name'])
      endif
    endfor
  endif
endfunction

" Lists all exercises for a course
function! tmc#core#list_exercises(course_id) abort
  if empty(a:course_id)
    call tmc#core#echo_error('Usage: :TmcExercises <course-id>')
    return
  endif
  let l:json = tmc#cli#list_exercises(a:course_id)
  if empty(l:json)
    return
  endif

  if has_key(l:json, 'data')
    let l:data = l:json['data']
    let l:ex_list = []
    if has_key(l:data, 'output-data') && type(l:data['output-data']) == type([])
      let l:ex_list = l:data['output-data']
    elseif has_key(l:data, 'exercises')
      let l:ex_list = l:data['exercises']
    endif
    for ex in l:ex_list
      if has_key(ex, 'id') && has_key(ex, 'name')
        echom printf('%s: %s', ex['id'], ex['name'])
      endif
    endfor
  endif
endfunction

" Collects all exercise IDs for a course
function! tmc#core#get_exercise_ids(course_id) abort
  let l:json = tmc#cli#list_exercises(a:course_id)
  let l:ids = []
  if !empty(l:json) && has_key(l:json, 'data')
    let l:data = l:json['data']
    let l:list = []
    if has_key(l:data, 'output-data') && type(l:data['output-data']) == type([])
      let l:list = l:data['output-data']
    elseif has_key(l:data, 'exercises')
      let l:list = l:data['exercises']
    endif
    for ex in l:list
      if has_key(ex, 'id')
        call add(l:ids, string(ex['id']))
      endif
    endfor
  endif
  return l:ids
endfunction

