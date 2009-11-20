signature SIGNAT = sig

  type state = 
       {
        constants : IntSyn.tp MapS.map,
        linear_preds : SetS.set,
        pers_preds : SetS.set,
        rules : IntSyn.rule list,
        linear_rules : IntSyn.neg_prop list,
        saturating_rules : IntSyn.neg_prop list
       }
  val empty : state
  val w'constants : (state * IntSyn.tp MapS.map) -> state
  val w'linear_preds : (state * SetS.set) -> state
  val w'pers_preds : (state * SetS.set) -> state
  val w'rules : (state * IntSyn.rule list) -> state
  val w'linear_rules : (state * IntSyn.neg_prop list) -> state
  val w'saturating_rules : (state * IntSyn.neg_prop list) -> state

end

structure Signat :> SIGNAT = struct

  type state = 
       {constants : IntSyn.tp MapS.map,
        linear_preds : SetS.set,
        pers_preds : SetS.set,
        rules : IntSyn.rule list,
        linear_rules : IntSyn.neg_prop list,
        saturating_rules : IntSyn.neg_prop list}
  val empty  = 
      {constants = MapS.empty, 
       linear_preds = SetS.empty,
       pers_preds = SetS.empty,
       rules = [],
       linear_rules = [],
       saturating_rules = []}

  infix w'constants w'linear_preds w'pers_preds w'rules w'linear_rules w'saturating_rules
  fun (st : state) w'constants constants = 
      {constants        = constants, 
       linear_preds     = #linear_preds st,
       pers_preds       = #pers_preds st,
       rules            = #rules st,
       linear_rules     = #linear_rules st,
       saturating_rules = #saturating_rules st}
  fun (st : state) w'linear_preds linear_preds = 
      {constants        = #constants st, 
       linear_preds     = linear_preds,
       pers_preds       = #pers_preds st,
       rules            = #rules st,
       linear_rules     = #linear_rules st,
       saturating_rules = #saturating_rules st}
  fun (st : state) w'pers_preds pers_preds = 
      {constants        = #constants st, 
       linear_preds     = #linear_preds st,
       pers_preds       = pers_preds,
       rules            = #rules st,
       linear_rules     = #linear_rules st,
       saturating_rules = #saturating_rules st}
  fun (st : state) w'rules rules = 
      {constants        = #constants st, 
       linear_preds     = #linear_preds st,
       pers_preds       = #pers_preds st,
       rules            = rules,
       linear_rules     = #linear_rules st,
       saturating_rules = #saturating_rules st}
  fun (st : state) w'linear_rules linear_rules = 
      {constants        = #constants st, 
       linear_preds     = #linear_preds st,
       pers_preds       = #pers_preds st,
       rules            = #rules st,
       linear_rules     = linear_rules,
       saturating_rules = #saturating_rules st}
  fun (st : state) w'saturating_rules saturating_rules = 
      {constants        = #constants st, 
       linear_preds     = #linear_preds st,
       pers_preds       = #pers_preds st,
       rules            = #rules st,
       linear_rules     = #linear_rules st,
       saturating_rules = saturating_rules}

end
