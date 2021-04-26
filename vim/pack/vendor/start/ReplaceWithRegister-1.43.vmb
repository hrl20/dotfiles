" Vimball Archiver by Charles E. Campbell
UseVimball
finish
autoload/ReplaceWithRegister.vim	[[[1
185
" ReplaceWithRegister.vim: Replace text with the contents of a register.
"
" DEPENDENCIES:
"   - repeat.vim (vimscript #2136) plugin (optional)
"   - visualrepeat.vim (vimscript #3848) plugin (optional)
"
" Copyright: (C) 2011-2019 Ingo Karkat
"   The VIM LICENSE applies to this script; see ':help copyright'.
"
" Maintainer:	Ingo Karkat <ingo@karkat.de>

function! ReplaceWithRegister#SetRegister()
    let s:register = v:register
endfunction
function! ReplaceWithRegister#SetCount()
    let s:count = v:count
endfunction
function! ReplaceWithRegister#IsExprReg()
    return (s:register ==# '=')
endfunction

" Note: Could use ingo#pos#IsOnOrAfter(), but avoid dependency to ingo-library
" for now.
function! s:IsAfter( posA, posB )
    return (a:posA[1] > a:posB[1] || a:posA[1] == a:posB[1] && a:posA[2] > a:posB[2])
endfunction
function! s:CorrectForRegtype( type, register, regType, pasteText )
    if a:type ==# 'visual' && visualmode() ==# "\<C-v>" || a:type[0] ==# "\<C-v>"
	" Adaptations for blockwise replace.
	let l:pasteLnum = len(split(a:pasteText, "\n"))
	if a:regType ==# 'v' || a:regType ==# 'V' && l:pasteLnum == 1
	    " If the register contains just a single line, temporarily duplicate
	    " the line to match the height of the blockwise selection.
	    let l:height = line("'>") - line("'<") + 1
	    if l:height > 1
		call setreg(a:register, join(repeat(split(a:pasteText, "\n"), l:height), "\n"), "\<C-v>")
		return 1
	    endif
	elseif a:regType ==# 'V' && l:pasteLnum > 1
	    " If the register contains multiple lines, paste as blockwise.
	    call setreg(a:register, '', "a\<C-v>")
	    return 1
	endif
    elseif a:regType ==# 'V' && a:pasteText =~# '\n$'
	" Our custom operator is characterwise, even in the
	" ReplaceWithRegisterLine variant, in order to be able to replace less
	" than entire lines (i.e. characterwise yanks).
	" So there's a mismatch when the replacement text is a linewise yank,
	" and the replacement would put an additional newline to the end.
	" To fix that, we temporarily remove the trailing newline character from
	" the register contents and set the register type to characterwise yank.
	call setreg(a:register, strpart(a:pasteText, 0, len(a:pasteText) - 1), 'v')

	return 1
    endif

    return 0
endfunction
function! s:ReplaceWithRegister( type )
    " With a put in visual mode, the selected text will be replaced with the
    " contents of the register. This works better than first deleting the
    " selection into the black-hole register and then doing the insert; as
    " "d" + "i/a" has issues at the end-of-the line (especially with blockwise
    " selections, where "v_o" can put the cursor at either end), and the "c"
    " commands has issues with multiple insertion on blockwise selection and
    " autoindenting.
    " With a put in visual mode, the previously selected text is put in the
    " unnamed register, so we need to save and restore that.
    let l:save_clipboard = &clipboard
    set clipboard= " Avoid clobbering the selection and clipboard registers.
    let l:save_reg = getreg('"')
    let l:save_regmode = getregtype('"')

    " Note: Must not use ""p; this somehow replaces the selection with itself?!
    let l:pasteRegister = (s:register ==# '"' ? '' : '"' . s:register)
    if s:register ==# '='
	" Cannot evaluate the expression register within a function; unscoped
	" variables do not refer to the global scope. Therefore, evaluation
	" happened earlier in the mappings.
	" To get the expression result into the buffer, we use the unnamed
	" register; this will be restored, anyway.
	call setreg('"', g:ReplaceWithRegister#expr)
	call s:CorrectForRegtype(a:type, '"', getregtype('"'), g:ReplaceWithRegister#expr)
	" Must not clean up the global temp variable to allow command
	" repetition.
	"unlet g:ReplaceWithRegister#expr
	let l:pasteRegister = ''
    endif
    try
	if a:type ==# 'visual'
"****D echomsg '**** visual' string(getpos("'<")) string(getpos("'>")) string(l:pasteRegister)
	    let l:previousLineNum = line("'>") - line("'<") + 1
	    if &selection ==# 'exclusive' && getpos("'<") == getpos("'>")
		" In case of an empty selection, just paste before the cursor
		" position; reestablishing the empty selection would override
		" the current character, a peculiarity of how selections work.
		execute 'silent normal!' l:pasteRegister . 'P'
	    else
		execute 'silent normal! gv' . l:pasteRegister . 'p'
	    endif
	else
"****D echomsg '**** operator' string(getpos("'[")) string(getpos("']")) string(l:pasteRegister)
	    let l:previousLineNum = line("']") - line("'[") + 1
	    if s:IsAfter(getpos("'["), getpos("']"))
		execute 'silent normal!' l:pasteRegister . 'P'
	    else
		" Note: Need to use an "inclusive" selection to make `] include
		" the last moved-over character.
		let l:save_selection = &selection
		set selection=inclusive
		try
		    execute 'silent normal! g`[' . (a:type ==# 'line' ? 'V' : 'v') . 'g`]' . l:pasteRegister . 'p'
		finally
		    let &selection = l:save_selection
		endtry
	    endif
	endif

	let l:newLineNum = line("']") - line("'[") + 1
	if l:previousLineNum >= &report || l:newLineNum >= &report
	    echomsg printf('Replaced %d line%s', l:previousLineNum, (l:previousLineNum == 1 ? '' : 's')) .
	    \   (l:previousLineNum == l:newLineNum ? '' : printf(' with %d line%s', l:newLineNum, (l:newLineNum == 1 ? '' : 's')))
	endif
    finally
	call setreg('"', l:save_reg, l:save_regmode)
	let &clipboard = l:save_clipboard
    endtry
endfunction
function! ReplaceWithRegister#Operator( type, ... )
    let l:pasteText = getreg(s:register, 1) " Expression evaluation inside function context may cause errors, therefore get unevaluated expression when s:register ==# '='.
    let l:regType = getregtype(s:register)
    let l:isCorrected = s:CorrectForRegtype(a:type, s:register, l:regType, l:pasteText)
    try
	call s:ReplaceWithRegister(a:type)
    finally
	if l:isCorrected
	    " Undo the temporary change of the register.
	    " Note: This doesn't cause trouble for the read-only registers :, .,
	    " %, # and =, because their regtype is always 'v'.
	    call setreg(s:register, l:pasteText, l:regType)
	endif
    endtry

    if a:0
	if a:0 >= 2 && a:2
	    silent! call repeat#set(a:1, s:count)
	else
	    silent! call repeat#set(a:1)
	endif
    elseif s:register ==# '='
	" Employ repeat.vim to have the expression re-evaluated on repetition of
	" the operator-pending mapping.
	silent! call repeat#set("\<Plug>ReplaceWithRegisterExpressionSpecial")
    endif
    silent! call visualrepeat#set("\<Plug>ReplaceWithRegisterVisual")
endfunction
function! ReplaceWithRegister#OperatorExpression()
    call ReplaceWithRegister#SetRegister()
    set opfunc=ReplaceWithRegister#Operator

    let l:keys = 'g@'

    if ! &l:modifiable || &l:readonly
	" Probe for "Cannot make changes" error and readonly warning via a no-op
	" dummy modification.
	" In the case of a nomodifiable buffer, Vim will abort the normal mode
	" command chain, discard the g@, and thus not invoke the operatorfunc.
	let l:keys = ":call setline('.', getline('.'))\<CR>" . l:keys
    endif

    if v:register ==# '='
	" Must evaluate the expression register outside of a function.
	let l:keys = ":let g:ReplaceWithRegister#expr = getreg('=')\<CR>" . l:keys
    endif

    return l:keys
endfunction

function! ReplaceWithRegister#VisualMode()
    let l:keys = "1v\<Esc>"
    silent! let l:keys = visualrepeat#reapply#VisualMode(0)
    return l:keys
endfunction

" vim: set ts=8 sts=4 sw=4 noexpandtab ff=unix fdm=syntax :
plugin/ReplaceWithRegister.vim	[[[1
83
" ReplaceWithRegister.vim: Replace text with the contents of a register.
"
" DEPENDENCIES:
"   - Requires Vim 7.0 or higher.
"
" Copyright: (C) 2008-2019 Ingo Karkat
"   The VIM LICENSE applies to this script; see ':help copyright'.
"
" Maintainer:	Ingo Karkat <ingo@karkat.de>

" Avoid installing twice or when in unsupported Vim version.
if exists('g:loaded_ReplaceWithRegister') || (v:version < 700)
    finish
endif
let g:loaded_ReplaceWithRegister = 1

let s:save_cpo = &cpo
set cpo&vim

" This mapping repeats naturally, because it just sets global things, and Vim is
" able to repeat the g@ on its own.
nnoremap <expr> <Plug>ReplaceWithRegisterOperator ReplaceWithRegister#OperatorExpression()
" But we need repeat.vim to get the expression register re-evaluated: When Vim's
" . command re-invokes 'opfunc', the expression isn't re-evaluated, an
" inconsistency with the other mappings. We creatively use repeat.vim to sneak
" in the expression evaluation then.
nnoremap <silent> <Plug>ReplaceWithRegisterExpressionSpecial :<C-u>let g:ReplaceWithRegister#expr = getreg('=')<Bar>execute 'normal!' v:count1 . '.'<CR>

" This mapping needs repeat.vim to be repeatable, because it consists of
" multiple steps (visual selection + 'c' command inside
" ReplaceWithRegister#Operator).
nnoremap <silent> <Plug>ReplaceWithRegisterLine
\ :<C-u>call setline('.', getline('.'))<Bar>
\execute 'silent! call repeat#setreg("\<lt>Plug>ReplaceWithRegisterLine", v:register)'<Bar>
\call ReplaceWithRegister#SetRegister()<Bar>
\if ReplaceWithRegister#IsExprReg()<Bar>
\    let g:ReplaceWithRegister#expr = getreg('=')<Bar>
\endif<Bar>
\call ReplaceWithRegister#SetCount()<Bar>
\execute 'normal! V' . v:count1 . "_\<lt>Esc>"<Bar>
\call ReplaceWithRegister#Operator('visual', "\<lt>Plug>ReplaceWithRegisterLine", 1)<CR>

" Repeat not defined in visual mode, but enabled through visualrepeat.vim.
vnoremap <silent> <Plug>ReplaceWithRegisterVisual
\ :<C-u>call setline('.', getline('.'))<Bar>
\execute 'silent! call repeat#setreg("\<lt>Plug>ReplaceWithRegisterVisual", v:register)'<Bar>
\call ReplaceWithRegister#SetRegister()<Bar>
\if ReplaceWithRegister#IsExprReg()<Bar>
\    let g:ReplaceWithRegister#expr = getreg('=')<Bar>
\endif<Bar>
\call ReplaceWithRegister#Operator('visual', "\<lt>Plug>ReplaceWithRegisterVisual")<CR>

" A normal-mode repeat of the visual mapping is triggered by repeat.vim. It
" establishes a new selection at the cursor position, of the same mode and size
" as the last selection.
" If [count] is given, that number of lines is used / the original size is
" multiplied accordingly. This has the side effect that a repeat with [count]
" will persist the expanded size, just as it should.
" First of all, the register must be handled, though.
nnoremap <silent> <Plug>ReplaceWithRegisterVisual
\ :<C-u>call setline('.', getline('.'))<Bar>
\execute 'silent! call repeat#setreg("\<lt>Plug>ReplaceWithRegisterVisual", v:register)'<Bar>
\call ReplaceWithRegister#SetRegister()<Bar>
\if ReplaceWithRegister#IsExprReg()<Bar>
\    let g:ReplaceWithRegister#expr = getreg('=')<Bar>
\endif<Bar>
\execute 'normal!' ReplaceWithRegister#VisualMode()<Bar>
\call ReplaceWithRegister#Operator('visual', "\<lt>Plug>ReplaceWithRegisterVisual")<CR>


if ! hasmapto('<Plug>ReplaceWithRegisterOperator', 'n')
    nmap gr <Plug>ReplaceWithRegisterOperator
endif
if ! hasmapto('<Plug>ReplaceWithRegisterLine', 'n')
    nmap grr <Plug>ReplaceWithRegisterLine
endif
if ! hasmapto('<Plug>ReplaceWithRegisterVisual', 'x')
    xmap gr <Plug>ReplaceWithRegisterVisual
endif

let &cpo = s:save_cpo
unlet s:save_cpo
" vim: set ts=8 sts=4 sw=4 noexpandtab ff=unix fdm=syntax :
doc/ReplaceWithRegister.txt	[[[1
229
*ReplaceWithRegister.txt*   Replace text with the contents of a register.

		   REPLACE WITH REGISTER    by Ingo Karkat
						     *ReplaceWithRegister.vim*
description			|ReplaceWithRegister-description|
usage				|ReplaceWithRegister-usage|
installation			|ReplaceWithRegister-installation|
configuration			|ReplaceWithRegister-configuration|
limitations			|ReplaceWithRegister-limitations|
known problems			|ReplaceWithRegister-known-problems|
todo				|ReplaceWithRegister-todo|
history				|ReplaceWithRegister-history|

==============================================================================
DESCRIPTION				     *ReplaceWithRegister-description*

Replacing an existing text with the contents of a register is a very common
task during editing. One typically first deletes the existing text via the
|d|, |D| or |dd| commands, then pastes the register with |p| or |P|. Most of
the time, the unnamed register is involved, with the following pitfall: If you
forget to delete into the black-hole register ("_), the replacement text is
overwritten!

This plugin offers a two-in-one command that replaces text covered by a
{motion}, entire line(s) or the current selection with the contents of a
register; the old text is deleted into the black-hole register, i.e. it's
gone. (But of course, the command can be easily undone.)

The replacement mode (characters or entire lines) is determined by the
replacement command / selection, not by the register contents. This avoids
surprises like when the replacement text was a linewise yank, but the
replacement is characterwise: In this case, no additional newline is inserted.

SEE ALSO								     *

- ReplaceWithSameIndentRegister.vim (vimscript #5046) is a companion plugin
  for the special (but frequent) case of replacing lines while keeping the
  original indent.
- LineJugglerCommands.vim (vimscript #4465) provides a similar :Replace [["]x]
  Ex command.

RELATED WORKS								     *

- regreplop.vim (vimscript #2702) provides an alternative implementation of
  the same idea.
- operator-replace (vimscript #2782) provides replacement of {motion} only,
  depends on another library of the author, and does not have a default
  mapping.
- Luc Hermitte has an elegant minimalistic visual-mode mapping in
  https://github.com/LucHermitte/lh-misc/blob/master/plugin/repl-visual-no-reg-overwrite.vim
- EasyClip (https://github.com/svermeulen/vim-easyclip) changes the delete
  commands to stop yanking, introduces a new "m" command for cutting, and also
  provides an "s" substitution operator that pastes register contents over the
  moved-over text.
- R (replace) operator (vimscript #5239) provides an alternative
  implementation that defaults to the clipboard register.
- replace_operator.vim (vimscript #5742) provides normal (only with motion,
  not by lines) and visual mode mappings.
- subversive.vim (vimscript #5763) provides another alternative
  implementation, has no default mappings, and as a unique feature provides a
  two-motion operator that changes all occurrences in the moved-over range
  with typed text; something similar to the functionality of my ChangeGlobally
  plugin (vimscript #4321).

==============================================================================
USAGE						   *ReplaceWithRegister-usage*
							     *gr* *grr* *v_gr*
[count]["x]gr{motion}	Replace {motion} text with the contents of register x.
			Especially when using the unnamed register, this is
			quicker than "_d{motion}P or "_c{motion}<C-R>"
[count]["x]grr		Replace [count] lines with the contents of register x.
			To replace from the cursor position to the end of the
			line use ["x]gr$
{Visual}["x]gr		Replace the selection with the contents of register x.

==============================================================================
INSTALLATION				    *ReplaceWithRegister-installation*

The code is hosted in a Git repo at
    https://github.com/inkarkat/vim-ReplaceWithRegister
You can use your favorite plugin manager, or "git clone" into a directory used
for Vim |packages|. Releases are on the "stable" branch, the latest unstable
development snapshot on "master".


This script is also packaged as a |vimball|. If you have the "gunzip"
decompressor in your PATH, simply edit the *.vmb.gz package in Vim; otherwise,
decompress the archive first, e.g. using WinZip. Inside Vim, install by
sourcing the vimball or via the |:UseVimball| command. >
    vim ReplaceWithRegister*.vmb.gz
    :so %
To uninstall, use the |:RmVimball| command.

DEPENDENCIES				    *ReplaceWithRegister-dependencies*

- Requires Vim 7.0 or higher.
- repeat.vim (vimscript #2136) plugin (optional)
  To support repetition with a register other than the default register, you
  need version 1.1 or later.
- visualrepeat.vim (vimscript #3848) plugin (version 2.00 or higher; optional)

==============================================================================
CONFIGURATION				   *ReplaceWithRegister-configuration*
						   *ReplaceWithRegister-remap*
The default mappings override the (rarely used, but somewhat related) |gr|
command (replace virtual characters under the cursor with {char}).
If you want to use different mappings, map your keys to the
<Plug>ReplaceWithRegister... mapping targets _before_ sourcing the script
(e.g. in your |vimrc|): >
    nmap <Leader>r  <Plug>ReplaceWithRegisterOperator
    nmap <Leader>rr <Plug>ReplaceWithRegisterLine
    xmap <Leader>r  <Plug>ReplaceWithRegisterVisual
<
==============================================================================
LIMITATIONS				     *ReplaceWithRegister-limitations*

- The mode cannot be set for register "/; it will always be pasted
  characterwise. Implement a special case for glp?
- With :set selection=clipboard together with either "autoselect" (in the
  console) or a 'guioptions' setting that contains "a" (in the GUI), the
  mappings don't seem to work. This is because they all temporarily create a
  visual selection, whose contents are put into register *, which is the
  default register due to the 'selection' setting. Therefore, the replacement
  replaces itself. The same happens when you try to replace the visual
  selection via the built-in |v_p| command. Either don't use these settings in
  combination, or explicitly select the default register by prepending "" to
  the mappings.

KNOWN PROBLEMS				  *ReplaceWithRegister-known-problems*

TODO						    *ReplaceWithRegister-todo*

IDEAS						   *ReplaceWithRegister-ideas*

CONTRIBUTING				      *ReplaceWithRegister-contribute*

Report any bugs, send patches, or suggest features via the issue tracker at
https://github.com/inkarkat/vim-ReplaceWithRegister/issues or email (address
below).

==============================================================================
HISTORY						 *ReplaceWithRegister-history*

1.43	19-Nov-2019
- BUG: {count}grr does not repeat the count.
- Suppress "--No lines in buffer--" message when replacing the entire buffer,
  and combine "Deleted N lines" / "Added M lines" into a single message that
  is given when either previous or new amount of lines reaches 'report'.

1.42	29-Oct-2014
- BUG: Previous version 1.41 broke replacement of single character with
  gr{motion}.

1.41	28-May-2014
- Also handle empty exclusive selection and empty text object
  (e.g. gri" on "").

1.40	21-Nov-2013
- Avoid changing the jumplist.
- Use optional visualrepeat#reapply#VisualMode() for normal mode repeat of a
  visual mapping. When supplying a [count] on such repeat of a previous
  linewise selection, now [count] number of lines instead of [count] times the
  original selection is used.

1.31	28-Nov-2012
BUG: When repeat.vim is not installed, the grr and v_gr mappings do nothing.
Need to :execute the :silent! call of repeat.vim to avoid that the remainder
of the command line is aborted together with the call. Thanks for David
Kotchan for reporting this.

1.30	06-Dec-2011
- Adaptations for blockwise replace:
  - If the register contains just a single line, temporarily duplicate the
    line to match the height of the blockwise selection.
  - If the register contains multiple lines, paste as blockwise.
- BUG: v:register is not replaced during command repetition, so repeat always
  used the unnamed register. Add register registration to enhanced repeat.vim
  plugin, which also handles repetition when used together with the expression
  register "=. Requires a so far inofficial update to repeat.vim version 1.0
  (that hopefully makes it into upstream), which is available at
  https://github.com/inkarkat/vim-repeat/zipball/1.0ENH1
- Moved functions from plugin to separate autoload script.

1.20	26-Apr-2011
- BUG: ReplaceWithRegisterOperator didn't work correctly with linewise motions
  (like "+"); need to use a linewise visual selection in this case.
- BUG: Text duplicated from yanked previous lines is inserted on a replacement
  of a visual blockwise selection. Switch replacement mechanism to a put in
  visual mode in combination with a save and restore of the unnamed register.
  This should handle all cases and doesn't require the autoindent workaround,
  neither.

1.10	21-Apr-2011
- The operator-pending mapping now also handles 'nomodifiable' and 'readonly'
  buffers without function errors.
- Add experimental support for repeating the replacement also in visual mode
  through visualrepeat.vim. Renamed vmap <Plug>ReplaceWithRegisterOperator to
  <Plug>ReplaceWithRegisterVisual for that.
  *** PLEASE UPDATE YOUR CUSTOM MAPPINGS ***
  A repeat in visual mode will now apply the previous line and operator
  replacement to the selection text. A repeat in normal mode will apply the
  previous visual mode replacement at the current cursor position, using the
  size of the last visual selection.

1.03    07-Jan-2011
- ENH: Better handling when buffer is 'nomodifiable' or 'readonly'.
- Added separate help file and packaging the plugin as a vimball.

1.02    25-Nov-2009
Replaced the <SID>Count workaround with :map-expr and an intermediate
s:ReplaceWithRegisterOperatorExpression.

1.01    06-Oct-2009
Do not define "gr" mapping for select mode; printable characters should start
insert mode.

1.00	05-Jal-2009
First published version.

0.01	11-Aug-2008
Started development.

==============================================================================
Copyright: (C) 2008-2019 Ingo Karkat
The VIM LICENSE applies to this plugin; see |copyright|.

Maintainer:	Ingo Karkat <ingo@karkat.de>
==============================================================================
 vim:tw=78:ts=8:ft=help:norl:
