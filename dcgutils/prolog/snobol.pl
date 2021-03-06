:- module(snobol, [
		any//1
   ,  notany//1
   ,  arb//0 
   ,  arbno//1
   ,  bal//1
	,	span//1
   ,  break//1
   ,  len//1
   ,  rem//0
   ]).


/** <module> SNOBOL-inspired DCG operators

   NB. 
   FAIL is just {fail} or dcg_core:fail 
   SUCCEED is {repeat} or dcg_core:repeat.
   FENCE is ! (cut).

   ABORT cannot be implemented in plain Prolog because there is no
   ancestral cut operator. Instead abort//0 just throws an exception
   which you must arrange to catch yourself.

   POS, RPOS, TAB and RTAB are not context-free rules and can only be 
   implemented in paired-state DCG which counts the current position in 
   the string.
*/

:- meta_predicate arbno(//,?,?).

% SNOBOL4ish rules
%
%	Others:
%		maxarb
%		pos rpos
%		tab rtab

%% rem// is det.
rem(_,[]).

%% abort// is det.
abort(_,_) :- throw(abort).

%% any(+L:list(_))// is nondet.
%  Matches any element of L.
any(L)    --> [X], {member(X,L)}.

%% notany(+L:list(_))// is nondet.
%  Matches anything not in L.
notany(L) --> [X], {maplist(dif(X),L)}.

%% arb// is nondet.
%  Matches an arbitrary sequence. Proceeds cautiously.
arb       --> []; [_], arb.

%% arbno(+P:phrase)// is nondet.
%  Matches an arbitrary number of P. Proceeds cautiously.
%  Any variables in P are shared across calls.
arbno(P)  --> []; phrase(P), arbno(P).

%% span(+L:list(_))// is nondet.
%  Matches the longest possible sequence of symbols from L.
span(L,A,[]) :- any(L,A,[]).
span(L)      --> any(L), span(L).
span(L), [N] --> any(L), [N], {maplist(dif(N),L)}.

%% break(+L:list(_))// is nondet.
%  Matches the longest possible sequence of symbols not in L.
break(L,A,[]) :- notany(L,A,[]).
break(L)      --> notany(L), break(L).
break(L), [N] --> notany(L), [N], {member(N,L)}.

%% len(+N:natural)// is det.
%% len(-N:natural)// is nondet.
%  Matches any N symbols.
len(0)    --> []. 
len(N)    --> [_], ({var(N)} -> len(M), {succ(M,N)}; {succ(M,N)}, len(M)). 


%% bal(+Delims:list(C))// is nondet.
%  Matches any expression with balanced generalised parentheses. 
%  The opening and closing parenthesis must be supplied as a list
%  of terminals [Open,Close]. 
bal(Delims) --> bal_one(Delims), arbno(bal_one(Delims)).
bal_one(Delims) --> {Delims=[O,C]}, [O], bal(Delims), [C].
bal_one(Delims) --> notany(Delims).
