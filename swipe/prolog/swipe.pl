:- module(swipe, 
   [  run/1
   ,  command/2
   ,  command/3
   ,  with_pipe_output/3
   ,  with_pipe_input/3
   ,  op(300,xfy,:>)
   ,  op(300,yfx,>:)
   ,  op(200,fy,@)
   ]).

/** <module> Shell pipeline execution utilities

   This module provides a mechanism for composing and running Unix shell
   pipelines. It defines a typed algebraic term language using operators for
   piping and redirections while checking that the type of data passing
   through the standard input and output streams of each subprocess match
   with those of connected processes.
   The language is only capable of describing simple, linear pipelines, where
   each process can have one or zero input streams and one or zero output
   streams. The type of a process is denoted by a term =|X>>Y|=, where
   X and Y are stream types and can be 0 for no stream, or $T for a stream
   of type T, where T is an arbitrary term describing what sort of data is
   in the stream, eg, plain text or XML. The typing judgements are as follows:
   ==
   P >> Q :: X>>Z :- P :: X>>Y,    Q::Y>>Z.
   F :> Q :: 0>>Z :- F :: file(Y), Q::Y>>Z.
   P >: F :: X>>0 :- F :: file(Y), P::X>>Y.
   P * Q  :: T    :- P :: T1, Q :: T2, seq_types(T1,T2,T).
   P + Q  :: T    :- P :: T1, Q :: T2, par_types(T1,T2,T).
   P :: T :- swipe:def(P,Q), Q :: T.
   sh(T,Fmt,Args) :: T.
   sh(T,Cmd) :: T.

   in(D,P) :: T   :- P::T. % execute P in directory D

   Filename^T :: file(T).
   ==
   The rules for combining types with the * operator (shell &&, sequential
   execution) and + operator (shell &, concurrent execution) are encoded
   in the predicates seq_types and par_types. The rules for sequential
   excution are:

      1. A process with no input (output) (type 0) can combine with a process 
         with any input (output) type, and the compound inherits that input (output) type. 
      2. If both processes have nonzero input (output) types, then those types must unify,
         and the compound inherits that output type.

   The rules for concurrent execution are 

      1. A process with no input (output) (type 0) can combine with a process 
         with any input (output) type, and the compound inherits that 
         input (output) type. 
      2. If both processes have nonzero input types, then they cannot be run concurrently.
      2. If both processes have nonzero output types, then those types must unify, 
         and the compound inherits that output type.

   If the type requirements are not met, then the system throws a helpful type_mismatch exception.

   The primitive processes are expressed as shell commands.
   A term =|sh(T,Cmd)|=, where T is an explicitly  given type,
   corresponds to a shell command Cmd, written, including arguments, as you
   would type it into the Unix shell. Arguments can be handling using the
   form =|sh(T,Fmt,Args)|=, where Fmt is a format string as used by format/2,
   and Args is a list of arguments of type:
   ==
   shell_args ---> spec+access % A file spec and access mode, format with ~s
                 ; @ground     % any term, is written and escaped, format with ~s
                 ; \_.         % Any other kind of argument, passed through
   access ---> read ; write ; append ; execute.
   ==

   ---+++ File names

   File names should passed to sh/3 as Spec+Access.
   If Spec is atomic, it is treated as an explicit absolute or relative
   path in the file system and formatted quoted and escaped so that
   any special characters in the path are properly handled.

   If Spec is a compound term, the system uses absolute_file_name/3
   with the access(Access) option to expand Spec. This must succeed exactly
   once, otherwise an exception is thrown. The resulting path is quoted and escaped.

   In both cases, the result is captured by '~s' in the format string. There is
   a subtlety in the handling of compound file specifier terms: the file must
   exist with the correct access at pipeline *composition* time---if the file is
   only created when the pipeline is run, then the path expansion will fail. In
   these cases, you must use an atomic file specifier, or the (@)/1 operator.
   This also applies to files used with the redirection operators (:>)/2 and (>:)/2.

   ---+++ Declaring new processes

   New compound pipelines can be declared using the multifile predicate
   swipe:def/2. The commands cat/0, cat/1 and echo/1 are already defined.
   ==
   cat       :: $T >> $T. % any stream type to the same stream type
   cat(F^T)  :: 0 >> $T.   % output contents of file F
   echo(S^T) :: 0 >> $T.   % output literal text S as type T
   ==
   
   ---+++ Running 

   A pipeline expression can be used in one of three ways:
      1. With command/{2,3}, which produce a string which can be passed to shell/1
         or used with open(pipe(Cmd), ...).
      2. With run/1, which calls the formatted command directly using shell/1.
      3. Using with_pipe_output/3 or with_pipe_output/3, which runs the pipeline
         concurrently with the current thread, making either its standard input 
         or standard output available on a Prolog stream.

   @tbd
   * Use of parenthesis for grouping might not work in some cases
   * Connecting stdin and stdout of pipeline with Prolog streams
   * Decide on best quoting/escaping mechanism
*/

