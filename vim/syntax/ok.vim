if exists("b:current_syntax")
    finish
endif

let s:cpo_save = &cpo
set cpo&vim

syntax match okNumberLiteral display "\<[0-9][0-9_]*"
syntax match okNumberLiteral display "\<0x[a-fA-F0-9_]\+"
syntax match okNumberLiteral display "\<0o[0-7_]\+"
syntax match okNumberLiteral display "\<0b[01_]\+"
hi def link okNumberLiteral Number

syntax match okEscapeError display contained /\\./
syntax match okEscape display contained /\\\([nrt0\\'"]\|x\x\{2}\)/
syntax match okEscapeUnicode display contained /\\u{\%(\x_*\)\{1,6}}/
syntax region okStringLiteral matchgroup=okStringDelimiter start=+"+ skip=+\\\\\|\\"+ end=+"+ contains=okEscape,okEscapeError,@Spell
hi def link okEscapeError Error
hi def link okEscape Special
hi def link okEscapeUnicode Special
hi def link okStringLiteral Number
hi def link okStringDelimiter Number

syntax keyword okUndefined undef
hi def link okUndefined Number

syntax match okStructure "\V("
syntax match okStructure "\V)"
syntax match okStructure "\V["
syntax match okStructure "\V{"
syntax match okStructure "\V]"
syntax match okStructure "\V}"
syntax match okStructure "\V`"
syntax match okStructure "\V~"
syntax match okStructure "\V!"
syntax match okStructure "\V$"
syntax match okStructure "\V%"
syntax match okStructure "\V^"
syntax match okStructure "\V&"
syntax match okStructure "\V*"
syntax match okStructure "\V-"
syntax match okStructure "\V_"
syntax match okStructure "\V="
syntax match okStructure "\V+"
syntax match okStructure "\V\\"
syntax match okStructure "\V|"
syntax match okStructure "\V;"
syntax match okStructure "\V:"
syntax match okStructure "\V,"
syntax match okStructure "\V<"
syntax match okStructure "\V."
syntax match okStructure "\V>"
syntax match okStructure "\V/"
syntax match okStructure "\V?"
hi def link okStructure Structure

syntax match okComptime "#"
syntax match okComptime "#debug_mode"
hi def link okComptime Define

syntax match okModPath "\w\(\w\)*::[^<]"he=e-3,me=e-3
hi def link okModPath Include

syntax match okBlockCall "\w\(\w\)*("he=e-1,me=e-1
hi def link okBlockCall Function

syntax match okCollectionMake "\w\+{"he=e-1,me=e-1
hi def link okCollectionMake StorageClass

syntax match okBuiltinPrimitive "\%(@isize\|@usize\|@f16\|@f32\|@f64\|@bool\|@str\|@opt\)"
syntax match okBuiltinPrimitive "\%(@c_short\|@c_ushort\|@c_int\|@c_uint\|@c_long\|@c_ulong\|@c_longlong\|@c_ulonglong\|@c_longdouble\|@c_str\)"
syntax match okBuiltinPrimitive "\v\@[iu][0-9]+"
hi def link okBuiltinPrimitive Type

syntax match okBuiltinLiteral "\v\@true"
syntax match okBuiltinLiteral "\v\@false"
syntax match okBuiltinLiteral "\v\@nil"
hi def link okBuiltinLiteral Number

syntax match okBuiltinIndexer "\v\@arr"
syntax match okBuiltinIndexer "\v\@map"
syntax match okBuiltinIndexer "\v\@tab"
hi def link okBuiltinIndexer StorageClass

syntax match okBuiltinInstruction "\v\@set"
syntax match okBuiltinInstruction "\v\@copy"
syntax match okBuiltinInstruction "\v\@clone"
syntax match okBuiltinInstruction "\v\@plus"
syntax match okBuiltinInstruction "\v\@times"
syntax match okBuiltinInstruction "\v\@minus"
syntax match okBuiltinInstruction "\v\@divided"
syntax match okBuiltinInstruction "\v\@not"
syntax match okBuiltinInstruction "\v\@and"
syntax match okBuiltinInstruction "\v\@or"
syntax match okBuiltinInstruction "\v\@eql"
syntax match okBuiltinInstruction "\v\@notEql"
syntax match okBuiltinInstruction "\v\@bitAnd"
syntax match okBuiltinInstruction "\v\@bitOr"
syntax match okBuiltinInstruction "\v\@first"
syntax match okBuiltinInstruction "\v\@last"
syntax match okBuiltinInstruction "\v\@clear"
syntax match okBuiltinInstruction "\v\@isEmpty"
syntax match okBuiltinInstruction "\v\@isNotEmpty"
syntax match okBuiltinInstruction "\v\@some"
syntax match okBuiltinInstruction "\v\@isSome"
syntax match okBuiltinInstruction "\v\@isNil"
syntax match okBuiltinInstruction "\v\@include"
syntax match okBuiltinInstruction "\v\@assert"
syntax match okBuiltinInstruction "\v\@to"
hi def link okBuiltinInstruction Statement

syntax region okComment start="'" end="$"
hi def link okComment Comment

syntax region okDocComment start="''" end="$"
hi def link okDocComment SpecialComment

let b:current_syntax = "ok"

let &cpo = s:cpo_save
unlet! s:cpo_save
