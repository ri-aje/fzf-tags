scriptencoding utf-8

let s:default_fzf_tags_prompt = ' 🔎 '
let s:fzf_tags_prompt = get(g:, 'fzf_tags_prompt', s:default_fzf_tags_prompt)

let s:default_fzf_layout = { 'window': { 'width': 0.9, 'height': 0.6 } }
let s:fzf_layout = get(g:, 'fzf_layout', s:default_fzf_layout)

let s:actions = {
  \ 'ctrl-t': 'tab split',
  \ 'ctrl-x': 'split',
  \ 'ctrl-v': 'vsplit' }

" caching taglist results.
let s:fzf_tags_cache = {}

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
          \ 'options': '--expect=' . expect_keys . ' --layout=reverse --ansi --no-sort --tiebreak index --prompt "' . s:fzf_tags_prompt . '\"' . identifier . '\" > "',
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
  if get(g:, 'fzf_tags_enable_cache', 0)
    if !has_key(s:fzf_tags_cache, a:identifier)
      let s:fzf_tags_cache[a:identifier] = map(taglist('^' . a:identifier . '$', expand('%:p')),function('s:tag_to_string'))

      function! s:compare_items(x, y)
        if a:x < a:y
          return -1
        endif
        if a:x > a:y
          return 1
        endif
        return 0
      endfunction

      function! s:category(filepath)
        if a:filepath =~? "generated"
          return 1
        endif
        if a:filepath =~? "test"
          return 2
        endif
        return 0
      endfunction

      function! s:compare_lists(x, y)
        " classify filepath into categories and compare category first.
        let xcategory = s:category(a:x[1])
        let ycategory = s:category(a:y[1])
        if xcategory != ycategory
          return xcategory - ycategory
        endif

        let xsize = len(a:x)
        let ysize = len(a:y)

        let index = 1 " ignore first item, which is the somewhat randm index.
        while index < min([xsize,ysize])
          let c = s:compare_items(a:x[index], a:y[index])
          if c != 0
            return c
          endif
          let index += 1
        endwhile

        " all [1:] items are identical, shorter list is smaller.
        return xsize - ysize
      endfunction

      " sort the tag lists. the default order seems just random and confusing.
      call sort(s:fzf_tags_cache[a:identifier], function('s:compare_lists'))

      let tagsize = len(s:fzf_tags_cache[a:identifier])
      let ndigit = 0
      if tagsize < 10
        let ndigit = 1
      elseif tagsize < 100
        let ndigit = 2
      elseif tagsize < 1000
        let ndigit = 3
      elseif tagsize < 10000
        let ndigit = 4
      endif

      function! s:reset_index(index, list) closure " closure to capture ndigit.
        let a:list[0] = printf("%0" . ndigit . "d", a:index+1)
        return a:list
      endfunction

      " reset the tag list indices to align with the sorted ordering. note:
      " 1. lambda won't work here since vim lambda only supports expressions.
      "    it has thee same shortcoming as python lambda.
      " 2. wasn't able to get partial function work here. even if it does, looks
      "    like pretty compliated setup just to pass in ndigit.
      call map(s:fzf_tags_cache[a:identifier], function('s:reset_index'))
    endif
    return map(s:align_lists(deepcopy(s:fzf_tags_cache[a:identifier])), 'join(v:val, " ")')
  else
    let relevant_fields = map(
          \   taglist('^' . a:identifier . '$', expand('%:p')),
          \   function('s:tag_to_string')
          \ )
    return map(s:align_lists(relevant_fields), 'join(v:val, " ")')
  endif
endfunction

function! s:tag_to_string(index, tag_dict)
  let components = [a:index + 1]
  if has_key(a:tag_dict, 'filename')
    " shorten home dir prefix on unix platforms for filenames.
    let filename = a:tag_dict['filename']
    for pattern in ["\\C/data/users/".$USER, "\\C/Users/".$USER, "\\C/home/".$USER]
      if filename =~ pattern
        let filename = substitute(filename,pattern,'~','')
        break
      endif
    endfor
    call add(components, s:black(filename))
  endif

  " for some reason, only one of namespace and class is present.
  " probably because namespace and class decl aren't on the same line?
  if has_key(a:tag_dict, 'namespace')
    call add(components, s:blue(trim(a:tag_dict['namespace'])))
  endif
  if has_key(a:tag_dict, 'class')
    call add(components, s:blue(a:tag_dict['class']))
  endif

  if has_key(a:tag_dict, 'kind')
    let kind = a:tag_dict['kind']
    " struct is class, so is enum, sort of.
    if kind == 's' || kind == 'g'
      let kind = 'c'
    endif
    call add(components, s:purple(repeat(kind,3)))
  endif
  if has_key(a:tag_dict, 'line')
    call add(components, s:red(a:tag_dict['line']))
  endif

  " cmd is basically the source code. remove useless regex control chars.
  if has_key(a:tag_dict, 'cmd')
    let cmd = trim(a:tag_dict['cmd'])
    if get(g:, 'fzf_tags_clean', 0)
      " remove head ^/ symbol.
      if cmd =~ "^\/\^"
        let cmd = cmd[2:]
      endif
      " remove tail $/ symbol.
      if cmd =~ "\$\/$"
        let cmd = cmd[:-3]
      endif
      let cmd = trim(cmd)
      " remove tail open paren/bracket/brace symbols.
      if cmd =~ '[([{][^([{]*$'
        let cmd = substitute(cmd,'[([{][^([{]*$','','')
      endif
      " unescape escaped / symbols.
      if cmd =~ '\\\/'
        let cmd = substitute(cmd,'\\\/','\/','g')
      endif
      let cmd = trim(cmd)
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
