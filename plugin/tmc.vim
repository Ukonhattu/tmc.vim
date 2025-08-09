
" plugin/tmc.vim
" Entry points for commands and mappings
" Author: Daniel Koch (github: Ukonhattu)

if exists('g:loaded_tmc_plugin')
  finish
endif
let g:loaded_tmc_plugin = 1

" ===========================
" Commands
" ===========================

" Run tests for current exercise
command! TmcRunTests call tmc#run_tests_current()

" Submit current exercise
command! TmcSubmit call tmc#submit_current()

" Download all exercises for a course (requires course ID and org)
command! -nargs=+ TmcDownload call tmc#course_exercises(<f-args>)

" Pick course (organization → course → auto download)
command! TmcPickCourse call tmc#pick_course_command()

" Pick only organization
command! TmcPickOrganization call tmc#pick_organization_command()

" List courses for current organization
command! TmcListCourses call tmc#list_courses()

" List exercises for a course ID
command! -nargs=1 TmcListExercises call tmc#list_exercises(<f-args>)

" Login to TMC
command! -nargs=? TmcLogin call tmc#login(<f-args>)
command! TmcLogout call tmc#logout()
command! TmcStatus call tmc#status()

" Change to course directory

command! TmcCdCourse call tmc#cd_course()

command! TmcPaste call tmc#paste_current()

" Inspect resolved projects directory (for debugging)
command! TmcProjectsDir echo tmc#projects_dir()

" --- Aliases that match README / common naming ---
command! -nargs=0 TmcCourses     call tmc#list_courses()
command! -nargs=1 TmcExercises   call tmc#list_exercises(<f-args>)
command! -nargs=0 TmcPickOrg     call tmc#pick_organization_command()

" ===========================
" Key Mappings (optional)
" ===========================
" Provide <Plug> targets so users can remap cleanly
nnoremap <silent> <Plug>(tmc-run-tests)        :TmcRunTests<CR>
nnoremap <silent> <Plug>(tmc-submit-current)   :TmcSubmit<CR>

" Default leader mappings (can be disabled)
if !get(g:, 'tmc_disable_default_mappings', 0)
  nmap <silent> <leader>tt <Plug>(tmc-run-tests)
  nmap <silent> <leader>ts <Plug>(tmc-submit-current)
endif

