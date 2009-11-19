signature PARSE = sig
  
  type token
  val token_to_string : token -> string
  val file_to_tokenstream : string -> (token * Pos.pos) Stream.stream 
  val string_to_tokenstream : string -> (token * Pos.pos) Stream.stream
  val decl_parser : (ExtSyn.decl, token) Parsing.parser

end

structure Parse :> PARSE = struct

  open Global
  open Parsing
  
  infixr 4 << >>
  infixr 3 &&
  infix  2 -- ##
  infix  2 wth suchthat return guard when
  infixr 1 ||

  datatype token = 
      PERIOD | LPAREN | RPAREN | CONJ 
    | LOLLI | BANG | NEQ | EQ
    | LAMBDA of string | FORALL of string | EXISTS of string 
    | ID of string list * string 
    | PERCENT of string | COLON | WS

  fun token_to_string token = 
      case token of 
        PERIOD => "." | LPAREN => "(" | RPAREN => ")" | CONJ => ","
      | LOLLI => "-o" | BANG => "!" | NEQ => "<>" | EQ => "==" 
      | LAMBDA x => "λ " ^ x | FORALL x => "∀ " ^ x | EXISTS x => "∃ " ^ x
      | ID(path,x) => concat (map (fn x => x ^  ".") path) ^ x 
      | PERCENT x => "%" ^ x | COLON => ":" | WS => ""

  (* Literate transform: remove all non-literate parts from a file *)
  val transform_tok0 = 
   fn fs =>
      let
        fun newline fs () = 
            case Stream.force fs of 
              Stream.Nil => Stream.Nil
            | Stream.Cons((">",_),fs) => codeline fs ()
            | _ => textline fs ()

        and textline fs () = 
            case Stream.force fs of
              Stream.Nil => Stream.Nil
            | Stream.Cons(("\n",_),fs) => newline fs ()
            | Stream.Cons(_,fs) => textline fs ()

        and codeline fs () =
            case Stream.force fs of
              Stream.Nil => Stream.Nil
            | Stream.Cons(("\n",p),fs) => 
              Stream.Cons(("\n",p),Stream.delay(newline fs))
            | Stream.Cons((c,p),fs) =>
              Stream.Cons((c,p),Stream.delay(codeline fs))
      in Stream.delay(newline fs) end 
            

  (* Transform 1: 
   *** Strip line comments
   *** Consolidate whitespace
   *** Consolidate identifiers and separate separators
   *)
  val transform_tok1 = 
      let
        val sep = 
            fn "." => false | "(" => false | ")" => false | "," => false 
             | "!" => false
             | "λ" => false | "∀" => false | "∃" => false 
             | "\\" => false | "%" => false | ":" => false
             | " " => false | "\t" => false | "\n" => false
             | _ => true
        val ws = 
            fn " " => true | "\t" => true | "\n" => true | _ => false
        val idpart = repeat1 (satisfy sep) wth concat
        val linecomment = 
            literal "%" >> literal "%" >> 
            repeat (satisfy (fn "\n" => false | _ => true)) >> literal "\n" >>
            succeed " "
        val tokenparser = 
            alt [linecomment, 
                 literal ".", literal "(", literal ")", literal ",",
                 literal "!",
                 literal "λ", literal "∀", literal "∃", 
                 literal "\\", literal "%", literal ":",
                 repeat1 (satisfy ws) >> succeed " ", idpart]
      in transform (!! tokenparser) end

  (* Transform 2:
   *** Tokenize separators
   *** Read TeX-style characters (XXX not implemented XXX)
   *** Ensure binders are followed by identifiers and periods (XXX this choice
   ***   could be problematic if we need to attach types to binders...)
   *** Resolve identifier paths (XXX not implemented XXX)
   *)
  val transform_tok2 = 
      let
        fun not str pos = 
            raise 
              ErrPos(pos, "Binder " ^ " not followed by identifier + period")
        fun backslash pos = raise ErrPos(pos, "Backslash not permitted")
        val white = repeat (literal " ") >> succeed ()
        val tokenparser = 
            alt [literal "." >> succeed PERIOD,
                 literal "(" >> succeed LPAREN,
                 literal ")" >> succeed RPAREN,
                 literal "," >> succeed CONJ,
                 literal "!" >> succeed BANG,
                 literal "%" >> any wth PERCENT,
                 literal ":" >> succeed COLON,
                 literal " " >> succeed WS,
                 literal "-o" >> succeed LOLLI,
                 literal "<>" >> succeed NEQ,
                 literal "==" >> succeed EQ,
                 literal "λ" >> (white >> any << white << literal "." 
                                       ## (fn pos => not "λ" pos)) wth LAMBDA,
                 literal "∀" >> (white >> any << white << literal "." 
                                       ## (fn pos => not "∀" pos)) wth FORALL,
                 literal "∃" >> (white >> any << white << literal "." 
                                       ## (fn pos => not "∃" pos)) wth EXISTS,
                 (!! (literal "\\") -- (fn (_,pos) => backslash pos)), 
                 any wth (fn x => ID([],x))] 
      in transform (!! tokenparser) end 

  (* Transform 3: Filter whitespace *)
  val transform_tok3 = 
      let 
        fun filter s () = 
            case Stream.force s of
              Stream.Nil => Stream.Nil
            | Stream.Cons((WS,_),s) => filter s ()
            | Stream.Cons((tok,pos : Pos.pos),s) => 
              Stream.Cons ((tok,pos),Stream.delay (filter s))
      in fn s => Stream.delay (filter s) end
 
  (* Main parser *)
  val decl_parser =
      let 
        fun conj pos ((trm1,pos1),(trm2,pos2)) =
            let val pos = Pos.union(Pos.union(pos,pos1),pos2)
            in (ExtSyn.Conj(pos,trm1,trm2),pos) end
        fun bang pos ((trm1,pos1)) = 
            let val pos = Pos.union(pos,pos1)
            in (ExtSyn.Bang(pos,trm1),pos) end
        fun lolli pos ((trm1,pos1),(trm2,pos2)) =
            let val pos = Pos.union(Pos.union(pos,pos1),pos2)
            in (ExtSyn.Lolli(pos,trm1,trm2),pos) end
        fun neq pos ((trm1,pos1),(trm2,pos2)) =
            let val pos = Pos.union(Pos.union(pos,pos1),pos2)
            in (ExtSyn.Neq(pos,trm1,trm2),pos) end
        fun eq pos ((trm1,pos1),(trm2,pos2)) =
            let val pos = Pos.union(Pos.union(pos,pos1),pos2)
            in (ExtSyn.Eq(pos,trm1,trm2),pos) end
        fun lambda ((x,pos),(trm,pos')) = 
            let val pos = Pos.union(pos,pos') 
            in (ExtSyn.Lambda(pos,SimpleType.Var'(),x,trm),pos) end
        fun forall ((x,pos),(trm,pos')) = 
            let val pos = Pos.union(pos,pos') 
            in (ExtSyn.Forall(pos,SimpleType.Var'(),x,trm),pos) end
        fun exists ((x,pos),(trm,pos')) = 
            let val pos = Pos.union(pos,pos') 
            in (ExtSyn.Exists(pos,SimpleType.Var'(),x,trm),pos) end
        val fixityitem_parser = 
        get (fn pos => 
          (literal LPAREN && literal RPAREN) wth (fn _ => Atm(ExtSyn.Unit(pos),pos)) ||
          maybe (fn tok =>
            case tok of 
              CONJ => SOME(Opr(Infix(Right,6,conj pos)))
            | LOLLI => SOME(Opr(Infix(Right,4,lolli pos)))
            | NEQ => SOME(Opr(Infix(Non,8,neq pos)))
            | EQ => SOME(Opr(Infix(Non,8,eq pos)))
            | BANG => SOME(Opr(Prefix(10, bang pos)))
            | ID (path,x) => SOME(Atm(ExtSyn.Id(pos,path,x),pos))
            | LAMBDA _ => NONE
            | FORALL _ => NONE
            | EXISTS _ => NONE
            | PERIOD => NONE
            | LPAREN => NONE
            | RPAREN => NONE
            | tok => 
              raise ErrPos(pos,"Unexpected token: " ^ token_to_string tok)))
        val exp_parser = fix
        (fn exp_parser =>
            let
              val parens_parser = 
                  get (fn pos => 
                    maybe (fn LPAREN => SOME() | tok => NONE))
                  >> !! exp_parser <<
                  get (fn pos => 
                    maybe (fn RPAREN => SOME() 
                            | tok => raise ErrPos(pos,"Expected ')', found '"
                                                      ^ token_to_string tok)))
                  wth Atm
              val lambda_parser = 
                  get (fn pos =>
                    maybe (fn (LAMBDA x) => SOME (x,pos) | _ => NONE) 
                        && !! exp_parser wth (Atm o lambda))
              val forall_parser = 
                  get (fn pos => 
                    maybe (fn (FORALL x) => SOME (x,pos) | _ => NONE) 
                        && !! exp_parser wth (Atm o forall))
              val exists_parser = 
                  get (fn pos => 
                    maybe (fn (EXISTS x) => SOME (x,pos) | _ => NONE) 
                        && !! exp_parser wth (Atm o exists))
            in 
              parsefixityadj
                  (alt [fixityitem_parser,
                        parens_parser,
                        lambda_parser,
                        forall_parser,
                        exists_parser])
                  Left
                  (fn ((trm1,pos1),(trm2,pos2)) =>
                      let val pos = Pos.union(pos1,pos2) 
                      in (ExtSyn.App(pos,trm1,trm2),pos) end)
            end wth (fn (trm,pos) => trm))
        val force_period = 
            get (fn pos => 
              maybe (fn PERIOD => SOME() 
                      | tok => 
                        raise ErrPos(pos,"Expected '.', found '"
                                       ^ token_to_string tok)))
        val rule_parser = 
            (* get (fn pos => 
              maybe (fn ID([],x) => SOME(x,pos) | _ => NONE))
            << maybe (fn COLON => SOME() | _ => NONE)
            && *) !! exp_parser << force_period 
                wth (fn (trm,pos') => 
                        ExtSyn.RULE(pos', "-", trm))
        val numparser =
         fn ID([],"*") => SOME(NONE)
          | ID([],id) => 
            (case Int.fromString id of NONE => NONE | SOME i => SOME(SOME i))
          | _ => NONE
        val exec_parser = 
            get (fn pos => 
              maybe (fn PERCENT("exec") => SOME() | _ => NONE)
              >> maybe numparser && exp_parser << force_period 
                wth (fn (n,x) => ExtSyn.EXEC(pos,n,x)))
        val trace_parser = 
            get (fn pos => 
              maybe (fn PERCENT("trace") => SOME() | _ => NONE)
              >> maybe numparser && exp_parser << force_period 
                wth (fn (n,x) => ExtSyn.TRACE(pos,n,x)))
      in alt [exec_parser,trace_parser,rule_parser] end

  fun markstream f fs = 
      let
        val pos0 = Pos.initposex f
        fun mark ("\n",pos) = 
            let val pos' = Pos.nextline pos 
            in
              liveprint "\n";
              (("\n", Pos.union(pos,pos')), pos')
            end
          | mark (c, pos) =
            let val pos' = Pos.nextchar pos
            in
              liveprint c;
              ((c, Pos.union(pos,pos')), pos')
            end
      in StreamUtil.foldstream mark pos0 fs end

  fun stream_to_tokenstream f fs = 
      let 
        val fs1 = markstream f fs
        val fs2 = transform_tok1 fs1
        val fs3 = transform_tok2 fs2
        val fs4 = transform_tok3 fs3 
      in fs4 end

  fun literate_to_tokenstream f fs = 
      let
        val fs0 = markstream f fs
        val fs1 = transform_tok0 fs0
        val fs2 = transform_tok1 fs1
        val fs3 = transform_tok2 fs2
        val fs4 = transform_tok3 fs3 
      in fs4 end

  (* Default is to non-literate code *)
  fun file_to_tokenstream f = 
      case OS.Path.splitBaseExt f of
        {ext=SOME "lolf",...} => 
        literate_to_tokenstream f (StreamUtil.ftoUTF8stream f)
      | _ => stream_to_tokenstream f (StreamUtil.ftoUTF8stream f)

  (* Assumed non-literate code *)
  fun string_to_tokenstream s =
      stream_to_tokenstream "" (StreamUtil.ltostream(UTF8Util.explode s))

(*
  fun readfile f = 
      let
        val fs = StreamUtil.ftoUTF8stream f
        val pos0 = Pos.initposex f
        fun mark ("\n",pos) = 
            let val pos = Pos.nextline pos 
            in (("\n",pos), pos) end
          | mark (c,pos) =
            let val pos = Pos.nextchar pos
            in ((c,pos), pos) end
        val fs1 = StreamUtil.foldstream mark pos0 fs
        val fs2 = transform_tok1 fs1
        val fs3 = transform_tok2 fs2
        val fs4 = transform_tok3 fs3
        fun printtok (tok,pos) = 
            print (Pos.toString pos ^ " - " ^ token_to_string tok ^ "\n") 
        (* val () = Stream.app printtok fs4 *)
      in transform_decl fs4 end
*)
  fun readfile f = raise Match


end