:- meta_predicate with_pipe_output(-,+,0), with_pipe_input(-,+,0).
:- multifile def/2.

:- use_module(library(dcg_codes)).
:- use_module(library(fileutils)).

:- set_prolog_flag(double_quotes,string).
:- set_prolog_flag(back_quotes,codes).

:- setting(quote_method,oneof([strong,weak]),strong,"Filename quoting method").

def(cat,      sh($T >> $T,"cat")).
def(cat(F^T), sh(0 >> $T,"cat ~s",[F+read])).
def(echo(S^T),sh(0 >> $T,"echo ~s",[@S])).

ppipe(P,T) --> "(",pipe(P,T),")".
pipe(P>>Q, X>>Z)   --> !, ppipe(P,X>>Y1), " | ", ppipe(Q,Y2>>Z), {u(P>>Q,Y1,Y2)}.
pipe(F^X:>P, 0>>Y) --> !, ppipe(P, $X1 >> Y), " < ", file(F,read), {u(F^X:>P,X,X1)}.
pipe(P>:F^Y, X>>0) --> !, ppipe(P, X >> $Y1), " > ", file(F,write), {u(P>:F^Y,Y1,Y)}.
pipe(P*Q, T) -->       !, ppipe(P,T1), " && ", ppipe(Q,T2), {seq_types(P*Q,T1,T2,T)}.
pipe(P+Q,T) -->        !, ppipe(P,T1), " & ", ppipe(Q,T2), {par_types(P+Q,T1,T2,T)}.
pipe(in(D,P),T) -->    !, "cd ", file(D,write), " && ", ppipe(P,T). 
pipe(sh(T,Str),T) -->  !, at(Str).
pipe(sh(T,F,A),T) -->  !, {maplist(quote_arg,A,A1)}, fmt(F,A1). 
pipe(M,T) -->          {def(M,P)}, pipe(P,T).

file(Spec,Access) --> 
   {  (  atomic(Spec) -> atom_codes(Spec,Codes)
      ;  findall(P, absolute_file_name(Spec,P,[access(Access)]), Ps),
         (  Ps=[] -> throw(no_matching_file(Spec:Access))
         ;  Ps=[_,_|_] -> throw(indeterminate_file(Spec:Access,Ps))
         ;  Ps=[Path] -> atom_codes(Path,Codes)
         )
      ),
      setting(quote_method,QM) 
   },
   quote(QM,Codes).

quote_arg(\A,A).
quote_arg(@A,B) :- 
   setting(quote_method,QM), 
   format(codes(Codes),'~w',[A]),
   quote(QM,Codes,Quoted,[]),
   string_codes(B,Quoted).
quote_arg(Spec+Access,B) :- 
   file(Spec,Access,Codes,[]), 
   string_codes(B,Codes).


seq_types(P,In1>>Out1,In2>>Out2,In>>Out) :-
   meet(input_of(P),In1,In2,In),
   meet(output_of(P),Out1,Out2,Out).

