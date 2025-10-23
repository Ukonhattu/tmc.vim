
" autoload/tmc/course.vim
" Course management functions

if exists('g:loaded_tmc_course')
  finish
endif
let g:loaded_tmc_course = 1

" ===========================
" Course Listing
" ===========================

" Lists all courses for the current organization
function! tmc#course#list() abort
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

" Get course data as list
function! tmc#course#get_list(org) abort
  let l:json = tmc#cli#list_courses(a:org)
  let l:courses = []
  
  if !empty(l:json) && has_key(l:json, 'data')
    let l:data = l:json['data']
    if has_key(l:data, 'output-data') && type(l:data['output-data']) == type([])
      let l:courses = l:data['output-data']
    elseif has_key(l:data, 'courses')
      let l:courses = l:data['courses']
    endif
  endif
  
  return l:courses
endfunction

