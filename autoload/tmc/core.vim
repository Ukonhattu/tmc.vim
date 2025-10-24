
if exists('g:loaded_tmc_core')
  finish
endif
let g:loaded_tmc_core = 1

" ===========================
" Backward Compatibility Shims
" All core functionality has been moved to specialized modules:
" - tmc#util for messaging
" - tmc#project for project/exercise management
" - tmc#course for course management
" - tmc#exercise for exercise management
" ===========================

" Message functions - delegate to tmc#util
function! tmc#core#echo_error(msg) abort
  return tmc#util#echo_error(a:msg)
endfunction

function! tmc#core#echo_info(msg) abort
  return tmc#util#echo_info(a:msg)
endfunction

function! tmc#core#echo_success(msg) abort
  return tmc#util#echo_success(a:msg)
endfunction

function! tmc#core#error(msg) abort
  return tmc#util#echo_error(a:msg)
endfunction

" Project functions - delegate to tmc#project
function! tmc#core#cd_course() abort
  return tmc#project#cd_course()
endfunction

function! tmc#core#projects_dir() abort
  return tmc#project#get_dir()
endfunction

function! tmc#core#find_exercise_root() abort
  return tmc#project#find_exercise_root()
endfunction

function! tmc#core#get_exercise_id(root) abort
  return tmc#project#get_exercise_id(a:root)
endfunction

" Course functions - delegate to tmc#course
function! tmc#core#list_courses() abort
  return tmc#course#list()
endfunction

" Exercise functions - delegate to tmc#exercise
function! tmc#core#list_exercises(course_id) abort
  return tmc#exercise#list(a:course_id)
endfunction

function! tmc#core#get_exercise_ids(course_id) abort
  return tmc#exercise#get_ids(a:course_id)
endfunction

