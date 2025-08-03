
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

" Change to course directory

command! TmcCdCourse call tmc#cd_course()


" ===========================
" Key Mappings (optional)
" ===========================
" Uncomment or adjust as needed
nnoremap <leader>tt :TmcRunTests<CR>
nnoremap <leader>ts :TmcSubmit<CR>
nnoremap <leader>td :TmcDownload<CR>

