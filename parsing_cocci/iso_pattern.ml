(* Potential problem: offset of mcode is not updated when an iso is
instantiated, implying that a term may end up with many mcodes with the
same offset.  On the other hand, at the moment offset only seems to be used
before this phase.  Furthermore add_dot_binding relies on the offset to
remain the same between matching an iso and instantiating it with bindings. *)

(* --------------------------------------------------------------------- *)
(* match a SmPL expression against a SmPL abstract syntax tree,
either - or + *)

module Ast = Ast_cocci
module Ast0 = Ast0_cocci
module V0 = Visitor_ast0

let current_rule = ref ""

(* --------------------------------------------------------------------- *)

type isomorphism =
    Ast_cocci.metavar list * Ast0_cocci.anything list list * string (* name *)

let strip_info =
  let mcode (term,_,_,_) = (term,Ast0.NONE,Ast0.default_info(),Ast0.PLUS) in
  let donothing r k e =
    let (term,info,index,mc,ty,dots,arg,test,is_iso) = k e in
    (term,Ast0.default_info(),ref 0,ref Ast0.PLUS,ref None,Ast0.NoDots,
     false,test,None) in
  V0.rebuilder
    mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode
    mcode
    donothing donothing donothing donothing donothing donothing
    donothing donothing donothing donothing donothing donothing donothing
    donothing donothing

let anything_equal = function
    (Ast0.DotsExprTag(d1),Ast0.DotsExprTag(d2)) ->
      failwith "not a possible variable binding" (*not sure why these are pbs*)
  | (Ast0.DotsInitTag(d1),Ast0.DotsInitTag(d2)) ->
      failwith "not a possible variable binding"
  | (Ast0.DotsParamTag(d1),Ast0.DotsParamTag(d2)) ->
      failwith "not a possible variable binding"
  | (Ast0.DotsStmtTag(d1),Ast0.DotsStmtTag(d2)) ->
      (strip_info.V0.rebuilder_statement_dots d1) =
      (strip_info.V0.rebuilder_statement_dots d2)
  | (Ast0.DotsDeclTag(d1),Ast0.DotsDeclTag(d2)) ->
      failwith "not a possible variable binding"
  | (Ast0.DotsCaseTag(d1),Ast0.DotsCaseTag(d2)) ->
      failwith "not a possible variable binding"
  | (Ast0.IdentTag(d1),Ast0.IdentTag(d2)) ->
      (strip_info.V0.rebuilder_ident d1) = (strip_info.V0.rebuilder_ident d2)
  | (Ast0.ExprTag(d1),Ast0.ExprTag(d2)) ->
      (strip_info.V0.rebuilder_expression d1) =
      (strip_info.V0.rebuilder_expression d2)
  | (Ast0.ArgExprTag(_),_) | (_,Ast0.ArgExprTag(_)) ->
      failwith "not possible - only in isos1"
  | (Ast0.TestExprTag(_),_) | (_,Ast0.TestExprTag(_)) ->
      failwith "not possible - only in isos1"
  | (Ast0.TypeCTag(d1),Ast0.TypeCTag(d2)) ->
      (strip_info.V0.rebuilder_typeC d1) =
      (strip_info.V0.rebuilder_typeC d2)
  | (Ast0.InitTag(d1),Ast0.InitTag(d2)) ->
      (strip_info.V0.rebuilder_initialiser d1) =
      (strip_info.V0.rebuilder_initialiser d2)
  | (Ast0.ParamTag(d1),Ast0.ParamTag(d2)) ->
      (strip_info.V0.rebuilder_parameter d1) =
      (strip_info.V0.rebuilder_parameter d2)
  | (Ast0.DeclTag(d1),Ast0.DeclTag(d2)) ->
      (strip_info.V0.rebuilder_declaration d1) =
      (strip_info.V0.rebuilder_declaration d2)
  | (Ast0.StmtTag(d1),Ast0.StmtTag(d2)) ->
      (strip_info.V0.rebuilder_statement d1) =
      (strip_info.V0.rebuilder_statement d2)
  | (Ast0.CaseLineTag(d1),Ast0.CaseLineTag(d2)) ->
      (strip_info.V0.rebuilder_case_line d1) =
      (strip_info.V0.rebuilder_case_line d2)
  | (Ast0.TopTag(d1),Ast0.TopTag(d2)) ->
      (strip_info.V0.rebuilder_top_level d1) =
      (strip_info.V0.rebuilder_top_level d2)
  | (Ast0.AnyTag,_) | (_,Ast0.AnyTag) ->
      failwith "anytag only for isos within iso phase"
  | _ -> false

let term (var1,_,_,_) = var1
let dot_term (var1,_,info,_) = ("", var1 ^ (string_of_int info.Ast0.offset))


type reason =
    NotPure of Ast0.pure * (string * string) * Ast0.anything
  | NotPureLength of (string * string)
  | ContextRequired of Ast0.anything
  | NonMatch
  | Braces of Ast0.statement

let interpret_reason name line reason printer =
  Printf.printf
    "warning: iso %s does not match the code below on line %d\n" name line;
  printer(); Format.print_newline();
  match reason with
    NotPure(Ast0.Pure,(_,var),nonpure) ->
      Printf.printf
	"pure metavariable %s is matched against the following nonpure code:\n"
	var;
      Unparse_ast0.unparse_anything nonpure
  | NotPure(Ast0.Context,(_,var),nonpure) ->
      Printf.printf
	"context metavariable %s is matched against the following\nnoncontext code:\n"
	var;
      Unparse_ast0.unparse_anything nonpure
  | NotPure(Ast0.PureContext,(_,var),nonpure) ->
      Printf.printf
	"pure context metavariable %s is matched against the following\nnonpure or noncontext code:\n"
	var;
      Unparse_ast0.unparse_anything nonpure
  | NotPureLength((_,var)) ->
      Printf.printf
	"pure metavariable %s is matched against too much or too little code\n"
	var;
  | ContextRequired(term) ->
      Printf.printf
	"the following code matched is not uniformly minus or context,\nor contains a disjunction:\n";
      Unparse_ast0.unparse_anything term
  | Braces(s) ->
      Printf.printf "braces must be all minus (plus code allowed) or all\ncontext (plus code not allowed in the body) to match:\n";
      Unparse_ast0.statement "" s;
      Format.print_newline()
  | _ -> failwith "not possible"

type 'a either = OK of 'a | Fail of reason

let add_binding var exp bindings =
  let var = term var in
  let attempt bindings =
    try
      let cur = List.assoc var bindings in
      if anything_equal(exp,cur) then [bindings] else []
    with Not_found -> [((var,exp)::bindings)] in
  match List.concat(List.map attempt bindings) with
    [] -> Fail NonMatch
  | x -> OK x

let add_dot_binding var exp bindings =
  let var = dot_term var in
  let attempt bindings =
    try
      let cur = List.assoc var bindings in
      if anything_equal(exp,cur) then [bindings] else []
    with Not_found -> [((var,exp)::bindings)] in
  match List.concat(List.map attempt bindings) with
    [] -> Fail NonMatch
  | x -> OK x

let rec nub ls =
  match ls with
    [] -> []
  | (x::xs) when (List.mem x xs) -> nub xs
  | (x::xs) -> x::(nub xs)

(* --------------------------------------------------------------------- *)

let init_env = [[]]

let debug str m binding =
  let res = m binding in
  (match res with
    None -> Printf.printf "%s: failed\n" str
  | Some binding ->
      List.iter
	(function binding ->
	  Printf.printf "%s: %s\n" str
	    (String.concat " " (List.map (function (x,_) -> x) binding)))
	binding);
  res

