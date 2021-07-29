scriptencoding utf-8

let s:default_fzf_tags_prompt = ' 🔎 '
let s:fzf_tags_prompt = get(g:, 'fzf_tags_prompt', s:default_fzf_tags_prompt)

let s:default_fzf_layout = { 'window': { 'width': 0.9, 'height': 0.6 } }
let s:fzf_layout = get(g:, 'fzf_layout', s:default_fzf_layout)

let s:actions = {
  \ 'ctrl-t': 'tab split',
  \ 'ctrl-x': 'split',
  \ 'ctrl-v': 'vsplit' }

function! fzf_tags#SelectCommand(identifier)
  let identifier = empty(a:identifier) ? s:tagstack_head() : a:identifier
  if empty(identifier)
    echohl Error
    echo "Tag stack empty"
    echohl None
  else
    call fzf_tags#Find(identifier)
  endif
endfunction

function! fzf_tags#FindCommand(identifier)
  return fzf_tags#Find(empty(a:identifier) ? expand('<cword>') : a:identifier)
endfunction

function! fzf_tags#Find(identifier)
  let identifier = s:strip_leading_bangs(a:identifier)
  let source_lines = s:source_lines(identifier)

  if len(source_lines) == 0
    echohl WarningMsg
    echo 'Tag not found: ' . identifier
    echohl None
  elseif len(source_lines) == 1
    execute 'tag' identifier
  else
    let expect_keys = join(keys(s:actions), ',')
    let run_spec = {
          \ 'source': source_lines,
          \ 'sink*': function('s:sink', [identifier]),
          \ 'options': '--expect=' . expect_keys . ' --ansi --no-sort --tiebreak index --prompt "' . s:fzf_tags_prompt . '\"' . identifier . '\" > "',
          \ }
    let final_run_spec = extend(run_spec, s:fzf_layout)
    call fzf#run(final_run_spec)
  endif
endfunction

function! s:tagstack_head()
  let stack = gettagstack()
  return stack.length != 0 ? stack.items[-1].tagname : ""
endfunction

function! s:strip_leading_bangs(identifier)
  if (a:identifier[0] !=# '!')
    return a:identifier
  else
    return s:strip_leading_bangs(a:identifier[1:])
  endif
endfunction

function! s:source_lines(identifier)
  let relevant_fields = map(
  \   taglist('^' . a:identifier . '$', expand('%:p')),
  \   function('s:tag_to_string')
  \ )
  return map(s:align_lists(relevant_fields), 'join(v:val, " ")')
endfunction

function! s:tag_to_string(index, tag_dict)
  let components = [a:index + 1]
  if has_key(a:tag_dict, 'filename')
    call add(components, s:black(a:tag_dict['filename']))
  endif

  " for some reason, only one of namespace and class is present.
  " probably because namespace and class decl aren't on the same line?
  if has_key(a:tag_dict, 'namespace')
    call add(components, s:blue(trim(a:tag_dict['namespace'])))
  endif
  if has_key(a:tag_dict, 'class')
    call add(components, s:blue(a:tag_dict['class']))
  endif

  if has_key(a:tag_dict, 'line')
    call add(components, s:red(a:tag_dict['line']))
  endif
  if has_key(a:tag_dict, 'kind')
    let kind = a:tag_dict['kind']
    " struct is class, so is enum, sort of.
    if kind == 's' || kind == 'g'
      let kind = 'c'
    endif
    call add(components, s:purple(repeat(kind,2)))
  endif

  " cmd is basically the source code. remove useless regex control chars.
  if has_key(a:tag_dict, 'cmd')
    let cmd = trim(a:tag_dict['cmd'])
    " remove head ^/ symbol.
    if cmd =~ "^\/\^"
      let cmd = cmd[2:]
    endif
    " remove tail $/ symbol.
    if cmd =~ "\$\/$"
      let cmd = cmd[:-3]
    endif
    let cmd = trim(cmd)
    " remove tail open paren/brace/bracket symbol.
    if cmd =~ "[([{]$"
      let cmd = trim(cmd[:-1])
    endif
    call add(components, s:red(cmd))
  endif

  " signature gives the function params, useful for overload resolution.
  if has_key(a:tag_dict, 'signature')
    call add(components, s:purple(trim(a:tag_dict['signature'])))
  endif
  return components
endfunction

function! s:align_lists(lists)
  if !get(g:, 'fzf_tags_align', 0)
    return a:lists
  endif
  let maxes = {}
  for list in a:lists
    let i = 0
    while i < len(list)
      let maxes[i] = max([get(maxes, i, 0), len(list[i])])
      let i += 1
    endwhile
  endfor
  for list in a:lists
    call map(list, "printf('%-'.maxes[v:key].'s', v:val)")
  endfor
  return a:lists
endfunction

function! s:sink(identifier, selection)
  let selected_with_key = a:selection[0]
  let selected_text = a:selection[1]

  " Open new split or tab.
  if has_key(s:actions, selected_with_key)
    execute 'silent' s:actions[selected_with_key]
  endif

  " Go to tag!
  let l:count = split(selected_text)[0]
  execute l:count . 'tag' a:identifier
endfunction

" colors found on https://gist.github.com/vratiu/9780109
function! s:black(s)
  return "\033[30m" . a:s . "\033[m"
endfunction
function! s:red(s)
  return "\033[31m" . a:s . "\033[m"
endfunction
function! s:green(s)
  return "\033[32m" . a:s . "\033[m"
endfunction
function! s:blue(s)
  return "\033[34m" . a:s . "\033[m"
endfunction
function! s:purple(s)
  return "\033[35m" . a:s . "\033[m"
endfunction
