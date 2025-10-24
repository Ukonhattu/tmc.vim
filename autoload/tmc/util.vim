
" autoload/tmc/util.vim
" Common utility functions for messaging and error handling

if exists('g:loaded_tmc_util')
  finish
endif
let g:loaded_tmc_util = 1

" ===========================
" Message Display Functions
" ===========================

" Display error message
function! tmc#util#echo_error(msg) abort
  echohl ErrorMsg
  echom a:msg
  echohl None
endfunction

" Display info message
function! tmc#util#echo_info(msg) abort
  echohl MoreMsg
  echom a:msg
  echohl None
endfunction

" Display success message
function! tmc#util#echo_success(msg) abort
  echohl MoreMsg
  echom a:msg
  echohl None
endfunction

" Display warning message
function! tmc#util#echo_warning(msg) abort
  echohl WarningMsg
  echom a:msg
  echohl None
endfunction

