
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
  " Ensure course name and organization exist
  if !exists('g:tmc_course_name') || empty(g:tmc_course_name)
    echohl ErrorMsg | echom 'No course selected; pick a course first' | echohl None
    return
  endif
  if !exists('g:tmc_organization') || empty(g:tmc_organization)
    echohl ErrorMsg | echom 'No organisation selected; pick an organisation first' | echohl None
    return
  endif


  " Clean up course name: trim spaces and surrounding quotes
  let l:course_dirname = substitute(g:tmc_course_name, '^\s*["'']\?\|\(["'']\?\s*$\)', '', 'g')



  " Determine base directory
  if exists('$TMC_LANGS_DEFAULT_PROJECTS_DIR') && !empty($TMC_LANGS_DEFAULT_PROJECTS_DIR)
    let l:base = $TMC_LANGS_DEFAULT_PROJECTS_DIR . '/tmc_vim'
  elseif has('win32') || has('win64')
    let l:base = $LOCALAPPDATA . '/tmc/tmc_vim'
  else
    let l:base = expand('~/.local/share/tmc/tmc_vim')
  endif

  let l:path = l:base . '/' . l:course_dirname

  " Change directory
  execute 'cd' fnameescape(l:path)
  echom 'Changed directory to ' . l:path
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

" Reads course_config.toml to find exercise ID
function! tmc#core#get_exercise_id(root) abort
  let l:slug = fnamemodify(a:root, ':t')
  let l:dir = a:root
  while 1
    let l:toml_file = l:dir . '/course_config.toml'
    if filereadable(l:toml_file)
      let l:lines = readfile(l:toml_file)
      let l:section = '[exercises.' . l:slug . ']'
      for l:idx in range(len(l:lines))
        if l:lines[l:idx] =~# '^\s*' . escape(l:section, '[]') . '\s*$'
          let l:i = l:idx + 1
          while l:i < len(l:lines) && l:lines[l:i] !~# '^\s*\['
            if l:lines[l:i] =~# '^\s*id\s*=\s*\d\+'
              return matchstr(l:lines[l:i], '\d\+')
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

" ===========================
" Course/Exercise Listing
" ===========================

" Lists all courses for the current organization
function! tmc#core#list_courses() abort
  let l:org = get(g:, 'tmc_organization', 'mooc')
  let l:json = tmc#cli#run(['get-courses', '--organization', l:org])
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
  let l:json = tmc#cli#run(['get-course-exercises', '--course-id', a:course_id])
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
  let l:json = tmc#cli#run(['get-course-exercises', '--course-id', a:course_id])
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

