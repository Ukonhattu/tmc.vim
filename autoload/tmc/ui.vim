scriptencoding utf-8

" autoload/tmc/ui.vim
"
" Handles UI elements: async selection popups and error messaging.
" Uses autoload/tmc/spinner.vim directly for spinner functionality.

if exists('g:autoloaded_tmc_ui')
  finish
endif
let g:autoloaded_tmc_ui = 1

" ----------------------------------------
" Error display
" ----------------------------------------

function! tmc#ui#error(msg) abort
  return tmc#util#echo_error(a:msg)
endfunction

" ----------------------------------------
" Async UI selector
" ----------------------------------------

let s:ui_callbacks = {}
let s:ui_cb_next_id = 1

function! tmc#ui#call_callback(id, value) abort
  if has_key(s:ui_callbacks, a:id)
    call call(s:ui_callbacks[a:id], [a:value])
    unlet s:ui_callbacks[a:id]
  endif
endfunction

function! tmc#ui#select(items, prompt, cb) abort
  let l:list = copy(a:items)
  for i in range(len(l:list))
    let l:list[i] = '' . l:list[i]
  endfor

  let l:cb_id = s:ui_cb_next_id
  let s:ui_callbacks[l:cb_id] = a:cb
  let s:ui_cb_next_id += 1

  if has('nvim') && exists(':Telescope')
    let g:TMC_UI_CB_ID = l:cb_id
    let g:tmc_ui_select_items = l:list
    let g:tmc_ui_select_prompt = a:prompt
lua << EOF
      local pickers = require('telescope.pickers')
      local finders = require('telescope.finders')
      local conf    = require('telescope.config').values
      local actions = require('telescope.actions')
      local action_state = require('telescope.actions.state')

      pickers.new({}, {
        prompt_title = vim.g.tmc_ui_select_prompt,
        finder = finders.new_table { results = vim.g.tmc_ui_select_items },
        sorter = conf.generic_sorter({}),
        attach_mappings = function(_, map)
          actions.select_default:replace(function(bufnr)
            local entry = action_state.get_selected_entry()
            vim.schedule(function()
              vim.fn['tmc#ui#call_callback'](vim.g.TMC_UI_CB_ID, entry and entry[1] or '')
            end)
            actions.close(bufnr)
          end)
          return true
        end,
      }):find()
EOF
    unlet g:tmc_ui_select_items
    unlet g:tmc_ui_select_prompt
    return v:null

  elseif has('nvim') && exists('*luaeval')
    let g:TMC_UI_CB_ID = l:cb_id
    let g:tmc_ui_select_items = l:list
    let g:tmc_ui_select_prompt = a:prompt
lua << EOF
      if vim.ui and type(vim.ui.select) == 'function' then
        vim.ui.select(vim.g.tmc_ui_select_items, { prompt = vim.g.tmc_ui_select_prompt }, function(choice)
          vim.schedule(function()
            vim.fn['tmc#ui#call_callback'](vim.g.TMC_UI_CB_ID, choice or '')
          end)
        end)
      end
EOF
    unlet g:tmc_ui_select_items
    unlet g:tmc_ui_select_prompt
    return v:null

  elseif exists('*fzf#run')
    call fzf#run({
          \ 'source': l:list,
          \ 'sink*': { lines -> call('tmc#ui#call_callback', [l:cb_id, get(lines, 0, '')]) },
          \ 'options': ['--prompt=' . a:prompt . '> '],
          \ })
    return v:null

  else
    let l:choice = ''
    if exists('*popup_menu')
      let l:idx = popup_menu(l:list, {'title': a:prompt})
      if l:idx >= 1 && l:idx <= len(l:list)
        let l:choice = l:list[l:idx - 1]
      endif
    else
      let l:choices = [a:prompt]
      for i in range(len(l:list))
        call add(l:choices, printf('%d. %s', i+1, l:list[i]))
      endfor
      let l:res = inputlist(l:choices)
      if l:res >= 1 && l:res <= len(l:list)
        let l:choice = l:list[l:res - 1]
      endif
    endif
    call call('tmc#ui#call_callback', [l:cb_id, l:choice])
    return v:null
  endif
endfunction

" ----------------------------------------
" Course / Organization picking
" ----------------------------------------

