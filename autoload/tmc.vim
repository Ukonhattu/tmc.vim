scriptencoding utf-8

if exists('g:loaded_tmc')
  finish
endif
let g:loaded_tmc = 1

" ========================================
" Backward compatibility wrappers
" ========================================

" CLI
function! tmc#ensure_cli() abort
  return tmc#cli#ensure()
endfunction

function! tmc#run_cli(args) abort
  return tmc#cli#run(a:args)
endfunction

function! tmc#run_cli_streaming(args) abort
  return tmc#cli#run_streaming(a:args)
endfunction

" Courses
function! tmc#list_courses() abort
  return tmc#course#list()
endfunction

function! tmc#list_exercises(course_id) abort
  return tmc#exercise#list(a:course_id)
endfunction

function! tmc#cd_course() abort
  return tmc#project#cd_course()
endfunction

" Auth
function! tmc#login(...) abort
  return call('tmc#auth#login', a:000)
endfunction

function! tmc#logout() abort
  return tmc#auth#logout()
endfunction

function! tmc#status() abort
  return tmc#auth#status()
endfunction

" Submit
function! tmc#submit_current() abort
  return tmc#submit#current()
endfunction

" Tests
function! tmc#run_tests_current() abort
  return tmc#run_tests#current()
endfunction

" Download
function! tmc#download_course_exercises(course_id, org, cb) abort
  return tmc#download#course_exercises(a:course_id, a:org, a:cb)
endfunction

" Pick
function! tmc#pick_course_command() abort
  return tmc#ui#pick_course_command()
endfunction

function! tmc#pick_organization_command() abort
  return tmc#ui#pick_organization_command()
endfunction

function! tmc#paste_current() abort
  return tmc#paste#current()
endfunction

function! tmc#projects_dir() abort
  return tmc#project#get_dir()
endfunction
