" autoload/tmc/auth.vim
"
" Handles authentication (login, logout, session status check) with TMC server.

if exists('g:autoloaded_tmc_auth')
  finish
endif
let g:autoloaded_tmc_auth = 1

" Login to the TMC server.  Optionally accepts an email address; if omitted
" the user is prompted.  Password is always prompted via inputsecret().
function! tmc#auth#login(...) abort
  " Prompt for email and password.  Email may be provided as a command
  " argument; password is always prompted via inputsecret().
  let l:email = ''
  if a:0 >= 1
    let l:email = a:1
  else
    let l:email = input('TMC email: ')
  endif
  let l:password = inputsecret('Password: ')
  " Build the login command manually so we can pass the password via stdin.
  " Ensure CLI is available and client flags are included.  Use the 'tmc'
  " subcommand and do not call tmc#run_cli() because that uses system()
  " without input redirection.
  let l:cli_path = tmc#cli#ensure()
  let l:cmd_list = [l:cli_path, 'tmc', '--client-name', g:tmc_client_name, '--client-version', g:tmc_client_version,
        \ 'login', '--email', l:email, '--stdin']
  let l:cmd = join(l:cmd_list, ' ')
  " Pass the password via stdin with a trailing newline so the CLI reads it.
  let l:out = system(l:cmd, l:password . "\n")
  if v:shell_error
    call tmc#core#echo_error('tmc-langs-cli login failed: ' . l:out)
    return
  endif
  try
    let l:json = json_decode(l:out)
  catch
    echom 'Login response: ' . l:out
    return
  endtry
  if has_key(l:json, 'status') && has_key(l:json, 'message')
    echom l:json['status'] . ': ' . l:json['message']
  else
    echom 'Login command executed'
  endif
endfunction


function! tmc#auth#logout() abort
  call tmc#cli#ensure()

  let l:cmd = [
        \ g:tmc_cli_path,
        \ 'tmc',
        \ '--client-name', g:tmc_client_name,
        \ '--client-version', g:tmc_client_version,
        \ 'logout'
        \ ]

  let l:out = system(join(l:cmd, ' '))

  if v:shell_error
    call tmc#ui#error('Logout failed: ' . l:out)
    return
  endif

  try
    let l:json = json_decode(l:out)
  catch
    echom 'Logout response: ' . l:out
    return
  endtry

  if has_key(l:json, 'status') && has_key(l:json, 'message')
    echom l:json['status'] . ': ' . l:json['message']
  else
    echom 'Logged out successfully'
  endif
endfunction

function! tmc#auth#status() abort
  call tmc#cli#ensure()

  let l:cmd = [
        \ g:tmc_cli_path,
        \ 'tmc',
        \ '--client-name', g:tmc_client_name,
        \ '--client-version', g:tmc_client_version,
        \ 'logged-in'
        \ ]

  let l:out = system(join(l:cmd, ' '))

  if v:shell_error
    echom 'Not logged in'
    return
  endif

  try
    let l:json = json_decode(l:out)
  catch
    echom 'Session response: ' . l:out
    return
  endtry

  if has_key(l:json, 'status') && l:json['status'] ==# 'success'
    echom 'You are logged in'
  else
    echom 'Not logged in'
  endif
endfunction
