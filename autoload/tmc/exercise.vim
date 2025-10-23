
" autoload/tmc/exercise.vim
" Exercise management functions

if exists('g:loaded_tmc_exercise')
  finish
endif
let g:loaded_tmc_exercise = 1

" ===========================
" Exercise Listing
" ===========================

" Lists all exercises for a course
function! tmc#exercise#list(course_id) abort
  if empty(a:course_id)
    call tmc#util#echo_error('Usage: :TmcExercises <course-id>')
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
function! tmc#exercise#get_ids(course_id) abort
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

" Get exercise data as list
function! tmc#exercise#get_list(course_id) abort
  let l:json = tmc#cli#list_exercises(a:course_id)
  let l:exercises = []
  
  if !empty(l:json) && has_key(l:json, 'data')
    let l:data = l:json['data']
    if has_key(l:data, 'output-data') && type(l:data['output-data']) == type([])
      let l:exercises = l:data['output-data']
    elseif has_key(l:data, 'exercises')
      let l:exercises = l:data['exercises']
    endif
  endif
  
  return l:exercises
endfunction