let conjunct_bindings
    (m1 : 'binding -> 'binding either)
    (m2 : 'binding -> 'binding either)
    (binding : 'binding) : 'binding either =
  match m1 binding with Fail(reason) -> Fail(reason) | OK binding -> m2 binding

let mcode_equal (x,_,_,_) (y,_,_,_) = x = y

let return b binding = if b then OK binding else Fail NonMatch
let return_false reason binding = Fail reason

let match_option f t1 t2 =
  match (t1,t2) with
    (Some t1, Some t2) -> f t1 t2
  | (None, None) -> return true
  | _ -> return false

let bool_match_option f t1 t2 =
  match (t1,t2) with
    (Some t1, Some t2) -> f t1 t2
  | (None, None) -> true
  | _ -> false

(* context_required is for the example
   if (
+      (int * )
       x == NULL)
  where we can't change x == NULL to eg NULL == x.  So there can either be
  nothing attached to the root or the term has to be all removed.
  if would be nice if we knew more about the relationship between the - and +
  code, because in the case where the + code is a separate statement in a
  sequence, this is not a problem.  Perhaps something could be done in
  insert_plus *)
let is_context e =
  match Ast0.get_mcodekind e with
    Ast0.CONTEXT(cell) -> true
  | _ -> false

(* needs a special case when there is a Disj or an empty DOTS
   the following stops at the statement level, and gives true if one
   statement is replaced by another *)
let rec is_pure_context s =
  match Ast0.get_mcodekind s with
    Ast0.CONTEXT(mc) ->
      (match !mc with
	(Ast.NOTHING,_,_) -> true
      |	_ -> false)
  | Ast0.MINUS(mc) ->
      (match !mc with
	(* do better for the common case of replacing a stmt by another one *)
	([[Ast.StatementTag(s)]],_) ->
	  (match Ast.unwrap s with
	    Ast.IfThen(_,_,_) -> false (* potentially dangerous *)
	  | _ -> true)
      |	(_,_) -> false)
  | _ ->
      (match Ast0.unwrap s with
	Ast0.Disj(starter,statement_dots_list,mids,ender) ->
	  List.for_all
	    (function x ->
	      match Ast0.undots x with
		[s] -> is_pure_context s
	      |	_ -> false (* could we do better? *))
	    statement_dots_list
      |	_ -> false)

let is_minus e =
  match Ast0.get_mcodekind e with Ast0.MINUS(cell) -> true | _ -> false

let match_list matcher is_list_matcher do_list_match la lb =
  let rec loop = function
      ([],[]) -> return true
    | ([x],lb) when is_list_matcher x -> do_list_match x lb
    | (x::xs,y::ys) -> conjunct_bindings (matcher x y) (loop (xs,ys))
    | _ -> return false in
  loop (la,lb)

let match_maker checks_needed context_required whencode_allowed =

  let match_dots matcher is_list_matcher do_list_match d1 d2 =
    match (Ast0.unwrap d1, Ast0.unwrap d2) with
      (Ast0.DOTS(la),Ast0.DOTS(lb))
    | (Ast0.CIRCLES(la),Ast0.CIRCLES(lb))
    | (Ast0.STARS(la),Ast0.STARS(lb)) ->
	match_list matcher is_list_matcher (do_list_match d2) la lb
    | _ -> return false in

  let is_elist_matcher el =
    match Ast0.unwrap el with Ast0.MetaExprList(_,_,_) -> true | _ -> false in

  let is_plist_matcher pl =
    match Ast0.unwrap pl with Ast0.MetaParamList(_,_,_) -> true | _ -> false in

  let is_slist_matcher pl =
    match Ast0.unwrap pl with Ast0.MetaStmtList(_,_) -> true | _ -> false in

  let no_list _ = false in

  let build_dots pattern data =
    match Ast0.unwrap pattern with
      Ast0.DOTS(_) -> Ast0.rewrap pattern (Ast0.DOTS(data))
    | Ast0.CIRCLES(_) -> Ast0.rewrap pattern (Ast0.CIRCLES(data))
    | Ast0.STARS(_) -> Ast0.rewrap pattern (Ast0.STARS(data)) in

  let pure_sp_code =
    let bind = Ast0.lub_pure in
    let option_default = Ast0.Context in
    let pure_mcodekind = function
	Ast0.CONTEXT(mc) ->
	  (match !mc with
	    (Ast.NOTHING,_,_) -> Ast0.PureContext
	  | _ -> Ast0.Context)
      | Ast0.MINUS(mc) ->
	  (match !mc with ([],_) -> Ast0.Pure | _ ->  Ast0.Impure)
      | _ -> Ast0.Impure in
    let donothing r k e =
      bind (pure_mcodekind (Ast0.get_mcodekind e)) (k e) in

    let mcode m = pure_mcodekind (Ast0.get_mcode_mcodekind m) in

    (* a case for everything that has a metavariable *)
    (* pure is supposed to match only unitary metavars, not anything that
       contains only unitary metavars *)
    let ident r k i =
      bind (bind (pure_mcodekind (Ast0.get_mcodekind i)) (k i))
	(match Ast0.unwrap i with
	  Ast0.MetaId(name,pure) | Ast0.MetaFunc(name,pure)
	| Ast0.MetaLocalFunc(name,pure) -> pure
	| _ -> Ast0.Impure) in

    let expression r k e =
      bind (bind (pure_mcodekind (Ast0.get_mcodekind e)) (k e))
	(match Ast0.unwrap e with
	  Ast0.MetaErr(name,pure) 
	| Ast0.MetaExpr(name,_,_,pure) | Ast0.MetaExprList(name,_,pure) -> pure
	| _ -> Ast0.Impure) in

    let typeC r k t =
      bind (bind (pure_mcodekind (Ast0.get_mcodekind t)) (k t))
	(match Ast0.unwrap t with
	  Ast0.MetaType(name,pure) -> pure
	| _ -> Ast0.Impure) in

    let param r k p =
      bind (bind (pure_mcodekind (Ast0.get_mcodekind p)) (k p))
	(match Ast0.unwrap p with
	  Ast0.MetaParam(name,pure) | Ast0.MetaParamList(name,_,pure) -> pure
	| _ -> Ast0.Impure) in

    let stmt r k s =
      bind (bind (pure_mcodekind (Ast0.get_mcodekind s)) (k s))
	(match Ast0.unwrap s with
	  Ast0.MetaStmt(name,pure) | Ast0.MetaStmtList(name,pure) -> pure
	| _ -> Ast0.Impure) in

    V0.combiner bind option_default 
      mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode
      mcode
      donothing donothing donothing donothing donothing donothing
      ident expression typeC donothing param donothing stmt donothing
      donothing in

  let add_pure_list_binding name pure is_pure builder1 builder2 lst =
    match (checks_needed,pure) with
      (true,Ast0.Pure) | (true,Ast0.Context) | (true,Ast0.PureContext) ->
	(match lst with
	  [x] ->
	    if (Ast0.lub_pure (is_pure x) pure) = pure
	    then add_binding name (builder1 lst)
	    else return_false (NotPure (pure,term name,builder1 lst))
	| _ -> return_false (NotPureLength (term name)))
    | (false,_) | (_,Ast0.Impure) -> add_binding name (builder2 lst) in

  let add_pure_binding name pure is_pure builder x =
    match (checks_needed,pure) with
      (true,Ast0.Pure) | (true,Ast0.Context) | (true,Ast0.PureContext) ->
	if (Ast0.lub_pure (is_pure x) pure) = pure
	then add_binding name (builder x)
	else return_false (NotPure (pure,term name, builder x))
    | (false,_) | (_,Ast0.Impure) ->  add_binding name (builder x) in

  let do_elist_match builder el lst =
    match Ast0.unwrap el with
      Ast0.MetaExprList(name,lenname,pure) ->
        (*how to handle lenname? should it be an option type and always None?*)
	failwith "expr list pattern not supported in iso"
	(*add_pure_list_binding name pure
	  pure_sp_code.V0.combiner_expression
	  (function lst -> Ast0.ExprTag(List.hd lst))
	  (function lst -> Ast0.DotsExprTag(build_dots builder lst))
	  lst*)
    | _ -> failwith "not possible" in

  let do_plist_match builder pl lst =
    match Ast0.unwrap pl with
      Ast0.MetaParamList(name,lename,pure) ->
	failwith "param list pattern not supported in iso"
	(*add_pure_list_binding name pure
	  pure_sp_code.V0.combiner_parameter
	  (function lst -> Ast0.ParamTag(List.hd lst))
	  (function lst -> Ast0.DotsParamTag(build_dots builder lst))
	  lst*)
    | _ -> failwith "not possible" in

  let do_slist_match builder sl lst =
    match Ast0.unwrap sl with
      Ast0.MetaStmtList(name,pure) ->
	add_pure_list_binding name pure
	  pure_sp_code.V0.combiner_statement
	  (function lst -> Ast0.StmtTag(List.hd lst))
	  (function lst -> Ast0.DotsStmtTag(build_dots builder lst))
	  lst
    | _ -> failwith "not possible" in

  let do_nolist_match _ _ = failwith "not possible" in

  let rec match_ident pattern id =
    match Ast0.unwrap pattern with
      Ast0.MetaId(name,pure) ->
	add_pure_binding name pure pure_sp_code.V0.combiner_ident
	  (function id -> Ast0.IdentTag id) id
    | Ast0.MetaFunc(name,pure) -> failwith "metafunc not supported"
    | Ast0.MetaLocalFunc(name,pure) -> failwith "metalocalfunc not supported"
    | up ->
	if not(checks_needed) or not(context_required) or is_context id
	then
	  match (up,Ast0.unwrap id) with
	    (Ast0.Id(namea),Ast0.Id(nameb)) -> return (mcode_equal namea nameb)
	  | (Ast0.OptIdent(ida),Ast0.OptIdent(idb))
	  | (Ast0.UniqueIdent(ida),Ast0.UniqueIdent(idb)) ->
	      match_ident ida idb
	  | (_,Ast0.OptIdent(idb))
	  | (_,Ast0.UniqueIdent(idb)) -> match_ident pattern idb
	  | _ -> return false
	else return_false (ContextRequired (Ast0.IdentTag id)) in

  (* should we do something about matching metavars against ...? *)
  let rec match_expr pattern expr =
    match Ast0.unwrap pattern with
      Ast0.MetaExpr(name,ty,form,pure) ->
	let form_ok =
	  match (form,expr) with
	    (Ast.ANY,_) -> true
	  | (Ast.CONST,e) ->
	      let rec matches e =
		match Ast0.unwrap e with
		  Ast0.Constant(c) -> true
		| Ast0.Cast(lp,ty,rp,e) -> matches e
		| Ast0.SizeOfExpr(se,exp) -> true
		| Ast0.SizeOfType(se,lp,ty,rp) -> true
		| Ast0.MetaExpr(nm,_,Ast.CONST,p) ->
		    (Ast0.lub_pure p pure) = pure
		| _ -> false in
	      matches e
	  | (Ast.ID,e) ->
	      let rec matches e =
		match Ast0.unwrap e with
		  Ast0.Ident(c) -> true
		| Ast0.Cast(lp,ty,rp,e) -> matches e
		| Ast0.MetaExpr(nm,_,Ast.ID,p) -> (Ast0.lub_pure p pure) = pure
		| _ -> false in
	      matches e in
	if form_ok
	then
	  match ty with
	    Some ts ->
	      if List.exists
		  (function Type_cocci.MetaType(_,_,_) -> true | _ -> false)
		  ts
	      then
		(match ts with
		  [Type_cocci.MetaType(tyname,_,_)] ->
		    let expty =
		      match (Ast0.unwrap expr,Ast0.get_type expr) with
		  (* easier than updating type inferencer to manage multiple
		     types *)
			(Ast0.MetaExpr(_,Some tts,_,_),_) -> Some tts
		      | (_,Some ty) -> Some [ty]
		      | _ -> None in
		    (match expty with
		      Some expty ->
			let tyname = Ast0.rewrap_mcode name tyname in
			(function bindings ->
			  let attempts =
			    List.map
			      (function expty ->
				(try
				  conjunct_bindings
				    (add_pure_binding tyname Ast0.Impure
				       (function _ -> Ast0.Impure)
				       (function ty -> Ast0.TypeCTag ty)
				       (Ast0.rewrap expr
					  (Ast0.reverse_type expty)))
				    (add_pure_binding name pure
				       pure_sp_code.V0.combiner_expression
				       (function expr -> Ast0.ExprTag expr)
				       expr)
				    bindings
				with Ast0.TyConv ->
				  Printf.printf "warning: unconvertible type";
				  return false bindings))
			      expty in
			  match
			    List.concat
			      (List.map (function Fail _ -> [] | OK x -> x)
				 attempts)
			  with
			    [] -> Fail NonMatch
			  | x -> OK x)
		    |	_ ->
		  (*Printf.printf
		     "warning: type metavar can only match one type";*)
			return false)
		| _ ->
		    failwith "mixture of metatype and other types not supported")
	      else
		let expty = Ast0.get_type expr in
		if List.exists (function t -> Type_cocci.compatible t expty) ts
		then
		  add_pure_binding name pure pure_sp_code.V0.combiner_expression
		    (function expr -> Ast0.ExprTag expr)
		    expr
		else return false
	  | None ->
	      add_pure_binding name pure pure_sp_code.V0.combiner_expression
		(function expr -> Ast0.ExprTag expr)
		expr
	else return false
    | Ast0.MetaErr(namea,pure) -> failwith "metaerr not supported"
    | Ast0.MetaExprList(_,_,_) -> failwith "metaexprlist not supported"
    | up ->
	if not(checks_needed) or not(context_required) or is_context expr
	then
	  match (up,Ast0.unwrap expr) with
	    (Ast0.Ident(ida),Ast0.Ident(idb)) ->
	      match_ident ida idb
	  | (Ast0.Constant(consta),Ast0.Constant(constb)) ->
	      return (mcode_equal consta constb)
	  | (Ast0.FunCall(fna,_,argsa,_),Ast0.FunCall(fnb,lp,argsb,rp)) ->
	      conjunct_bindings (match_expr fna fnb)
		(match_dots match_expr is_elist_matcher do_elist_match
		   argsa argsb)
	  | (Ast0.Assignment(lefta,opa,righta,_),
	     Ast0.Assignment(leftb,opb,rightb,_)) ->
	       if mcode_equal opa opb
	       then
		 conjunct_bindings (match_expr lefta leftb)
		   (match_expr righta rightb)
	       else return false
	  | (Ast0.CondExpr(exp1a,_,exp2a,_,exp3a),
	     Ast0.CondExpr(exp1b,lp,exp2b,rp,exp3b)) ->
	       conjunct_bindings (match_expr exp1a exp1b)
		 (conjunct_bindings (match_option match_expr exp2a exp2b)
		    (match_expr exp3a exp3b))
	  | (Ast0.Postfix(expa,opa),Ast0.Postfix(expb,opb)) ->
	      if mcode_equal opa opb
	      then match_expr expa expb
	      else return false
	  | (Ast0.Infix(expa,opa),Ast0.Infix(expb,opb)) ->
	      if mcode_equal opa opb
	      then match_expr expa expb
	      else return false
	  | (Ast0.Unary(expa,opa),Ast0.Unary(expb,opb)) ->
	      if mcode_equal opa opb
	      then match_expr expa expb
	      else return false
	  | (Ast0.Binary(lefta,opa,righta),Ast0.Binary(leftb,opb,rightb)) ->
	      if mcode_equal opa opb
	      then
		conjunct_bindings (match_expr lefta leftb)
		  (match_expr righta rightb)
	      else return false
	  | (Ast0.Paren(_,expa,_),Ast0.Paren(lp,expb,rp)) ->
	      match_expr expa expb
	  | (Ast0.ArrayAccess(exp1a,_,exp2a,_),
	     Ast0.ArrayAccess(exp1b,lb,exp2b,rb)) ->
	       conjunct_bindings (match_expr exp1a exp1b)
		 (match_expr exp2a exp2b)
	  | (Ast0.RecordAccess(expa,_,fielda),
	     Ast0.RecordAccess(expb,op,fieldb))
	  | (Ast0.RecordPtAccess(expa,_,fielda),
	     Ast0.RecordPtAccess(expb,op,fieldb)) ->
	       conjunct_bindings
		 (match_expr expa expb)
		 (match_ident fielda fieldb)
	  | (Ast0.Cast(_,tya,_,expa),Ast0.Cast(lp,tyb,rp,expb)) ->
	      conjunct_bindings (match_typeC tya tyb)
		(match_expr expa expb)
	  | (Ast0.SizeOfExpr(_,expa),Ast0.SizeOfExpr(szf,expb)) ->
	      match_expr expa expb
	  | (Ast0.SizeOfType(_,_,tya,_),Ast0.SizeOfType(szf,lp,tyb,rp)) ->
	      match_typeC tya tyb
	  | (Ast0.TypeExp(tya),Ast0.TypeExp(tyb)) ->
	      match_typeC tya tyb
	  | (Ast0.EComma(_),Ast0.EComma(cm)) -> return true
	  | (Ast0.DisjExpr(_,expsa,_,_),_) ->
	      failwith "not allowed in the pattern of an isomorphism"
	  | (Ast0.NestExpr(_,exp_dotsa,_,_,_),_) ->
	      failwith "not allowed in the pattern of an isomorphism"
	  | (Ast0.Edots(_,None),Ast0.Edots(_,None))
	  | (Ast0.Ecircles(_,None),Ast0.Ecircles(_,None))
	  | (Ast0.Estars(_,None),Ast0.Estars(_,None)) -> return true
	  | (Ast0.Edots(ed,None),Ast0.Edots(_,Some wc))
	  | (Ast0.Ecircles(ed,None),Ast0.Ecircles(_,Some wc))
	  | (Ast0.Estars(ed,None),Ast0.Estars(_,Some wc)) ->
	    (* hope that mcode of edots is unique somehow *)
	      let (edots_whencode_allowed,_,_) = whencode_allowed in
	      if edots_whencode_allowed
	      then add_dot_binding ed (Ast0.ExprTag wc)
	      else
		(Printf.printf "warning: not applying iso because of whencode";
		 return false)
	  | (Ast0.Edots(_,Some _),_) | (Ast0.Ecircles(_,Some _),_)
	  | (Ast0.Estars(_,Some _),_) ->
	      failwith "whencode not allowed in a pattern1"
	  | (Ast0.OptExp(expa),Ast0.OptExp(expb))
	  | (Ast0.UniqueExp(expa),Ast0.UniqueExp(expb)) -> match_expr expa expb
	  | (_,Ast0.OptExp(expb))
	  | (_,Ast0.UniqueExp(expb)) -> match_expr pattern expb
	  | _ -> return false
	else return_false (ContextRequired (Ast0.ExprTag expr))
	    
(* the special case for function types prevents the eg T X; -> T X = E; iso
   from applying, which doesn't seem very relevant, but it also avoids a
   mysterious bug that is obtained with eg int attach(...); *)
  and match_typeC pattern t =
    match Ast0.unwrap pattern with
      Ast0.MetaType(name,pure) ->
	(match Ast0.unwrap t with
	  Ast0.FunctionType(tya,lp1a,paramsa,rp1a) -> return false
	| _ ->
	    add_pure_binding name pure pure_sp_code.V0.combiner_typeC
	      (function ty -> Ast0.TypeCTag ty)
	      t)
    | up ->
	if not(checks_needed) or not(context_required) or is_context t
	then
	  match (up,Ast0.unwrap t) with
	    (Ast0.ConstVol(cva,tya),Ast0.ConstVol(cvb,tyb)) ->
	      if mcode_equal cva cvb
	      then match_typeC tya tyb
	      else return false
	  | (Ast0.BaseType(tya,signa),Ast0.BaseType(tyb,signb)) ->
	      return (mcode_equal tya tyb &&
		      bool_match_option mcode_equal signa signb)
	  | (Ast0.ImplicitInt(signa),Ast0.ImplicitInt(signb)) ->
	      return (mcode_equal signa signb)
	  | (Ast0.Pointer(tya,_),Ast0.Pointer(tyb,star)) -> match_typeC tya tyb
	  | (Ast0.FunctionPointer(tya,lp1a,stara,rp1a,lp2a,paramsa,rp2a),
	     Ast0.FunctionPointer(tyb,lp1b,starb,rp1b,lp2b,paramsb,rp2b)) ->
	       conjunct_bindings (match_typeC tya tyb)
		 (match_dots match_param is_plist_matcher do_plist_match
		    paramsa paramsb)
	  | (Ast0.FunctionType(tya,lp1a,paramsa,rp1a),
	     Ast0.FunctionType(tyb,lp1b,paramsb,rp1b)) ->
	       conjunct_bindings (match_option match_typeC tya tyb)
		 (match_dots match_param is_plist_matcher do_plist_match
		    paramsa paramsb)
	  | (Ast0.Array(tya,_,sizea,_),Ast0.Array(tyb,lb,sizeb,rb)) ->
	      conjunct_bindings (match_typeC tya tyb)
		(match_option match_expr sizea sizeb)
	  | (Ast0.StructUnionName(kinda,Some namea),
	     Ast0.StructUnionName(kindb,Some nameb)) ->
	       if mcode_equal kinda kindb
	       then match_ident namea nameb
	       else return false
	  | (Ast0.StructUnionDef(tya,_,declsa,_),
	     Ast0.StructUnionDef(tyb,_,declsb,_)) ->
	       conjunct_bindings
		 (match_typeC tya tyb)
		 (match_dots match_decl no_list do_nolist_match declsa declsb)
	  | (Ast0.TypeName(namea),Ast0.TypeName(nameb)) ->
	      return (mcode_equal namea nameb)
	  | (Ast0.DisjType(_,typesa,_,_),Ast0.DisjType(_,typesb,_,_)) ->
	      failwith "not allowed in the pattern of an isomorphism"
	  | (Ast0.OptType(tya),Ast0.OptType(tyb))
	  | (Ast0.UniqueType(tya),Ast0.UniqueType(tyb)) -> match_typeC tya tyb
	  | (_,Ast0.OptType(tyb))
	  | (_,Ast0.UniqueType(tyb)) -> match_typeC pattern tyb
	  | _ -> return false
	else return_false (ContextRequired (Ast0.TypeCTag t))
	    
  and match_decl pattern d =
    if not(checks_needed) or not(context_required) or is_context d
    then
      match (Ast0.unwrap pattern,Ast0.unwrap d) with
	(Ast0.Init(stga,tya,ida,_,inia,_),Ast0.Init(stgb,tyb,idb,_,inib,_)) ->
	  if bool_match_option mcode_equal stga stgb
	  then
	    conjunct_bindings (match_typeC tya tyb)
	      (conjunct_bindings (match_ident ida idb) (match_init inia inib))
	  else return false
      | (Ast0.UnInit(stga,tya,ida,_),Ast0.UnInit(stgb,tyb,idb,_)) ->
	  if bool_match_option mcode_equal stga stgb
	  then conjunct_bindings (match_typeC tya tyb) (match_ident ida idb)
	  else return false
      | (Ast0.MacroDecl(namea,_,argsa,_,_),
	 Ast0.MacroDecl(nameb,_,argsb,_,_)) ->
	   if mcode_equal namea nameb
	   then
	     match_dots match_expr is_elist_matcher do_elist_match
	       argsa argsb
	   else return false
      | (Ast0.TyDecl(tya,_),Ast0.TyDecl(tyb,_)) -> match_typeC tya tyb
      | (Ast0.Typedef(stga,tya,ida,_),Ast0.Typedef(stgb,tyb,idb,_)) ->
	  conjunct_bindings (match_typeC tya tyb) (match_typeC ida idb)
      | (Ast0.DisjDecl(_,declsa,_,_),Ast0.DisjDecl(_,declsb,_,_)) ->
	  failwith "not allowed in the pattern of an isomorphism"
      | (Ast0.Ddots(_,None),Ast0.Ddots(_,None)) -> return true
      |	(Ast0.Ddots(dd,None),Ast0.Ddots(_,Some wc)) ->
	    (* hope that mcode of ddots is unique somehow *)
	  let (ddots_whencode_allowed,_,_) = whencode_allowed in
	  if ddots_whencode_allowed
	  then add_dot_binding dd (Ast0.DeclTag wc)
	  else
	    (Printf.printf "warning: not applying iso because of whencode";
	     return false)
      | (Ast0.Ddots(_,Some _),_) ->
	  failwith "whencode not allowed in a pattern1"
	    
      | (Ast0.OptDecl(decla),Ast0.OptDecl(declb))
      | (Ast0.UniqueDecl(decla),Ast0.UniqueDecl(declb)) ->
	  match_decl decla declb
      | (_,Ast0.OptDecl(declb))
      | (_,Ast0.UniqueDecl(declb)) -> match_decl pattern declb
      | _ -> return false
    else return_false (ContextRequired (Ast0.DeclTag d))
	
  and match_init pattern i =
    if not(checks_needed) or not(context_required) or is_context i
    then
      match (Ast0.unwrap pattern,Ast0.unwrap i) with
	(Ast0.InitExpr(expa),Ast0.InitExpr(expb)) ->
	  match_expr expa expb
      | (Ast0.InitList(_,initlista,_),Ast0.InitList(_,initlistb,_)) ->
	  match_dots match_init no_list do_nolist_match initlista initlistb
      | (Ast0.InitGccDotName(_,namea,_,inia),
	 Ast0.InitGccDotName(_,nameb,_,inib)) ->
	   conjunct_bindings (match_ident namea nameb) (match_init inia inib)
      | (Ast0.InitGccName(namea,_,inia),Ast0.InitGccName(nameb,_,inib)) ->
	  conjunct_bindings (match_ident namea nameb) (match_init inia inib)
      | (Ast0.InitGccIndex(_,expa,_,_,inia),
	 Ast0.InitGccIndex(_,expb,_,_,inib)) ->
	   conjunct_bindings (match_expr expa expb) (match_init inia inib)
      | (Ast0.InitGccRange(_,exp1a,_,exp2a,_,_,inia),
	 Ast0.InitGccRange(_,exp1b,_,exp2b,_,_,inib)) ->
	   conjunct_bindings (match_expr exp1a exp1b)
	     (conjunct_bindings (match_expr exp2a exp2b) (match_init inia inib))
      | (Ast0.IComma(_),Ast0.IComma(_)) -> return true
      | (Ast0.Idots(_,None),Ast0.Idots(_,None)) -> return true
      | (Ast0.Idots(id,None),Ast0.Idots(_,Some wc)) ->
	  (* hope that mcode of edots is unique somehow *)
	  let (_,idots_whencode_allowed,_) = whencode_allowed in
	  if idots_whencode_allowed
	  then add_dot_binding id (Ast0.InitTag wc)
	  else
	    (Printf.printf "warning: not applying iso because of whencode";
	     return false)
      | (Ast0.Idots(_,Some _),_) ->
	  failwith "whencode not allowed in a pattern2"
      | (Ast0.OptIni(ia),Ast0.OptIni(ib))
      | (Ast0.UniqueIni(ia),Ast0.UniqueIni(ib)) -> match_init ia ib
      | (_,Ast0.OptIni(ib))
      | (_,Ast0.UniqueIni(ib)) -> match_init pattern ib
      | _ -> return false
    else return_false (ContextRequired (Ast0.InitTag i))
	
  and match_param pattern p =
    match Ast0.unwrap pattern with
      Ast0.MetaParam(name,pure) ->
	add_pure_binding name pure pure_sp_code.V0.combiner_parameter
	  (function p -> Ast0.ParamTag p)
	  p
    | Ast0.MetaParamList(name,_,pure) -> failwith "metaparamlist not supported"
    | up ->
	if not(checks_needed) or not(context_required) or is_context p
	then
	  match (up,Ast0.unwrap p) with
	    (Ast0.VoidParam(tya),Ast0.VoidParam(tyb)) -> match_typeC tya tyb
	  | (Ast0.Param(tya,ida),Ast0.Param(tyb,idb)) ->
	      conjunct_bindings (match_typeC tya tyb)
		(match_option match_ident ida idb)
	  | (Ast0.PComma(_),Ast0.PComma(_))
	  | (Ast0.Pdots(_),Ast0.Pdots(_))
	  | (Ast0.Pcircles(_),Ast0.Pcircles(_)) -> return true
	  | (Ast0.OptParam(parama),Ast0.OptParam(paramb))
	  | (Ast0.UniqueParam(parama),Ast0.UniqueParam(paramb)) ->
	      match_param parama paramb
	  | (_,Ast0.OptParam(paramb))
	  | (_,Ast0.UniqueParam(paramb)) -> match_param pattern paramb
	  | _ -> return false
	else return_false (ContextRequired (Ast0.ParamTag p))
	    
  and match_statement pattern s =
    match Ast0.unwrap pattern with
      Ast0.MetaStmt(name,pure) ->
	(match Ast0.unwrap s with
	  Ast0.Dots(_,_) | Ast0.Circles(_,_) | Ast0.Stars(_,_) ->
	    return false (* ... is not a single statement *)
	| _ ->
	    add_pure_binding name pure pure_sp_code.V0.combiner_statement
	      (function ty -> Ast0.StmtTag ty)
	      s)
    | Ast0.MetaStmtList(name,pure) -> failwith "metastmtlist not supported"
    | up ->
	if not(checks_needed) or not(context_required) or is_context s
	then
	  match (up,Ast0.unwrap s) with
	    (Ast0.FunDecl(_,fninfoa,namea,_,paramsa,_,_,bodya,_),
	     Ast0.FunDecl(_,fninfob,nameb,_,paramsb,_,_,bodyb,_)) ->
	       conjunct_bindings
		 (match_fninfo fninfoa fninfob)
		 (conjunct_bindings
		    (match_ident namea nameb)
		    (conjunct_bindings
		       (match_dots
			  match_param is_plist_matcher do_plist_match
			  paramsa paramsb)
		       (match_dots
			  match_statement is_slist_matcher do_slist_match
			  bodya bodyb)))
	  | (Ast0.Decl(_,decla),Ast0.Decl(_,declb)) -> match_decl decla declb
	  | (Ast0.Seq(_,bodya,_),Ast0.Seq(_,bodyb,_)) ->
	      (* seqs can only match if they are all minus (plus code
		 allowed) or all context (plus code not allowed in the body).
		 we could be more permissive if the expansions of the isos are
		 also all seqs, but this would be hard to check except at top
		 level, and perhaps not worth checking even in that case.
		 Overall, the issue is that braces are used where single
		 statements are required, and something not satisfying these
		 conditions can cause a single statement to become a
		 non-single statement after the transformation.

		 example: if { ... -foo(); ... }
		 if we let the sequence convert to just -foo();
		 then we produce invalid code.  For some reason,
		 single_statement can't deal with this case, perhaps because
		 it starts introducing too many braces?  don't remember the
		 exact problem...
	      *)
	      if not(checks_needed) or is_minus s or 
		(is_context s &&
		 List.for_all is_pure_context (Ast0.undots bodyb))
	      then
		match_dots match_statement is_slist_matcher do_slist_match
		  bodya bodyb
	      else return_false (Braces(s))
	  | (Ast0.ExprStatement(expa,_),Ast0.ExprStatement(expb,_)) ->
	      match_expr expa expb
	  | (Ast0.IfThen(_,_,expa,_,branch1a,_),
	     Ast0.IfThen(_,_,expb,_,branch1b,_)) ->
	       conjunct_bindings (match_expr expa expb)
		 (match_statement branch1a branch1b)
	  | (Ast0.IfThenElse(_,_,expa,_,branch1a,_,branch2a,_),
	     Ast0.IfThenElse(_,_,expb,_,branch1b,_,branch2b,_)) ->
	       conjunct_bindings
		 (match_expr expa expb)
		 (conjunct_bindings
		    (match_statement branch1a branch1b)
		    (match_statement branch2a branch2b))
	  | (Ast0.While(_,_,expa,_,bodya,_),Ast0.While(_,_,expb,_,bodyb,_)) ->
	      conjunct_bindings (match_expr expa expb)
		(match_statement bodya bodyb)
	  | (Ast0.Do(_,bodya,_,_,expa,_,_),Ast0.Do(_,bodyb,_,_,expb,_,_)) ->
	      conjunct_bindings (match_statement bodya bodyb)
		(match_expr expa expb)
	  | (Ast0.For(_,_,e1a,_,e2a,_,e3a,_,bodya,_),
	     Ast0.For(_,_,e1b,_,e2b,_,e3b,_,bodyb,_)) ->
	       conjunct_bindings
		 (match_option match_expr e1a e1b)
		 (conjunct_bindings
		    (match_option match_expr e2a e2b)
		    (conjunct_bindings
		       (match_option match_expr e3a e3b)
		       (match_statement bodya bodyb)))
	  | (Ast0.Iterator(nma,_,argsa,_,bodya,_),
	     Ast0.Iterator(nmb,_,argsb,_,bodyb,_)) ->
	       if mcode_equal nma nmb
	       then
		 conjunct_bindings
		   (match_dots match_expr is_elist_matcher do_elist_match
		      argsa argsb)
		   (match_statement bodya bodyb)
	       else return false
	  | (Ast0.Switch(_,_,expa,_,_,casesa,_),
	     Ast0.Switch(_,_,expb,_,_,casesb,_)) ->
	       conjunct_bindings (match_expr expa expb)
		 (match_dots match_case_line no_list do_nolist_match
		    casesa casesb)
	  | (Ast0.Break(_,_),Ast0.Break(_,_)) -> return true
	  | (Ast0.Continue(_,_),Ast0.Continue(_,_)) -> return true
	  | (Ast0.Return(_,_),Ast0.Return(_,_)) -> return true
	  | (Ast0.ReturnExpr(_,expa,_),Ast0.ReturnExpr(_,expb,_)) ->
	      match_expr expa expb
	  | (Ast0.Disj(_,statement_dots_lista,_,_),_) ->
	      failwith "disj not supported in patterns"
	  | (Ast0.Nest(_,stmt_dotsa,_,_,_),_) ->
	      failwith "nest not supported in patterns"
	  | (Ast0.Exp(expa),Ast0.Exp(expb)) -> match_expr expa expb
	  | (Ast0.TopExp(expa),Ast0.TopExp(expb)) -> match_expr expa expb
	  | (Ast0.Exp(expa),Ast0.TopExp(expb)) -> match_expr expa expb
	  | (Ast0.Ty(tya),Ast0.Ty(tyb)) -> match_typeC tya tyb
	  | (Ast0.Dots(d,[]),Ast0.Dots(_,wc))
	  | (Ast0.Circles(d,[]),Ast0.Circles(_,wc))
	  | (Ast0.Stars(d,[]),Ast0.Stars(_,wc)) ->
	      (match wc with
		[] -> return true
	      |	_ ->
		  let (_,_,dots_whencode_allowed) = whencode_allowed in
		  if dots_whencode_allowed
		  then
		    List.fold_left
		      (function prev ->
			function
			  | Ast0.WhenNot wc ->
			      conjunct_bindings prev
				(add_dot_binding d (Ast0.DotsStmtTag wc))
			  | Ast0.WhenAlways wc ->
			      conjunct_bindings prev
				(add_dot_binding d (Ast0.StmtTag wc))
			  | Ast0.WhenAny ->
			      conjunct_bindings prev
				(add_dot_binding d Ast0.AnyTag))
		      (return true) wc
		  else
		    (Printf.printf
		       "warning: not applying iso because of whencode";
		     return false))
	  | (Ast0.Dots(_,_::_),_) | (Ast0.Circles(_,_::_),_)
	  | (Ast0.Stars(_,_::_),_) ->
	      failwith "whencode not allowed in a pattern3"
	  | (Ast0.OptStm(rea),Ast0.OptStm(reb))
	  | (Ast0.UniqueStm(rea),Ast0.UniqueStm(reb)) ->
	      match_statement rea reb
	  | (_,Ast0.OptStm(reb))
	  | (_,Ast0.UniqueStm(reb)) -> match_statement pattern reb
	  |	_ -> return false
	else return_false (ContextRequired (Ast0.StmtTag s))
	    
  (* first should provide a subset of the information in the second *)
  and match_fninfo patterninfo cinfo =
    let patterninfo = List.sort compare patterninfo in
    let cinfo = List.sort compare cinfo in
    let rec loop = function
	(Ast0.FStorage(sta)::resta,Ast0.FStorage(stb)::restb) ->
	  if mcode_equal sta stb then loop (resta,restb) else return false
      |	(Ast0.FType(tya)::resta,Ast0.FType(tyb)::restb) ->
	  conjunct_bindings (match_typeC tya tyb) (loop (resta,restb))
      |	(Ast0.FInline(ia)::resta,Ast0.FInline(ib)::restb) ->
	  if mcode_equal ia ib then loop (resta,restb) else return false
      |	(Ast0.FAttr(ia)::resta,Ast0.FAttr(ib)::restb) ->
	  if mcode_equal ia ib then loop (resta,restb) else return false
      |	(x::resta,((y::_) as restb)) ->
	  (match compare x y with
	    -1 -> return false
	  | 1 -> loop (resta,restb)
	  | _ -> failwith "not possible")
      |	_ -> return false in
    loop (patterninfo,cinfo)
      
  and match_case_line pattern c =
    if not(checks_needed) or not(context_required) or is_context c
    then
      match (Ast0.unwrap pattern,Ast0.unwrap c) with
	(Ast0.Default(_,_,codea),Ast0.Default(_,_,codeb)) ->
	  match_dots match_statement is_slist_matcher do_slist_match
	    codea codeb
      | (Ast0.Case(_,expa,_,codea),Ast0.Case(_,expb,_,codeb)) ->
	  conjunct_bindings (match_expr expa expb)
	    (match_dots match_statement is_slist_matcher do_slist_match
	       codea codeb)
      |	(Ast0.OptCase(ca),Ast0.OptCase(cb)) -> match_case_line ca cb
      |	(_,Ast0.OptCase(cb)) -> match_case_line pattern cb
      |	_ -> return false
    else return_false (ContextRequired (Ast0.CaseLineTag c)) in
  
  let match_statement_dots x y =
    match_dots match_statement is_slist_matcher do_slist_match x y in
  
  (match_expr, match_decl, match_statement, match_typeC,
   match_statement_dots)
    
let match_expr dochecks context_required whencode_allowed =
  let (fn,_,_,_,_) = match_maker dochecks context_required whencode_allowed in
  fn
    
let match_decl dochecks context_required whencode_allowed =
  let (_,fn,_,_,_) = match_maker dochecks context_required whencode_allowed in
  fn
    
let match_statement dochecks context_required whencode_allowed =
  let (_,_,fn,_,_) = match_maker dochecks context_required whencode_allowed in
  fn
    
let match_typeC dochecks context_required whencode_allowed =
  let (_,_,_,fn,_) = match_maker dochecks context_required whencode_allowed in
  fn
    
let match_statement_dots dochecks context_required whencode_allowed =
  let (_,_,_,_,fn) = match_maker dochecks context_required whencode_allowed in
  fn
    
(* --------------------------------------------------------------------- *)
(* make an entire tree MINUS *)
    
let make_minus =
  let mcode (term,arity,info,mcodekind) =
    (term,arity,info,
     match mcodekind with
       Ast0.CONTEXT(mc) ->
	 (match !mc with
	   (Ast.NOTHING,_,_) -> Ast0.MINUS(ref([],Ast0.default_token_info))
	 | _ -> failwith "make_minus: unexpected befaft")
     | Ast0.MINUS(mc) -> mcodekind (* in the part copied from the src term *)
     | _ -> failwith "make_minus mcode: unexpected mcodekind") in
  
  let update_mc mcodekind e =
    match !mcodekind with
      Ast0.CONTEXT(mc) ->
	(match !mc with
	  (Ast.NOTHING,_,_) ->
	    mcodekind := Ast0.MINUS(ref([],Ast0.default_token_info))
	| _ -> failwith "make_minus: unexpected befaft")
    | Ast0.MINUS(_mc) -> () (* in the part copied from the src term *)
    | Ast0.PLUS -> failwith "make_minus donothing: unexpected plus mcodekind"
    | _ -> failwith "make_minus donothing: unexpected mcodekind" in
  
  let donothing r k e =
    let mcodekind = Ast0.get_mcodekind_ref e in
    let e = k e in update_mc mcodekind e; e in
  
  (* special case for whencode, because it isn't processed by contextneg,
     since it doesn't appear in the + code *)
  (* cases for dots and nests *)
  let expression r k e =
    let mcodekind = Ast0.get_mcodekind_ref e in
    match Ast0.unwrap e with
      Ast0.Edots(d,whencode) ->
	(*don't recurse because whencode hasn't been processed by context_neg*)
	update_mc mcodekind e; Ast0.rewrap e (Ast0.Edots(mcode d,whencode))
    | Ast0.Ecircles(d,whencode) ->
	(*don't recurse because whencode hasn't been processed by context_neg*)
	update_mc mcodekind e; Ast0.rewrap e (Ast0.Ecircles(mcode d,whencode))
    | Ast0.Estars(d,whencode) ->
	(*don't recurse because whencode hasn't been processed by context_neg*)
	update_mc mcodekind e; Ast0.rewrap e (Ast0.Estars(mcode d,whencode))
    | Ast0.NestExpr(starter,expr_dots,ender,whencode,multi) ->
	update_mc mcodekind e;
	Ast0.rewrap e
	  (Ast0.NestExpr(mcode starter,
			 r.V0.rebuilder_expression_dots expr_dots,
			 mcode ender,whencode,multi))
    | _ -> donothing r k e in
  
  let declaration r k e =
    let mcodekind = Ast0.get_mcodekind_ref e in
    match Ast0.unwrap e with
      Ast0.Ddots(d,whencode) ->
	(*don't recurse because whencode hasn't been processed by context_neg*)
	update_mc mcodekind e; Ast0.rewrap e (Ast0.Ddots(mcode d,whencode))
    | _ -> donothing r k e in
  
  let statement r k e =
    let mcodekind = Ast0.get_mcodekind_ref e in
    match Ast0.unwrap e with
      Ast0.Dots(d,whencode) ->
	(*don't recurse because whencode hasn't been processed by context_neg*)
	update_mc mcodekind e; Ast0.rewrap e (Ast0.Dots(mcode d,whencode))
    | Ast0.Circles(d,whencode) ->
	update_mc mcodekind e; Ast0.rewrap e (Ast0.Circles(mcode d,whencode))
    | Ast0.Stars(d,whencode) ->
	update_mc mcodekind e; Ast0.rewrap e (Ast0.Stars(mcode d,whencode))
    | Ast0.Nest(starter,stmt_dots,ender,whencode,multi) ->
	update_mc mcodekind e;
	Ast0.rewrap e
	  (Ast0.Nest(mcode starter,r.V0.rebuilder_statement_dots stmt_dots,
		     mcode ender,whencode,multi))
    | _ -> donothing r k e in
  
  let initialiser r k e =
    let mcodekind = Ast0.get_mcodekind_ref e in
    match Ast0.unwrap e with
      Ast0.Idots(d,whencode) ->
	(*don't recurse because whencode hasn't been processed by context_neg*)
	update_mc mcodekind e; Ast0.rewrap e (Ast0.Idots(mcode d,whencode))
    | _ -> donothing r k e in
  
  let dots r k e =
    let info = Ast0.get_info e in
    let mcodekind = Ast0.get_mcodekind_ref e in
    match Ast0.unwrap e with
      Ast0.DOTS([]) ->
	(* if context is - this should be - as well.  There are no tokens
	   here though, so the bottom-up minusifier in context_neg leaves it
	   as mixed.  It would be better to fix context_neg, but that would
	   require a special case for each term with a dots subterm. *)
	(match !mcodekind with
	  Ast0.MIXED(mc) ->
	    (match !mc with
	      (Ast.NOTHING,_,_) ->
		mcodekind := Ast0.MINUS(ref([],Ast0.default_token_info));
		e
	    | _ -> failwith "make_minus: unexpected befaft")
	  (* code already processed by an enclosing iso *)
	| Ast0.MINUS(mc) -> e
	| _ ->
	    failwith
	      (Printf.sprintf
		 "%d: make_minus donothingxxx: unexpected mcodekind"
		 info.Ast0.line_start))
    | _ -> donothing r k e in
  
  V0.rebuilder
    mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode
    mcode
    dots dots dots dots dots dots
    donothing expression donothing initialiser donothing declaration
    statement donothing donothing
    
(* --------------------------------------------------------------------- *)
(* rebuild mcode cells in an instantiated alt *)
    
(* mcodes will be side effected later with plus code, so we have to copy
   them on instantiating an isomorphism.  One could wonder whether it would
   be better not to use side-effects, but they are convenient for insert_plus
   where is it useful to manipulate a list of the mcodes but side-effect a
   tree *)
(* hmm... Insert_plus is called before Iso_pattern... *)
let rebuild_mcode start_line =
  let copy_mcodekind = function
      Ast0.CONTEXT(mc) -> Ast0.CONTEXT(ref (!mc))
    | Ast0.MINUS(mc) -> Ast0.MINUS(ref (!mc))
    | Ast0.MIXED(mc) -> Ast0.MIXED(ref (!mc))
    | Ast0.PLUS ->
	(* this function is used elsewhere where we need to rebuild the
	   indices, and so we allow PLUS code as well *)
        Ast0.PLUS in
  
  let mcode (term,arity,info,mcodekind) =
    let info =
      match start_line with
	Some x -> {info with Ast0.line_start = x; Ast0.line_end = x}
      |	None -> info in
    (term,arity,info,copy_mcodekind mcodekind) in
  
  let copy_one (term,info,index,mcodekind,ty,dots,arg,test,is_iso) =
    let info =
      match start_line with
	Some x -> {info with Ast0.line_start = x; Ast0.line_end = x}
      |	None -> info in
    (term,info,ref !index,
     ref (copy_mcodekind !mcodekind),ty,dots,arg,test,is_iso) in
  
  let donothing r k e = copy_one (k e) in
  
  (* case for control operators (if, etc) *)
  let statement r k e =
    let s = k e in
    copy_one
      (Ast0.rewrap s
	 (match Ast0.unwrap s with
	   Ast0.Decl((info,mc),decl) ->
	     Ast0.Decl((info,copy_mcodekind mc),decl)
	 | Ast0.IfThen(iff,lp,tst,rp,branch,(info,mc)) ->
	     Ast0.IfThen(iff,lp,tst,rp,branch,(info,copy_mcodekind mc))
	 | Ast0.IfThenElse(iff,lp,tst,rp,branch1,els,branch2,(info,mc)) ->
	     Ast0.IfThenElse(iff,lp,tst,rp,branch1,els,branch2,
	       (info,copy_mcodekind mc))
	 | Ast0.While(whl,lp,exp,rp,body,(info,mc)) ->
	     Ast0.While(whl,lp,exp,rp,body,(info,copy_mcodekind mc))
	 | Ast0.For(fr,lp,e1,sem1,e2,sem2,e3,rp,body,(info,mc)) ->
	     Ast0.For(fr,lp,e1,sem1,e2,sem2,e3,rp,body,
		      (info,copy_mcodekind mc))
	 | Ast0.Iterator(nm,lp,args,rp,body,(info,mc)) ->
	     Ast0.Iterator(nm,lp,args,rp,body,(info,copy_mcodekind mc))
	 | Ast0.FunDecl
	     ((info,mc),fninfo,name,lp,params,rp,lbrace,body,rbrace) ->
	       Ast0.FunDecl
		 ((info,copy_mcodekind mc),
		  fninfo,name,lp,params,rp,lbrace,body,rbrace)
	 | s -> s)) in
  
  V0.rebuilder
    mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode
    mcode
    donothing donothing donothing donothing donothing donothing
    donothing donothing donothing donothing donothing
    donothing statement donothing donothing
    
(* --------------------------------------------------------------------- *)
(* The problem of whencode.  If an isomorphism contains dots in multiple
   rules, then the code that is matched cannot contain whencode, because we
   won't know which dots it goes with. Should worry about nests, but they
   aren't allowed in isomorphisms for the moment. *)
    
let count_edots =
  let mcode x = 0 in
  let option_default = 0 in
  let bind x y = x + y in
  let donothing r k e = k e in
  let exprfn r k e =
    match Ast0.unwrap e with
      Ast0.Edots(_,_) | Ast0.Ecircles(_,_) | Ast0.Estars(_,_) -> 1
    | _ -> 0 in
  
  V0.combiner bind option_default
    mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode
    mcode
    donothing donothing donothing donothing donothing donothing
    donothing exprfn donothing donothing donothing donothing donothing
    donothing donothing
    
let count_idots =
  let mcode x = 0 in
  let option_default = 0 in
  let bind x y = x + y in
  let donothing r k e = k e in
  let initfn r k e =
    match Ast0.unwrap e with Ast0.Idots(_,_) -> 1 | _ -> 0 in
  
  V0.combiner bind option_default
    mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode
    mcode
    donothing donothing donothing donothing donothing donothing
    donothing donothing donothing initfn donothing donothing donothing
    donothing donothing
    
let count_dots =
  let mcode x = 0 in
  let option_default = 0 in
  let bind x y = x + y in
  let donothing r k e = k e in
  let stmtfn r k e =
    match Ast0.unwrap e with
      Ast0.Dots(_,_) | Ast0.Circles(_,_) | Ast0.Stars(_,_) -> 1
    | _ -> 0 in
  
  V0.combiner bind option_default
    mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode
    mcode
    donothing donothing donothing donothing donothing donothing
    donothing donothing donothing donothing donothing donothing stmtfn
    donothing donothing
    
(* --------------------------------------------------------------------- *)
    
let lookup name bindings mv_bindings =
  try Common.Left (List.assoc (term name) bindings)
  with
    Not_found ->
      (* failure is not possible anymore *)
      Common.Right (List.assoc (term name) mv_bindings)

let instantiate bindings mv_bindings =
  let mcode x = x in
  let donothing r k e = k e in

  (* cases where metavariables can occur *)
  let identfn r k e =
    match Ast0.unwrap e with
      Ast0.MetaId(name,pure) ->
	(rebuild_mcode None).V0.rebuilder_ident
	  (match lookup name bindings mv_bindings with
	    Common.Left(Ast0.IdentTag(id)) -> id
	  | Common.Left(_) -> failwith "not possible 1"
	  | Common.Right(new_mv) ->
	      Ast0.rewrap e
		(Ast0.MetaId(Ast0.set_mcode_data new_mv name,pure)))
    | Ast0.MetaFunc(name,pure) -> failwith "metafunc not supported"
    | Ast0.MetaLocalFunc(name,pure) -> failwith "metalocalfunc not supported"
    | _ -> k e in

  (* case for list metavariables *)
  let rec elist r same_dots = function
      [] -> []
    | [x] ->
	(match Ast0.unwrap x with
	  Ast0.MetaExprList(name,lenname,pure) ->
	    failwith "meta_expr_list in iso not supported"
	    (*match lookup name bindings mv_bindings with
	      Common.Left(Ast0.DotsExprTag(exp)) ->
		(match same_dots exp with
		  Some l -> l
		| None -> failwith "dots put in incompatible context")
	    | Common.Left(Ast0.ExprTag(exp)) -> [exp]
	    | Common.Left(_) -> failwith "not possible 1"
	    | Common.Right(new_mv) ->
		failwith "MetaExprList in SP not supported"*)
	| _ -> [r.V0.rebuilder_expression x])
    | x::xs -> (r.V0.rebuilder_expression x)::(elist r same_dots xs) in

  let rec plist r same_dots = function
      [] -> []
    | [x] ->
	(match Ast0.unwrap x with
	  Ast0.MetaParamList(name,lenname,pure) ->
	    failwith "meta_param_list in iso not supported"
	    (*match lookup name bindings mv_bindings with
	      Common.Left(Ast0.DotsParamTag(param)) ->
		(match same_dots param with
		  Some l -> l
		| None -> failwith "dots put in incompatible context")
	    | Common.Left(Ast0.ParamTag(param)) -> [param]
	    | Common.Left(_) -> failwith "not possible 1"
	    | Common.Right(new_mv) ->
		failwith "MetaExprList in SP not supported"*)
	| _ -> [r.V0.rebuilder_parameter x])
    | x::xs -> (r.V0.rebuilder_parameter x)::(plist r same_dots xs) in

  let rec slist r same_dots = function
      [] -> []
    | [x] ->
	(match Ast0.unwrap x with
	  Ast0.MetaStmtList(name,pure) ->
	    (match lookup name bindings mv_bindings with
	      Common.Left(Ast0.DotsStmtTag(stm)) ->
		(match same_dots stm with
		  Some l -> l
		| None -> failwith "dots put in incompatible context")
	    | Common.Left(Ast0.StmtTag(stm)) -> [stm]
	    | Common.Left(_) -> failwith "not possible 1"
	    | Common.Right(new_mv) ->
		failwith "MetaExprList in SP not supported")
	| _ -> [r.V0.rebuilder_statement x])
    | x::xs -> (r.V0.rebuilder_statement x)::(slist r same_dots xs) in

  let same_dots d =
    match Ast0.unwrap d with Ast0.DOTS(l) -> Some l |_ -> None in
  let same_circles d =
    match Ast0.unwrap d with Ast0.CIRCLES(l) -> Some l |_ -> None in
  let same_stars d =
    match Ast0.unwrap d with Ast0.STARS(l) -> Some l |_ -> None in

  let dots list_fn r k d =
    Ast0.rewrap d
      (match Ast0.unwrap d with
	Ast0.DOTS(l) -> Ast0.DOTS(list_fn r same_dots l)
      | Ast0.CIRCLES(l) -> Ast0.CIRCLES(list_fn r same_circles l)
      | Ast0.STARS(l) -> Ast0.STARS(list_fn r same_stars l)) in

  let exprfn r k e =
    match Ast0.unwrap e with
      Ast0.MetaExpr(name,x,form,pure) ->
	(rebuild_mcode None).V0.rebuilder_expression
	  (match lookup name bindings mv_bindings with
	    Common.Left(Ast0.ExprTag(exp)) -> exp
	  | Common.Left(_) -> failwith "not possible 1"
	  | Common.Right(new_mv) ->
	      let new_types =
		match x with
		  None -> None
		| Some types ->
		    let rec renamer = function
			Type_cocci.MetaType(name,keep,inherited) ->
			  (match lookup (name,(),(),()) bindings mv_bindings
			  with
			    Common.Left(Ast0.TypeCTag(t)) ->
			      Ast0.ast0_type_to_type t
			  | Common.Left(_) -> failwith "unexpected type"
			  | Common.Right(new_mv) ->
			      Type_cocci.MetaType(new_mv,keep,inherited))
		      |	Type_cocci.ConstVol(cv,ty) ->
			  Type_cocci.ConstVol(cv,renamer ty)
		      | Type_cocci.Pointer(ty) ->
			  Type_cocci.Pointer(renamer ty)
		      | Type_cocci.FunctionPointer(ty) ->
			  Type_cocci.FunctionPointer(renamer ty)
		      | Type_cocci.Array(ty) ->
			  Type_cocci.Array(renamer ty)
		      | t -> t in
		    Some(List.map renamer types) in
	      Ast0.rewrap e
		(Ast0.MetaExpr
		   (Ast0.set_mcode_data new_mv name,new_types,form,pure)))
    | Ast0.MetaErr(namea,pure) -> failwith "metaerr not supported"
    | Ast0.MetaExprList(namea,lenname,pure) ->
	failwith "metaexprlist not supported"
    | Ast0.Unary(exp,unop) ->
	(match Ast0.unwrap_mcode unop with
	  Ast.Not ->
	    (match Ast0.unwrap exp with
	      Ast0.MetaExpr(name,x,form,pure) ->
		let res = r.V0.rebuilder_expression exp in
		let rec negate e (*for rewrapping*) res (*code to process*) =
		  match Ast0.unwrap res with
		    Ast0.Binary(e1,op,e2) ->
		      let reb nop = Ast0.rewrap_mcode op (Ast.Logical(nop)) in
		      let invop =
			match Ast0.unwrap_mcode op with
			  Ast.Logical(Ast.Inf) ->
			    Ast0.Binary(e1,reb Ast.SupEq,e2)
			| Ast.Logical(Ast.Sup) ->
			    Ast0.Binary(e1,reb Ast.InfEq,e2)
			| Ast.Logical(Ast.InfEq) ->
			    Ast0.Binary(e1,reb Ast.Sup,e2)
			| Ast.Logical(Ast.SupEq) ->
			    Ast0.Binary(e1,reb Ast.Inf,e2)
			| Ast.Logical(Ast.Eq) ->
			    Ast0.Binary(e1,reb Ast.NotEq,e2)
			| Ast.Logical(Ast.NotEq) ->
			    Ast0.Binary(e1,reb Ast.Eq,e2)
			| Ast.Logical(Ast.AndLog) ->
			    Ast0.Binary(negate e1 e1,reb Ast.OrLog,
					negate e2 e2)
			| Ast.Logical(Ast.OrLog) ->
			    Ast0.Binary(negate e1 e1,reb Ast.AndLog,
					negate e2 e2)
			| _ -> Ast0.Unary(res,Ast0.rewrap_mcode op Ast.Not) in
		      Ast0.rewrap e invop
		  | Ast0.DisjExpr(lp,exps,mids,rp) ->
		      (* use res because it is the transformed argument *)
		      let exps = List.map (function e -> negate e e) exps in
		      Ast0.rewrap res (Ast0.DisjExpr(lp,exps,mids,rp))
		  | _ ->
		      (*use e, because this might be the toplevel expression*)
		      Ast0.rewrap e
			(Ast0.Unary(res,Ast0.rewrap_mcode unop Ast.Not)) in
		negate e res
	    | _ -> k e)
	| _ -> k e)
    | Ast0.Edots(d,_) ->
	(try
	  (match List.assoc (dot_term d) bindings with
	    Ast0.ExprTag(exp) -> Ast0.rewrap e (Ast0.Edots(d,Some exp))
	  | _ -> failwith "unexpected binding")
	with Not_found -> e)
    | Ast0.Ecircles(d,_) ->
	(try
	  (match List.assoc (dot_term d) bindings with
	    Ast0.ExprTag(exp) -> Ast0.rewrap e (Ast0.Ecircles(d,Some exp))
	  | _ -> failwith "unexpected binding")
	with Not_found -> e)
    | Ast0.Estars(d,_) ->
	(try
	  (match List.assoc (dot_term d) bindings with
	    Ast0.ExprTag(exp) -> Ast0.rewrap e (Ast0.Estars(d,Some exp))
	  | _ -> failwith "unexpected binding")
	with Not_found -> e)
    | _ -> k e in

  let tyfn r k e =
    match Ast0.unwrap e with
      Ast0.MetaType(name,pure) ->
	(rebuild_mcode None).V0.rebuilder_typeC
	  (match lookup name bindings mv_bindings with
	    Common.Left(Ast0.TypeCTag(ty)) -> ty
	  | Common.Left(_) -> failwith "not possible 1"
	  | Common.Right(new_mv) ->
	      Ast0.rewrap e
		(Ast0.MetaType(Ast0.set_mcode_data new_mv name,pure)))
    | _ -> k e in

  let declfn r k e =
    match Ast0.unwrap e with
      Ast0.Ddots(d,_) ->
	(try
	  (match List.assoc (dot_term d) bindings with
	    Ast0.DeclTag(exp) -> Ast0.rewrap e (Ast0.Ddots(d,Some exp))
	  | _ -> failwith "unexpected binding")
	with Not_found -> e)
    | _ -> k e in

  let paramfn r k e =
    match Ast0.unwrap e with
      Ast0.MetaParam(name,pure) ->
	(rebuild_mcode None).V0.rebuilder_parameter
	  (match lookup name bindings mv_bindings with
	    Common.Left(Ast0.ParamTag(param)) -> param
	  | Common.Left(_) -> failwith "not possible 1"
	  | Common.Right(new_mv) ->
	      Ast0.rewrap e
		(Ast0.MetaParam(Ast0.set_mcode_data new_mv name,pure)))
    | Ast0.MetaParamList(name,lenname,pure) ->
	failwith "metaparamlist not supported"
    | _ -> k e in

  let stmtfn r k e =
    match Ast0.unwrap e with
    Ast0.MetaStmt(name,pure) ->
	(rebuild_mcode None).V0.rebuilder_statement
	  (match lookup name bindings mv_bindings with
	    Common.Left(Ast0.StmtTag(stm)) -> stm
	  | Common.Left(_) -> failwith "not possible 1"
	  | Common.Right(new_mv) ->
	      Ast0.rewrap e
		(Ast0.MetaStmt(Ast0.set_mcode_data new_mv name,pure)))
    | Ast0.MetaStmtList(name,pure) -> failwith "metastmtlist not supported"
    | Ast0.Dots(d,_) ->
	Ast0.rewrap e
	  (Ast0.Dots
	     (d,
	      List.map
		(function (_,v) ->
		  match v with
		    Ast0.DotsStmtTag(stms) -> Ast0.WhenNot stms
		  | Ast0.StmtTag(stm) -> Ast0.WhenAlways stm
		  | Ast0.AnyTag -> Ast0.WhenAny
		  | _ -> failwith "unexpected binding")
		(List.filter (function (x,v) -> x = (dot_term d)) bindings)))
    | Ast0.Circles(d,_) ->
	Ast0.rewrap e
	  (Ast0.Circles
	     (d,
	      List.map
		(function (_,v) ->
		  match v with
		    Ast0.DotsStmtTag(stms) -> Ast0.WhenNot stms
		  | Ast0.StmtTag(stm) -> Ast0.WhenAlways stm
		  | Ast0.AnyTag -> Ast0.WhenAny
		  | _ -> failwith "unexpected binding")
		(List.filter (function (x,v) -> x = (dot_term d)) bindings)))
    | Ast0.Stars(d,_) ->
	Ast0.rewrap e
	  (Ast0.Stars
	     (d,
	      List.map
		(function (_,v) ->
		  match v with
		    Ast0.DotsStmtTag(stms) -> Ast0.WhenNot stms
		  | Ast0.StmtTag(stm) -> Ast0.WhenAlways stm
		  | Ast0.AnyTag -> Ast0.WhenAny
		  | _ -> failwith "unexpected binding")
		(List.filter (function (x,v) -> x = (dot_term d)) bindings)))
    | _ -> k e in

  V0.rebuilder
    mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode
    mcode
    (dots elist) donothing (dots plist) (dots slist) donothing donothing
    identfn exprfn tyfn donothing paramfn declfn stmtfn donothing donothing

(* --------------------------------------------------------------------- *)

let is_minus e =
  match Ast0.get_mcodekind e with Ast0.MINUS(cell) -> true | _ -> false

let context_required e = not(is_minus e)

let disj_fail bindings e =
  match bindings with
    Some x -> Printf.fprintf stderr "no disj available at this type"; e
  | None -> e

(* isomorphism code is by default CONTEXT *)
let merge_plus model_mcode e_mcode =
  match model_mcode with
    Ast0.MINUS(mc) ->
      (* add the replacement information at the root *)
      (match e_mcode with
	Ast0.MINUS(emc) ->
	  emc :=
	    (match (!mc,!emc) with
	      (([],_),(x,t)) | ((x,_),([],t)) -> (x,t)
	    | _ -> failwith "how can we combine minuses?")
      |	_ -> failwith "not possible 6")
  | Ast0.CONTEXT(mc) ->
      (match e_mcode with
	Ast0.CONTEXT(emc) ->
	  (* keep the logical line info as in the model *)
	  let (mba,tb,ta) = !mc in
	  let (eba,_,_) = !emc in
	  (* merging may be required when a term is replaced by a subterm *)
	  let merged =
	    match (mba,eba) with
	      (x,Ast.NOTHING) | (Ast.NOTHING,x) -> x
	    | (Ast.BEFORE(b1),Ast.BEFORE(b2)) -> Ast.BEFORE(b1@b2)
	    | (Ast.BEFORE(b),Ast.AFTER(a)) -> Ast.BEFOREAFTER(b,a)
	    | (Ast.BEFORE(b1),Ast.BEFOREAFTER(b2,a)) ->
		Ast.BEFOREAFTER(b1@b2,a)
	    | (Ast.AFTER(a),Ast.BEFORE(b)) -> Ast.BEFOREAFTER(b,a)
	    | (Ast.AFTER(a1),Ast.AFTER(a2)) ->Ast.AFTER(a2@a1)
	    | (Ast.AFTER(a1),Ast.BEFOREAFTER(b,a2)) -> Ast.BEFOREAFTER(b,a2@a1)
	    | (Ast.BEFOREAFTER(b1,a),Ast.BEFORE(b2)) ->
		Ast.BEFOREAFTER(b1@b2,a)
	    | (Ast.BEFOREAFTER(b,a1),Ast.AFTER(a2)) ->
		Ast.BEFOREAFTER(b,a2@a1)
	    | (Ast.BEFOREAFTER(b1,a1),Ast.BEFOREAFTER(b2,a2)) ->
		 Ast.BEFOREAFTER(b1@b2,a2@a1) in
	  emc := (merged,tb,ta)
      |	Ast0.MINUS(emc) ->
	  let (anything_bef_aft,_,_) = !mc in
	  let (anythings,t) = !emc in
	  emc :=
	    (match anything_bef_aft with
	      Ast.BEFORE(b) -> (b@anythings,t)
	    | Ast.AFTER(a) -> (anythings@a,t)
	    | Ast.BEFOREAFTER(b,a) -> (b@anythings@a,t)
	    | Ast.NOTHING -> (anythings,t))
      |	_ -> failwith "not possible 7")
  | Ast0.MIXED(_) -> failwith "not possible 8"
  | Ast0.PLUS -> failwith "not possible 9"

let copy_plus printer minusify model e =
  let e =
    match Ast0.get_mcodekind model with
      Ast0.MINUS(mc) -> minusify e
    | Ast0.CONTEXT(mc) -> e
    | _ -> failwith "not possible: copy_plus\n" in
  merge_plus (Ast0.get_mcodekind model) (Ast0.get_mcodekind e);
  e

let copy_minus printer minusify model e =
  match Ast0.get_mcodekind model with
    Ast0.MINUS(mc) -> minusify e
  | Ast0.CONTEXT(mc) -> e
  | Ast0.MIXED(_) -> failwith "not possible 8"
  | Ast0.PLUS -> failwith "not possible 9"

let whencode_allowed prev_ecount prev_icount prev_dcount
    ecount icount dcount rest =
  (* actually, if ecount or dcount is 0, the flag doesn't matter, because it
     won't be tested *)
  let other_ecount = (* number of edots *)
    List.fold_left (function rest -> function (_,ec,ic,dc) -> ec + rest)
      prev_ecount rest in
  let other_icount = (* number of dots *)
    List.fold_left (function rest -> function (_,ec,ic,dc) -> ic + rest)
      prev_icount rest in
  let other_dcount = (* number of dots *)
    List.fold_left (function rest -> function (_,ec,ic,dc) -> dc + rest)
      prev_dcount rest in
  (ecount = 0 or other_ecount = 0, icount = 0 or other_icount = 0,
   dcount = 0 or other_dcount = 0)

(* copy the befores and afters to the instantiated code *)
let extra_copy_stmt_plus model e =
  (match Ast0.unwrap model with
    Ast0.FunDecl((info,bef),_,_,_,_,_,_,_,_)
  | Ast0.Decl((info,bef),_) ->
      (match Ast0.unwrap e with
	Ast0.FunDecl((info,bef1),_,_,_,_,_,_,_,_)
      | Ast0.Decl((info,bef1),_) ->
	  merge_plus bef bef1
      | _ ->  merge_plus bef (Ast0.get_mcodekind e))
  | Ast0.IfThen(_,_,_,_,_,(info,aft))
  | Ast0.IfThenElse(_,_,_,_,_,_,_,(info,aft))
  | Ast0.While(_,_,_,_,_,(info,aft))
  | Ast0.For(_,_,_,_,_,_,_,_,_,(info,aft))
  | Ast0.Iterator(_,_,_,_,_,(info,aft)) ->
      (match Ast0.unwrap e with
	Ast0.IfThen(_,_,_,_,_,(info,aft1))
      | Ast0.IfThenElse(_,_,_,_,_,_,_,(info,aft1))
      | Ast0.While(_,_,_,_,_,(info,aft1))
      | Ast0.For(_,_,_,_,_,_,_,_,_,(info,aft1))
      | Ast0.Iterator(_,_,_,_,_,(info,aft1)) ->
	  merge_plus aft aft1
      | _ -> merge_plus aft (Ast0.get_mcodekind e))
  | _ -> ());
  e

let extra_copy_other_plus model e = e

(* --------------------------------------------------------------------- *)

let mv_count = ref 0
let new_mv (_,s) =
  let ct = !mv_count in
  mv_count := !mv_count + 1;
  "_"^s^"_"^(string_of_int ct)

let get_name = function
    Ast.MetaIdDecl(ar,nm) ->
      (nm,function nm -> Ast.MetaIdDecl(ar,nm))
  | Ast.MetaFreshIdDecl(ar,nm) ->
      (nm,function nm -> Ast.MetaFreshIdDecl(ar,nm))
  | Ast.MetaTypeDecl(ar,nm) ->
      (nm,function nm -> Ast.MetaTypeDecl(ar,nm))
  | Ast.MetaListlenDecl(nm) ->
      failwith "should not be rebuilt"
  | Ast.MetaParamDecl(ar,nm) ->
      (nm,function nm -> Ast.MetaParamDecl(ar,nm))
  | Ast.MetaParamListDecl(ar,nm,nm1) ->
      (nm,function nm -> Ast.MetaParamListDecl(ar,nm,nm1))
  | Ast.MetaConstDecl(ar,nm,ty) ->
      (nm,function nm -> Ast.MetaConstDecl(ar,nm,ty))
  | Ast.MetaErrDecl(ar,nm) ->
      (nm,function nm -> Ast.MetaErrDecl(ar,nm))
  | Ast.MetaExpDecl(ar,nm,ty) ->
      (nm,function nm -> Ast.MetaExpDecl(ar,nm,ty))
  | Ast.MetaIdExpDecl(ar,nm,ty) ->
      (nm,function nm -> Ast.MetaIdExpDecl(ar,nm,ty))
  | Ast.MetaExpListDecl(ar,nm,nm1) ->
      (nm,function nm -> Ast.MetaExpListDecl(ar,nm,nm1))
  | Ast.MetaStmDecl(ar,nm) ->
      (nm,function nm -> Ast.MetaStmDecl(ar,nm))
  | Ast.MetaStmListDecl(ar,nm) ->
      (nm,function nm -> Ast.MetaStmListDecl(ar,nm))
  | Ast.MetaFuncDecl(ar,nm) ->
      (nm,function nm -> Ast.MetaFuncDecl(ar,nm))
  | Ast.MetaLocalFuncDecl(ar,nm) ->
      (nm,function nm -> Ast.MetaLocalFuncDecl(ar,nm))

let make_new_metavars metavars bindings =
  let new_metavars =
    List.filter
      (function mv ->
	let (s,_) = get_name mv in
	try let _ = List.assoc s bindings in false with Not_found -> true)
      metavars in
  List.split
    (List.map
       (function mv ->
	 let (s,rebuild) = get_name mv in
	 let new_s = (!current_rule,new_mv s) in
	 (rebuild new_s, (s,new_s)))
       new_metavars)

(* --------------------------------------------------------------------- *)

let mkdisj matcher metavars alts instantiater e disj_maker minusify
    rebuild_mcodes name printer extra_plus =
  let call_instantiate bindings mv_bindings alts =
    List.concat
      (List.map
	 (function (a,_,_,_) ->
	   nub
	   (* no need to create duplicates when the bindings have no effect *)
	     (List.map
		(function bindings ->
		  copy_plus printer minusify e
		    (extra_plus e
		       (instantiater bindings mv_bindings (rebuild_mcodes a))))
		bindings))
	 alts) in
  let rec inner_loop all_alts prev_ecount prev_icount prev_dcount = function
      [] -> Common.Left (prev_ecount, prev_icount, prev_dcount)
    | ((pattern,ecount,icount,dcount)::rest) ->
	let wc =
	  whencode_allowed prev_ecount prev_icount prev_dcount
	    ecount dcount icount rest in
	(match matcher true (context_required e) wc pattern e init_env with
	  Fail(reason) ->
	    if reason = NonMatch || not !Flag_parsing_cocci.show_iso_failures
	    then ()
	    else
	      (match matcher false false wc pattern e init_env with
		OK _ ->
		  interpret_reason name (Ast0.get_line e) reason
		    (function () -> printer e)
	      | _ -> ());
	    inner_loop all_alts (prev_ecount + ecount) (prev_icount + icount)
	      (prev_dcount + dcount) rest
	| OK (bindings : (((string * string) * 'a) list list)) ->
	    (match List.concat all_alts with
	      [x] -> Common.Left (prev_ecount, prev_icount, prev_dcount)
	    | all_alts ->
		let (new_metavars,mv_bindings) =
		  make_new_metavars metavars (nub(List.concat bindings)) in
		Common.Right
		  (new_metavars,
		   call_instantiate bindings mv_bindings all_alts))) in
  let rec outer_loop prev_ecount prev_icount prev_dcount = function
      [] | [[_]] (*only one alternative*)  -> ([],e) (* nothing matched *)
    | (alts::rest) as all_alts ->
	match inner_loop all_alts prev_ecount prev_icount prev_dcount alts with
	  Common.Left(prev_ecount, prev_icount, prev_dcount) ->
	    outer_loop prev_ecount prev_icount prev_dcount rest
	| Common.Right (new_metavars,res) ->
	    (new_metavars,
	     copy_minus printer minusify e (disj_maker res)) in
  outer_loop 0 0 0 alts

(* no one should ever look at the information stored in these mcodes *)
let disj_starter =
  ("(",Ast0.NONE,Ast0.default_info(),Ast0.context_befaft())

let disj_ender =
  ("(",Ast0.NONE,Ast0.default_info(),Ast0.context_befaft())

let disj_mid _ =
  ("|",Ast0.NONE,Ast0.default_info(),Ast0.context_befaft())

let make_disj_type tl =
  let mids =
    match tl with
      [] -> failwith "bad disjunction"
    | x::xs -> List.map disj_mid xs in
  Ast0.context_wrap (Ast0.DisjType(disj_starter,tl,mids,disj_ender))
let make_disj_stmt_list tl =
  let mids =
    match tl with
      [] -> failwith "bad disjunction"
    | x::xs -> List.map disj_mid xs in
  Ast0.context_wrap (Ast0.Disj(disj_starter,tl,mids,disj_ender))
let make_disj_expr el =
  let mids =
    match el with
      [] -> failwith "bad disjunction"
    | x::xs -> List.map disj_mid xs in
  Ast0.context_wrap (Ast0.DisjExpr(disj_starter,el,mids,disj_ender))
let make_disj_decl dl =
  let mids =
    match dl with
      [] -> failwith "bad disjunction"
    | x::xs -> List.map disj_mid xs in
  Ast0.context_wrap (Ast0.DisjDecl(disj_starter,dl,mids,disj_ender))
let make_disj_stmt sl =
  let dotify x = Ast0.context_wrap (Ast0.DOTS[x]) in
  let mids =
    match sl with
      [] -> failwith "bad disjunction"
    | x::xs -> List.map disj_mid xs in
  Ast0.context_wrap
    (Ast0.Disj(disj_starter,List.map dotify sl,mids,disj_ender))

let transform_type (metavars,alts,name) e =
  match alts with
    (Ast0.TypeCTag(_)::_)::_ ->
      (* start line is given to any leaves in the iso code *)
      let start_line = Some ((Ast0.get_info e).Ast0.line_start) in
      let alts =
	List.map
	  (List.map
	     (function
		 Ast0.TypeCTag(p) ->
		   (p,count_edots.V0.combiner_typeC p,
		    count_idots.V0.combiner_typeC p,
		    count_dots.V0.combiner_typeC p)
	       | _ -> failwith "invalid alt"))
	  alts in
      mkdisj match_typeC metavars alts
	(function b -> function mv_b -> function t ->
	  Ast0.set_iso
	    ((instantiate b mv_b).V0.rebuilder_typeC t)
	    (name,Ast0.TypeCTag t)) e
	make_disj_type make_minus.V0.rebuilder_typeC
	(rebuild_mcode start_line).V0.rebuilder_typeC
	name Unparse_ast0.typeC extra_copy_other_plus
  | _ -> ([],e)


let transform_expr (metavars,alts,name) e =
  let process _ =
      (* start line is given to any leaves in the iso code *)
    let start_line = Some ((Ast0.get_info e).Ast0.line_start) in
    let alts =
      List.map
	(List.map
	   (function
	       Ast0.ExprTag(p) | Ast0.ArgExprTag(p) | Ast0.TestExprTag(p) ->
		 (p,count_edots.V0.combiner_expression p,
		  count_idots.V0.combiner_expression p,
		  count_dots.V0.combiner_expression p)
	     | _ -> failwith "invalid alt"))
	alts in
    mkdisj match_expr metavars alts
      (function b -> function mv_b -> function e ->
	Ast0.set_iso
	  ((instantiate b mv_b).V0.rebuilder_expression e)
	  (name,Ast0.ExprTag e)) e
      make_disj_expr make_minus.V0.rebuilder_expression
      (rebuild_mcode start_line).V0.rebuilder_expression
      name Unparse_ast0.expression extra_copy_other_plus in
  match alts with
    (Ast0.ExprTag(_)::_)::_ -> process()
  | (Ast0.ArgExprTag(_)::_)::_ when Ast0.get_arg_exp e -> process()
  | (Ast0.TestExprTag(_)::_)::_ when Ast0.get_test_exp e -> process()
  | _ -> ([],e)

let transform_decl (metavars,alts,name) e =
  match alts with
    (Ast0.DeclTag(_)::_)::_ ->
      (* start line is given to any leaves in the iso code *)
      let start_line = Some (Ast0.get_info e).Ast0.line_start in
      let alts =
	List.map
	  (List.map
	     (function
		 Ast0.DeclTag(p) ->
		   (p,count_edots.V0.combiner_declaration p,
		    count_idots.V0.combiner_declaration p,
		    count_dots.V0.combiner_declaration p)
	       | _ -> failwith "invalid alt"))
	  alts in
      mkdisj match_decl metavars alts
	(function b -> function mv_b -> function d ->
	  Ast0.set_iso
	    ((instantiate b mv_b).V0.rebuilder_declaration d)
	    (name,Ast0.DeclTag d)) e
	make_disj_decl
	make_minus.V0.rebuilder_declaration
	(rebuild_mcode start_line).V0.rebuilder_declaration
	name Unparse_ast0.declaration extra_copy_other_plus
  | _ -> ([],e)

let transform_stmt (metavars,alts,name) e =
  match alts with
    (Ast0.StmtTag(_)::_)::_ ->
      (* start line is given to any leaves in the iso code *)
      let start_line = Some (Ast0.get_info e).Ast0.line_start in
      let alts =
	List.map
	  (List.map
	     (function
		 Ast0.StmtTag(p) ->
		   (p,count_edots.V0.combiner_statement p,
		    count_idots.V0.combiner_statement p,
		    count_dots.V0.combiner_statement p)
	       | _ -> failwith "invalid alt"))
	  alts in
      mkdisj match_statement metavars alts
	(function b -> function mv_b -> function s ->
	  Ast0.set_iso
	    ((instantiate b mv_b).V0.rebuilder_statement s)
	    (name,Ast0.StmtTag s)) e
	make_disj_stmt make_minus.V0.rebuilder_statement
	(rebuild_mcode start_line).V0.rebuilder_statement
	name (Unparse_ast0.statement "") extra_copy_stmt_plus
  | _ -> ([],e)

(* sort of a hack, because there is no disj at top level *)
let transform_top (metavars,alts,name) e =
  match Ast0.unwrap e with
    Ast0.DECL(declstm) ->
      (try
	let strip alts =
	  List.map
	    (List.map
	       (function
		   Ast0.DotsStmtTag(d) ->
		     (match Ast0.unwrap d with
		       Ast0.DOTS([s]) -> Ast0.StmtTag(s)
		     | _ -> raise (Failure ""))
		 | _ -> raise (Failure "")))
	    alts in
	let (mv,s) = transform_stmt (metavars,strip alts,name) declstm in
	(mv,Ast0.rewrap e (Ast0.DECL(s)))
      with Failure _ -> ([],e))
  | Ast0.CODE(stmts) ->
      let (mv,res) =
	match alts with
	  (Ast0.DotsStmtTag(_)::_)::_ ->
	       (* start line is given to any leaves in the iso code *)
	    let start_line = Some ((Ast0.get_info e).Ast0.line_start) in
	    let alts =
	      List.map
		(List.map
		   (function
		       Ast0.DotsStmtTag(p) ->
			 (p,count_edots.V0.combiner_statement_dots p,
			  count_idots.V0.combiner_statement_dots p,
			  count_dots.V0.combiner_statement_dots p)
		     | _ -> failwith "invalid alt"))
		alts in
	    mkdisj match_statement_dots metavars alts
	      (function b -> function mv_b -> function s ->
		Ast0.set_iso
		  ((instantiate b mv_b).V0.rebuilder_statement_dots s)
		  (name,Ast0.DotsStmtTag s))
	      stmts
	      (function x ->
		Ast0.rewrap e (Ast0.DOTS([make_disj_stmt_list x])))
	      make_minus.V0.rebuilder_statement_dots
	      (rebuild_mcode start_line).V0.rebuilder_statement_dots
	      name Unparse_ast0.statement_dots extra_copy_other_plus
	| _ -> ([],stmts) in
      (mv,Ast0.rewrap e (Ast0.CODE res))
  | _ -> ([],e)

(* --------------------------------------------------------------------- *)

let transform (alts : isomorphism) t =
  (* the following ugliness is because rebuilder only returns a new term *)
  let extra_meta_decls = ref ([] : Ast_cocci.metavar list) in
  let mcode x = x in
  let donothing r k e = k e in
  let exprfn r k e =
    let (extra_meta,exp) = transform_expr alts (k e) in
    extra_meta_decls := extra_meta @ !extra_meta_decls;
    exp in

  let declfn r k e =
    let (extra_meta,dec) = transform_decl alts (k e) in
    extra_meta_decls := extra_meta @ !extra_meta_decls;
    dec in

  let stmtfn r k e =
    let (extra_meta,stm) = transform_stmt alts (k e) in
    extra_meta_decls := extra_meta @ !extra_meta_decls;
    stm in
  
  let typefn r k e =
    let (extra_meta,ty) = transform_type alts (k e) in
    extra_meta_decls := extra_meta @ !extra_meta_decls;
    ty in
  
  let topfn r k e =
    let (extra_meta,ty) = transform_top alts (k e) in
    extra_meta_decls := extra_meta @ !extra_meta_decls;
    ty in
  
  let res =
    V0.rebuilder
      mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode
      mcode
      donothing donothing donothing donothing donothing donothing
      donothing exprfn typefn donothing donothing declfn stmtfn
      donothing topfn in
  let res = res.V0.rebuilder_top_level t in
  (!extra_meta_decls,res)

(* --------------------------------------------------------------------- *)

(* should be done by functorizing the parser to use wrap or context_wrap *)
let rewrap =
  let mcode (x,a,i,mc) = (x,a,i,Ast0.context_befaft()) in
  let donothing r k e = Ast0.context_wrap(Ast0.unwrap(k e)) in
  V0.rebuilder
    mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode
    mcode
    donothing donothing donothing donothing donothing donothing
    donothing donothing donothing donothing donothing donothing donothing
    donothing donothing

let rewrap_anything = function
    Ast0.DotsExprTag(d) ->
      Ast0.DotsExprTag(rewrap.V0.rebuilder_expression_dots d)
  | Ast0.DotsInitTag(d) ->
      Ast0.DotsInitTag(rewrap.V0.rebuilder_initialiser_list d)
  | Ast0.DotsParamTag(d) ->
      Ast0.DotsParamTag(rewrap.V0.rebuilder_parameter_list d)
  | Ast0.DotsStmtTag(d) ->
      Ast0.DotsStmtTag(rewrap.V0.rebuilder_statement_dots d)
  | Ast0.DotsDeclTag(d) ->
      Ast0.DotsDeclTag(rewrap.V0.rebuilder_declaration_dots d)
  | Ast0.DotsCaseTag(d) ->
      Ast0.DotsCaseTag(rewrap.V0.rebuilder_case_line_dots d)
  | Ast0.IdentTag(d) -> Ast0.IdentTag(rewrap.V0.rebuilder_ident d)
  | Ast0.ExprTag(d) -> Ast0.ExprTag(rewrap.V0.rebuilder_expression d)
  | Ast0.ArgExprTag(d) -> Ast0.ArgExprTag(rewrap.V0.rebuilder_expression d)
  | Ast0.TestExprTag(d) -> Ast0.TestExprTag(rewrap.V0.rebuilder_expression d)
  | Ast0.TypeCTag(d) -> Ast0.TypeCTag(rewrap.V0.rebuilder_typeC d)
  | Ast0.InitTag(d) -> Ast0.InitTag(rewrap.V0.rebuilder_initialiser d)
  | Ast0.ParamTag(d) -> Ast0.ParamTag(rewrap.V0.rebuilder_parameter d)
  | Ast0.DeclTag(d) -> Ast0.DeclTag(rewrap.V0.rebuilder_declaration d)
  | Ast0.StmtTag(d) -> Ast0.StmtTag(rewrap.V0.rebuilder_statement d)
  | Ast0.CaseLineTag(d) -> Ast0.CaseLineTag(rewrap.V0.rebuilder_case_line d)
  | Ast0.TopTag(d) -> Ast0.TopTag(rewrap.V0.rebuilder_top_level d)
  | Ast0.AnyTag -> failwith "anytag only for isos within iso phase"

(* --------------------------------------------------------------------- *)

let apply_isos isos rule rule_name =
  current_rule := rule_name;
  let isos =
    List.map
      (function (metavars,iso,name) ->
	(metavars,List.map (List.map rewrap_anything) iso,name))
      isos in
  let (extra_meta,rule) =
    List.split
      (List.map
	 (function t ->
	   List.fold_left
	     (function (extra_meta,t) -> function iso ->
	       let (new_extra_meta,t) = transform iso t in
	       (new_extra_meta@extra_meta,t))
	     ([],t) isos)
       rule) in
  (List.concat extra_meta, Compute_lines.compute_lines rule)
