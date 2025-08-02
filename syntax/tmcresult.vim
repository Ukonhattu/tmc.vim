
" Syntax highlighting for TMC test results

if exists("b:current_syntax")
  finish
endif

syntax match TmcPass /^✅.*$/
syntax match TmcFail /^❌.*$/
syntax match TmcHeader /^--- .* ---$/
syntax match TmcLog /^\s\+\(Stdout\|Stderr\):/

highlight def link TmcPass   DiffAdded
highlight def link TmcFail   DiffRemoved
highlight def link TmcHeader Title
highlight def link TmcLog    Comment

let b:current_syntax = "tmcresult"