% this might be wrong...
par_types(P,In1>>Out1,In2>>Out2,In>>Out) :-
   either(input_of(P),In1,In2,In),
   meet(output_of(P),Out1,Out2,Out).

u(_,T,T) :- !.
u(P,T1,T2) :- throw(type_mismatch(P,T1,T2)).

meet(_,T,T,T) :- !.
meet(_,0,T,T) :- !.
meet(_,T,0,T) :- !.
meet(P,T1,T2,_) :- throw(type_mismatch(P,T1,T2)).

either(_,0,T,T) :- !.
either(_,T,0,T) :- !.
either(P,T1,T2,_) :- throw(type_mismatch(P,T1,T2)).

%% command(Pipe:(X>>Y), -Type:pipe_type, Cmd:string) is det.
%% command(Pipe:(X>>Y), Cmd:string) is det.
%
%  Formats the shell command for a pipeline expression. Three argument
%  version unifies Type with the inferred type of the pipeline.
command(Pipeline,Cmd) :- command(Pipeline,_,Cmd).
command(Pipeline,Type,Cmd) :-
   pipe(Pipeline,Type,Codes,[]),
   string_codes(Cmd,Codes).

%% run(Pipe:(X>>Y)) is det
%
%  Runs a pipeline. Standard input and output of the process are 
%  inherited directly from Prolog process.
run(Pipeline) :-
   (  pipe(Pipeline,T,Cmd,[]) 
   -> debug(swipe,"Executing: ~w, ~s",[T,Cmd]),
      shell(Cmd)
   ;  throw(bad_pipeline(Pipeline))
   ).


%% with_pipe_output(S:stream, Pipe:(0>>$Y), G:callable) is det.
%  
%  Starts the given pipeline and calls goal G, with the standard output from
%  the pipeline available on stream S. The type of Pipe reflects the requirement
%  for it to expect nothing on standard input and must produce something on 
%  standard output.
with_pipe_output(S,Pipe,Goal) :-
   command(Pipe, 0 >> $_, Cmd),
   with_stream(S, open(pipe(Cmd),read,S), Goal).

%% with_pipe_input(S:stream, Pipe:(0>>$Y), G:callable) is det.
%  
%  Starts the given pipeline and calls goal G, with the standard input from
%  the pipeline available on stream S. The type of Pipe reflects the requirement
%  for it to expect input on stdin input and produce nothing on the output.
with_pipe_input(S,Pipe,Goal) :-
   command(Pipe, $_ >> 0, Cmd),
   with_stream(S, open(pipe(Cmd),write,S), Goal).


quote(strong,Codes) --> "'", esc(strong,Codes), "'".
quote(weak,Codes) --> "\"", esc(weak,Codes), "\"".

% weak(+Codes,-Tail)// is semidet.
% weak(-Codes,-Tail)// is semidet.
%
% This predicate encapsulates Bash's weak (ie double quoted) escaping rules.
% Basically, anything can appear except $, ", or `, which must be escaped
% by a backslash. A backslash that is not interpreted as a valid escape
% is retained, but \\ is also interpreted as a valid escape sequence for a 
% backslash. At this point, the rules become somewhat arcane and differ between
% shells. If your shell beeps when you want to write "\a\b\c", then I'm afraid
% you're going to have to work it out for yourself.
weak([C|T],T) --> [0'\\,C], {member(C,`\\$"\``)}.
weak([C|T],T) --> [C], {\+member(C,`\\$"\``)}.

%% strong(+Codes,-Tail)// is semidet.
%% string(-Codes,-Tail)// is semidet.
%
% This predicate encapsulated Bash's strong (single quoted) escape rules.
% Basically anything is allowed verbatim between single quotes, except for
% a single quote. The only way to inject a single quote is to terminate the
% string with ', then append an escaped ' as \' and then reopen a new string
% with ' -- the shell concatenates these three pieces into one string.
strong([C|T],T) --> [C], ({C=0''} -> "\\''"; []).

