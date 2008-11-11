functor Terms (Rep : TERM_REP) = struct

  open Lambda
  exception Invariant

  structure HC = HashCons
  structure HS = HashConsString

  datatype table = 
      T of {term_table : ndx HT.hash_table,
            term_array : A.growarray,
            construct_1 : int -> (int * int) option,
            construct_2 : int * (int * int) -> (int * int) option}

  fun newtable c1 c2 =
      T{term_table = HT.mkTable(101, Invariant),
        term_array = A.init 101,
        construct_1 = c1,
        construct_2 = c2}
      

  val strip_to_cell = 
      map (fn RCell cell => cell
            | _ => raise Invariant)

  (* Internalize a closed application, checking for the possibility 
   * of base constants. *)
  fun intern_app (t as T{term_table, term_array, construct_1, construct_2,...},
                  cid, tms) = 
      let 
        val cells = strip_to_cell tms
        val len = length cells
        val baseconst = 
            case cells of 
              [] => construct_1 cid
            | [BaseConst(ty,v)] => construct_2 (cid,(ty,v)) 
            | _ => NONE
      in
        case baseconst of
          SOME const => BaseConst const
        | NONE =>
          let 
            val key = key (RConst(cid, tms))
          in
            case HT.find term_table key of
              SOME ndx => Ndx ndx
            | NONE =>
              let
                val next = A.length term_array
              in
                A.append term_array (IConst(cid,cells));
                HT.insert term_table (key, next);
                Ndx next
              end
          end
      end

  (* Internalize a closed Skolem pointer *)
  fun intern_var (t as T{term_table, term_array,...}, ndx, tms) = 
      let
        val key = key (RVar(ndx, tms))
        val cells = strip_to_cell tms
      in
        case HT.find term_table key of
          SOME ndx => Ndx ndx
        | NONE =>
          let 
            val next = A.length term_array
          in
            A.append term_array (IVar(ndx, cells));
            HT.insert term_table (key, next);
            Ndx next
          end
      end

  (* Internalize a closed lambda *)
  fun intern_lam (t as T{term_table, term_array,...}, ty, tm) = 
      let 
        val key = key(RLam(ty,tm))
      in
        case HT.find term_table key of
          SOME ndx => Ndx ndx
        | NONE => 
          let 
            val next = A.length term_array
          in
            A.append term_array (ILam(ty, Void));
            HT.insert term_table (key, next);

            (* We know that this expression has one free variable. The
             * next round of internalization substitutes for this free 
             * variable, and so we can expect that it will fully internalize.
             * We can then update our lambda with knowledge of its body. *)
            case intern(t, tm, 1, next)  of
              (RCell cell,0) => A.update term_array next (ILam(ty, cell))
            | _ => raise Invariant;

            Ndx next
          end
      end

  (* intern(t,tm,i,ndx) = (rtm, free)
   * 
   * Takes table info and a term and returns a reduced term and an integer
   * describing the "deepest" free variable. Maintains the invariant that
   * if free = 0, then rtm = RCell(cell). 
   * 
   * Also attempts to substitute the Skolem pointer ndx for the bound variable
   * i if possible. If the function is being used to internalize a closed
   * term, just call with i = 1 and ndx = void. 
   *)
  and intern (t as T{...}, tm, i, ndx)  = 
      let 
        fun intern_chain (tm, (rtms, free)) = 
            let val (rtm, free') = intern (t, tm, i, ndx) in
              (rtm :: rtms, Int.max(free, free'))
            end
        fun args (TBase cid) = []
          | args (TArrow(t1,t2)) = t1 :: args t2
      in
        case tm of
          RLam(ty,tm) => 
          let val (rtm, free) = intern(t, tm, i+1, ndx) in
            if free <= 1 
            then (RCell(intern_lam(t, ty, tm)), 0)
            else (RLam(ty, rtm), free - 1)
          end
        | RConst(cid, tms) => 
          let val (rtms, free) = foldl intern_chain ([], 0) tms in
            if free = 0
            then (RCell(intern_app(t,cid,rtms)), 0)
            else (RConst(cid, rtms), free)
          end
        | RVar(ndx', tms) =>
          let val (rtms, free) = foldl intern_chain ([], 0) tms in
            if free = 0
            then (RCell(intern_var(t,ndx',rtms)), 0)
            else (RVar(ndx', rtms), free)
          end
        | RFVar(j, tms) =>
          let val (rtms, free) = foldl intern_chain ([], 0) tms in
            if i = j andalso free = 0
            then (RCell(intern_var(t,ndx,rtms)), 0)
            else if i = j
            then (RVar(ndx, rtms), free)
            else (RFVar(j, rtms), Int.max(free,j))
          end
        | RCell cell => (RCell cell, 0)
      end

  exception Internalize
  fun internalize t tm = 
      case intern(t,tm,1,void) of
        (RCell cell,_) => cell
      | _ => raise Internalize
      
  type base_const = int * int
  type ndx = ndx
  type term = red_term
  type intern_term = cell
  fun RLam x = RLam x
  fun RConst x = RConst x
  fun RFVar x = RFVar x
  fun RBase x = RCell(BaseConst x)


end
