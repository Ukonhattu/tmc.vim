" Prevent loading twice
if exists('g:loaded_tmc_plugin')
  finish
endif
let g:loaded_tmc_plugin = 1

" User commands for interacting with the TMC server via tmc‑langs‑cli.
"  - TmcLogin [email]         : login to the TMC server. Prompts for password.
"  - TmcCourses              : list available courses for the default organisation (mooc).
"  - TmcExercises <courseId> : list exercises for a course.
"  - TmcDownload <ids...>    : download or update one or more exercises by ID.
"  - TmcSubmit <id> <path>   : submit the exercise at path with the given ID.

command! -nargs=? TmcLogin     call tmc#login(<f-args>)
command! -nargs=0 TmcCourses   call tmc#list_courses()
command! -nargs=1 TmcExercises call tmc#list_exercises(<f-args>)
command! -nargs=+ TmcDownload  call tmc#download(<f-args>)
command! -nargs=+ TmcSubmit    call tmc#submit(<f-args>)

" Allow the user to change the organisation slug used for listing courses.
" Example: :TmcSetOrg hy
command! -nargs=1 TmcSetOrg call tmc#set_organization(<f-args>)

" Run tests for the exercise containing the current buffer.  This will open a
" new tab with the test output.  See tmc#run_tests_current for details.
command! -nargs=0 TmcRunTests call tmc#run_tests_current()

" Submit the exercise containing the current buffer.  Reads the exercise id
" from course_config.toml if available; prompts otherwise.  See tmc#submit_current.
command! -nargs=0 TmcSubmitCurrent call tmc#submit_current()

" Interactive picker for organisation and course.  Opens popup menus to
" choose an organisation and then a course.  After selection, lists the
" exercises for that course.  See tmc#pick_course_command for details.
command! -nargs=0 TmcPickCourse call tmc#pick_course_command()

" Allow the user to change the organisation separately from course selection.
command! -nargs=0 TmcPickOrg call tmc#pick_organization_command()

" Change Vim's current working directory to the directory of the last
" downloaded course.  The path is computed on demand from the selected
" organisation and course name when executing the command.
command! -nargs=0 TmcCdCourse call tmc#cd_course()

" Generic command: forward arbitrary CLI commands to tmc-langs-cli.  The
" provided arguments will be passed to the CLI after the 'tmc' subcommand
" (added internally).  Example: :Tmc get-exercise-details --exercise-id 1234
" will invoke `tmc-langs-cli tmc get-exercise-details --exercise-id 1234`.
" If no arguments are provided, the command prints usage information.
command! -nargs=* Tmc call tmc#run_generic(<f-args>)

" Provide default key mappings for running tests and submitting.  Users can
" set g:tmc_disable_default_mappings to disable these.
if !exists('g:tmc_disable_default_mappings')
  nnoremap <silent> <leader>tt :TmcRunTests<CR>
  nnoremap <silent> <leader>ts :TmcSubmitCurrent<CR>
endif