function! tmc#ui#pick_organization(cb) abort
  let l:json = tmc#cli#get_organizations()
  if empty(l:json)
    call a:cb('')
    return
  endif

  let l:orgs = []
  if has_key(l:json, 'data')
    if has_key(l:json['data'], 'output-data-kind') && l:json['data']['output-data-kind'] ==# 'organizations' && has_key(l:json['data'], 'output-data')
      for org in l:json['data']['output-data']
        if has_key(org, 'slug') && has_key(org, 'name')
          call add(l:orgs, printf('%s (%s)', org['slug'], org['name']))
        elseif has_key(org, 'slug')
          call add(l:orgs, org['slug'])
        endif
      endfor
    endif
  endif

  if empty(l:orgs)
    call tmc#ui#error('No organizations found')
    call a:cb('')
    return
  endif

  call tmc#ui#select(l:orgs, 'Select organization:', {choice ->
        \ (empty(choice)
        \   ? call(a:cb, [''])
        \   : call(a:cb, [split(choice)[0]]))})
endfunction

function! tmc#ui#pick_course(org, cb) abort
  if empty(a:org)
    call a:cb('')
    return
  endif

  let l:json = tmc#cli#list_courses(a:org)
  if empty(l:json)
    call a:cb('')
    return
  endif

  let l:courses = []
  if has_key(l:json, 'data')
    let l:data = l:json['data']
    let l:list = []
    if has_key(l:data, 'output-data-kind') && l:data['output-data-kind'] ==# 'courses' && has_key(l:data, 'output-data')
      let l:list = l:data['output-data']
    elseif has_key(l:data, 'courses')
      let l:list = l:data['courses']
    endif
    for c in l:list
      if has_key(c, 'id') && has_key(c, 'name')
        call add(l:courses, printf('%s: %s', c['id'], c['name']))
      endif
    endfor
  endif

  if empty(l:courses)
    call tmc#ui#error('No courses found for organization ' . a:org)
    call a:cb('')
    return
  endif

  call tmc#ui#select(l:courses, 'Select course:', {choice ->
        \ (empty(choice)
        \   ? call(a:cb, [''])
        \   : (function('tmc#ui#parse_course_choice'))(choice, a:cb))})
endfunction


function! tmc#ui#parse_course_choice(choice, cb) abort
  let l:parts = split(a:choice, ':', 2)
  let l:cid = ''
  let l:cname = ''

  " Extract ID and strip unwanted characters like quotes and leading apostrophes
  if len(l:parts) >= 1
    let l:cid = substitute(trim(l:parts[0]), "['\"`]", '', 'g')
  endif

  if len(l:parts) >= 2
    let l:cname = trim(l:parts[1])
  endif

  if !empty(l:cname)
    let g:tmc_course_name = l:cname
  endif

  let g:tmc_course_id = l:cid
  call a:cb(l:cid)
endfunction


function! tmc#ui#pick_course_command() abort
  if !exists('g:tmc_organization') || empty(g:tmc_organization)
    call tmc#ui#pick_organization({org ->
          \ (empty(org)
          \   ? ''
          \   : tmc#ui#handle_org_selection(org))})
  else
    call tmc#ui#pick_course(g:tmc_organization, {course_id -> tmc#ui#after_pick_course_async(g:tmc_organization, course_id)})
  endif
endfunction



function! tmc#ui#handle_org_selection(org) abort
  let l:org = trim(a:org)
  let g:tmc_organization = l:org
  call tmc#ui#pick_course(l:org, {course_id -> tmc#ui#after_pick_course_async(l:org, course_id)})
endfunction




function! tmc#ui#after_pick_course_async(org, course_id) abort
  if empty(a:course_id)
    return
  endif

  echom 'Selected organization: ' . a:org
  echom 'Selected course: ' . a:course_id

  " NEW: remember which course directory we’re targeting right away
  if exists('g:tmc_course_name') && !empty(g:tmc_course_name)
    let g:tmc_selected_course_dir = g:tmc_course_name
  endif

  call tmc#download#course_exercises(a:course_id, a:org, {cid ->
        \ (empty(cid)
        \   ? ''
        \   : tmc#ui#after_download_async(a:org, cid))})
endfunction



function! tmc#ui#after_download_async(org, course_id) abort
  " No delay; we already know the course dir
  if exists('g:tmc_selected_course_dir') && !empty(g:tmc_selected_course_dir)
    call tmc#project#cd_course()
  endif
  call tmc#exercise#list(a:course_id)
endfunction


function! tmc#ui#pick_organization_command() abort
  call tmc#ui#pick_organization({org ->
        \ execute(empty(org)
        \   ? ''
        \   : 'let g:tmc_organization = "' . org . '" | echom "Selected organization: ' . org . '"')})
endfunction

