" test/helpers.vim
" Helper functions and mocks for testing

" ===========================
" Test Setup and Teardown
" ===========================

function! test#setup() abort
  " Set up test environment
  let g:tmc_cli_path = 'mock-tmc-cli'
  let g:tmc_client_name = 'test_client'
  let g:tmc_client_version = '0.0.1'
  let g:tmc_organization = 'test-org'
  let $TMC_LANGS_DEFAULT_PROJECTS_DIR = '/tmp/tmc-test-projects'
endfunction

function! test#teardown() abort
  " Clean up test environment
  unlet! g:tmc_cli_path
  unlet! g:tmc_client_name
  unlet! g:tmc_client_version
  unlet! g:tmc_organization
  unlet! g:tmc_selected_course_dir
  unlet! g:tmc_course_name
  unlet! g:tmc_course_id
  unlet! $TMC_LANGS_DEFAULT_PROJECTS_DIR
endfunction

" ===========================
" Mock Functions
" ===========================

" Mock CLI ensure function
function! test#mock_cli_ensure() abort
  return 'mock-tmc-cli'
endfunction

" Create a mock course response
function! test#mock_courses_response() abort
  return {
        \ 'data': {
        \   'output-data': [
        \     {'id': 1, 'name': 'Test Course 1'},
        \     {'id': 2, 'name': 'Test Course 2'}
        \   ]
        \ }
        \ }
endfunction

" Create a mock exercises response
function! test#mock_exercises_response() abort
  return {
        \ 'data': {
        \   'output-data': [
        \     {'id': 101, 'name': 'exercise-1'},
        \     {'id': 102, 'name': 'exercise-2'}
        \   ]
        \ }
        \ }
endfunction

" Create a mock organizations response
function! test#mock_organizations_response() abort
  return {
        \ 'data': {
        \   'output-data-kind': 'organizations',
        \   'output-data': [
        \     {'slug': 'mooc', 'name': 'MOOC'},
        \     {'slug': 'hy', 'name': 'University of Helsinki'}
        \   ]
        \ }
        \ }
endfunction

" ===========================
" Test Assertions
" ===========================

function! test#assert_equal(expected, actual, ...) abort
  let l:msg = get(a:, 1, 'Values should be equal')
  if a:expected != a:actual
    throw printf('AssertionError: %s. Expected: %s, Got: %s', l:msg, string(a:expected), string(a:actual))
  endif
endfunction

function! test#assert_not_equal(expected, actual, ...) abort
  let l:msg = get(a:, 1, 'Values should not be equal')
  if a:expected == a:actual
    throw printf('AssertionError: %s. Both values: %s', l:msg, string(a:expected))
  endif
endfunction

function! test#assert_true(value, ...) abort
  let l:msg = get(a:, 1, 'Value should be true')
  if !a:value
    throw printf('AssertionError: %s. Got: %s', l:msg, string(a:value))
  endif
endfunction

function! test#assert_false(value, ...) abort
  let l:msg = get(a:, 1, 'Value should be false')
  if a:value
    throw printf('AssertionError: %s. Got: %s', l:msg, string(a:value))
  endif
endfunction

function! test#assert_match(pattern, string, ...) abort
  let l:msg = get(a:, 1, 'String should match pattern')
  if a:string !~# a:pattern
    throw printf('AssertionError: %s. Pattern: %s, String: %s', l:msg, a:pattern, a:string)
  endif
endfunction

" ===========================
" Temporary File Helpers
" ===========================

function! test#create_temp_dir() abort
  let l:dir = tempname()
  call mkdir(l:dir, 'p')
  return l:dir
endfunction

function! test#create_mock_exercise_root(root) abort
  " Create a mock exercise structure
  call mkdir(a:root, 'p')
  call writefile([''], a:root . '/.tmcproject.yml')
  return a:root
endfunction

function! test#create_mock_course_config(course_root, exercise_slug, exercise_id) abort
  " Create a mock course_config.toml
  let l:config = [
        \ '[course]',
        \ 'name = "Test Course"',
        \ '',
        \ '[exercises.' . a:exercise_slug . ']',
        \ 'id = ' . a:exercise_id
        \ ]
  call writefile(l:config, a:course_root . '/course_config.toml')
endfunction

