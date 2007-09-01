(* The error message "no available token to attach to" often comes in an
argument list of unbounded length.  In this case, one should move a comma so
that there is a comma after the + code. *)

(* Start at all of the corresponding BindContext nodes in the minus and
plus trees, and traverse their children.  We take the same strategy as
before: collect the list of minus/context nodes/tokens and the list of plus
tokens, and then merge them. *)

module Ast = Ast_cocci
module Ast0 = Ast0_cocci
module V0 = Visitor_ast0
module CN = Context_neg

let get_option f = function
    None -> []
  | Some x -> f x

(* --------------------------------------------------------------------- *)
(* Collect root and all context nodes in a tree *)

let collect_context e =
  let bind x y = x @ y in
  let option_default = [] in

  let mcode _ = [] in

  let donothing builder r k e =
    match Ast0.get_mcodekind e with
      Ast0.CONTEXT(_) -> (builder e) :: (k e)
    | _ -> k e in

(* special case for everything that contains whencode, so that we skip over
it *)
  let expression r k e =
    donothing Ast0.expr r k
      (Ast0.rewrap e
	 (match Ast0.unwrap e with
	   Ast0.NestExpr(starter,exp,ender,whencode) ->
	     Ast0.NestExpr(starter,exp,ender,None)
	 | Ast0.Edots(dots,whencode) -> Ast0.Edots(dots,None)
	 | Ast0.Ecircles(dots,whencode) -> Ast0.Ecircles(dots,None)
	 | Ast0.Estars(dots,whencode) -> Ast0.Estars(dots,None)
	 | e -> e)) in

  let initialiser r k i =
    donothing Ast0.ini r k
      (Ast0.rewrap i
	 (match Ast0.unwrap i with
	   Ast0.Idots(dots,whencode) -> Ast0.Idots(dots,None)
	 | i -> i)) in

  let statement r k s =
    donothing Ast0.stmt r k
      (Ast0.rewrap s
	 (match Ast0.unwrap s with
	   Ast0.Nest(started,stm_dots,ender,whencode) ->
	     Ast0.Nest(started,stm_dots,ender,None)
	 | Ast0.Dots(dots,whencode) -> Ast0.Dots(dots,[])
	 | Ast0.Circles(dots,whencode) -> Ast0.Circles(dots,[])
	 | Ast0.Stars(dots,whencode) -> Ast0.Stars(dots,[])
	 | s -> s)) in

  let topfn r k e = Ast0.TopTag(e) :: (k e) in

  let res =
    V0.combiner bind option_default
      mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode
      mcode
      (donothing Ast0.dotsExpr) (donothing Ast0.dotsInit)
      (donothing Ast0.dotsParam) (donothing Ast0.dotsStmt)
      (donothing Ast0.dotsDecl) (donothing Ast0.dotsCase)
      (donothing Ast0.ident) expression (donothing Ast0.typeC) initialiser
      (donothing Ast0.param) (donothing Ast0.decl) statement
      (donothing Ast0.case_line) topfn in
  res.V0.combiner_top_level e

(* --------------------------------------------------------------------- *)
(* --------------------------------------------------------------------- *)
(* collect the possible join points, in order, among the children of a
BindContext.  Dots are not allowed.  Nests and disjunctions are no problem,
because their delimiters take up a line by themselves *)

(* An Unfavored token is one that is in a BindContext node; using this causes
  the node to become Neither, meaning that isomorphisms can't be applied *)
(* Toplevel is for the bef token of a function declaration and is for
attaching top-level definitions that should come before the complete
declaration *)
type minus_join_point = Favored | Unfavored | Toplevel | Decl

(* Maps the index of a node to the indices of the mcodes it contains *)
let root_token_table = (Hashtbl.create(50) : (int, int list) Hashtbl.t)

let create_root_token_table minus =
  Hashtbl.iter
    (function tokens ->
      function (node,_) ->
	let key =
	  match node with
	    Ast0.DotsExprTag(d) -> Ast0.get_index d
	  | Ast0.DotsInitTag(d) -> Ast0.get_index d
	  | Ast0.DotsParamTag(d) -> Ast0.get_index d
	  | Ast0.DotsStmtTag(d) -> Ast0.get_index d
	  | Ast0.DotsDeclTag(d) -> Ast0.get_index d
	  | Ast0.DotsCaseTag(d) -> Ast0.get_index d
	  | Ast0.IdentTag(d) -> Ast0.get_index d
	  | Ast0.ExprTag(d) -> Ast0.get_index d
	  | Ast0.ArgExprTag(d) -> failwith "not possible - iso only"
	  | Ast0.TypeCTag(d) -> Ast0.get_index d
	  | Ast0.ParamTag(d) -> Ast0.get_index d
	  | Ast0.InitTag(d) -> Ast0.get_index d
	  | Ast0.DeclTag(d) -> Ast0.get_index d
	  | Ast0.StmtTag(d) -> Ast0.get_index d
	  | Ast0.CaseLineTag(d) -> Ast0.get_index d
	  | Ast0.TopTag(d) -> Ast0.get_index d in
	Hashtbl.add root_token_table key tokens)
    CN.minus_table;
  List.iter
    (function (t,info,index,mcodekind,ty,dots,arg) ->
      try let _ = Hashtbl.find root_token_table !index in ()
      with Not_found -> Hashtbl.add root_token_table !index [])
    minus

let collect_minus_join_points root =
  let root_index = Ast0.get_index root in
  let unfavored_tokens = Hashtbl.find root_token_table root_index in
  let bind x y = x @ y in
  let option_default = [] in

  let mcode (_,_,info,mcodekind) =
    if List.mem (info.Ast0.offset) unfavored_tokens
    then [(Unfavored,info,mcodekind)]
    else [(Favored,info,mcodekind)] in

  let do_nothing r k ((_,info,index,mcodekind,_,_,_) as e) =
    match !mcodekind with
      (Ast0.MINUS(_)) as mc -> [(Favored,info,mc)]
    | (Ast0.CONTEXT(_)) as mc when not(!index = root_index) ->
	(* This was unfavored at one point, but I don't remember why *)
      [(Favored,info,mc)]
    | _ -> k e in

(* don't want to attach to the outside of DOTS, because metavariables can't
bind to that; not good for isomorphisms *)

  let dots f k d =
    let multibind l =
      let rec loop = function
	  [] -> option_default
	| [x] -> x
	| x::xs -> bind x (loop xs) in
      loop l in

    match Ast0.unwrap d with
      Ast0.DOTS(l) -> multibind (List.map f l)
    | Ast0.CIRCLES(l) -> multibind (List.map f l)
    | Ast0.STARS(l) -> multibind (List.map f l) in

  let edots r k d = dots r.V0.combiner_expression k d in
  let idots r k d = dots r.V0.combiner_initialiser k d in
  let pdots r k d = dots r.V0.combiner_parameter k d in
  let sdots r k d = dots r.V0.combiner_statement k d in
  let ddots r k d = dots r.V0.combiner_declaration k d in
  let cdots r k d = dots r.V0.combiner_case_line k d in

  let statement r k s =
    let redo_branched res (ifinfo,aftmc) =
      let redo fv info mc rest =
	let new_info = {info with Ast0.attachable_end = false} in
	List.rev ((Favored,ifinfo,aftmc)::(fv,new_info,mc)::rest) in
      match List.rev res with
	[(fv,info,mc)] ->
	  (match mc with
	    Ast0.MINUS(_) | Ast0.CONTEXT(_) ->
		(* even for -, better for isos not to integrate code after an
		   if into the if body.
		   but the problem is that this can extend the region in
		   which a variable is bound, because a variable bound in the
		   aft node would seem to have to be live in the whole if,
		   whereas we might like it to be live in only one branch.
		   ie ideally, if we can keep the minus code in the right
		   order, we would like to drop it as close to the bindings
		   of its free variables.  This could be anywhere in the minus
		   code.  Perhaps we would like to do this after the
		   application of isomorphisms, though.
		*)
	      redo fv info mc []
	  | _ -> res)
      | (fv,info,mc)::rest ->
	  (match mc with
	    Ast0.CONTEXT(_) -> redo fv info mc rest
	  | _ -> res)
      | _ -> failwith "unexpected empty code" in
    match Ast0.unwrap s with
      Ast0.IfThen(_,_,_,_,_,aft)
    | Ast0.IfThenElse(_,_,_,_,_,_,_,aft)
    | Ast0.While(_,_,_,_,_,aft)
    | Ast0.For(_,_,_,_,_,_,_,_,_,aft)
    | Ast0.Iterator(_,_,_,_,_,aft) ->
	redo_branched (do_nothing r k s) aft
    | Ast0.FunDecl((info,bef),fninfo,name,lp,params,rp,lbrace,body,rbrace) ->
	(Toplevel,info,bef)::(k s)
    | Ast0.Decl((info,bef),decl) -> (Decl,info,bef)::(k s)
    | Ast0.Nest(starter,stmt_dots,ender,whencode) ->
	mcode starter @ r.V0.combiner_statement_dots stmt_dots @ mcode ender
    | Ast0.Dots(d,whencode) | Ast0.Circles(d,whencode)
    | Ast0.Stars(d,whencode) -> mcode d (* ignore whencode *)
    | _ -> do_nothing r k s in

  let initialiser r k e =
    match Ast0.unwrap e with
      Ast0.Idots(d,whencode) -> mcode d (* ignore whencode *)
    | _ -> do_nothing r k e in

  let expression r k e =
    match Ast0.unwrap e with
      Ast0.NestExpr(starter,expr_dots,ender,whencode) ->
	mcode starter @
	r.V0.combiner_expression_dots expr_dots @ mcode ender
    | Ast0.Edots(d,whencode) | Ast0.Ecircles(d,whencode)
    | Ast0.Estars(d,whencode) -> mcode d (* ignore whencode *)
    | _ -> do_nothing r k e in

  let do_top r k (e: Ast0.top_level) = k e in

  V0.combiner bind option_default
    mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode
    mcode
    edots idots pdots sdots ddots cdots
    do_nothing expression do_nothing initialiser do_nothing do_nothing
    statement do_nothing do_top


let call_collect_minus context_nodes :
    (int * (minus_join_point * Ast0.info * Ast0.mcodekind) list) list =
  List.map
    (function e ->
      match e with
	Ast0.DotsExprTag(e) ->
	  (Ast0.get_index e,
	   (collect_minus_join_points e).V0.combiner_expression_dots e)
      | Ast0.DotsInitTag(e) ->
	  (Ast0.get_index e,
	   (collect_minus_join_points e).V0.combiner_initialiser_list e)
      | Ast0.DotsParamTag(e) ->
	  (Ast0.get_index e,
	   (collect_minus_join_points e).V0.combiner_parameter_list e)
      | Ast0.DotsStmtTag(e) ->
	  (Ast0.get_index e,
	   (collect_minus_join_points e).V0.combiner_statement_dots e)
      | Ast0.DotsDeclTag(e) ->
	  (Ast0.get_index e,
	   (collect_minus_join_points e).V0.combiner_declaration_dots e)
      | Ast0.DotsCaseTag(e) ->
	  (Ast0.get_index e,
	   (collect_minus_join_points e).V0.combiner_case_line_dots e)
      | Ast0.IdentTag(e) ->
	  (Ast0.get_index e,
	   (collect_minus_join_points e).V0.combiner_ident e)
      | Ast0.ExprTag(e) ->
	  (Ast0.get_index e,
	   (collect_minus_join_points e).V0.combiner_expression e)
      | Ast0.ArgExprTag(e) -> failwith "not possible - iso only"
      | Ast0.TypeCTag(e) ->
	  (Ast0.get_index e,
	   (collect_minus_join_points e).V0.combiner_typeC e)
      | Ast0.ParamTag(e) ->
	  (Ast0.get_index e,
	   (collect_minus_join_points e).V0.combiner_parameter e)
      | Ast0.InitTag(e) ->
	  (Ast0.get_index e,
	   (collect_minus_join_points e).V0.combiner_initialiser e)
      | Ast0.DeclTag(e) ->
	  (Ast0.get_index e,
	   (collect_minus_join_points e).V0.combiner_declaration e)
      | Ast0.StmtTag(e) ->
	  (Ast0.get_index e,
	   (collect_minus_join_points e).V0.combiner_statement e)
      | Ast0.CaseLineTag(e) ->
	  (Ast0.get_index e,
	   (collect_minus_join_points e).V0.combiner_case_line e)
      | Ast0.TopTag(e) ->
	  (Ast0.get_index e,
	   (collect_minus_join_points e).V0.combiner_top_level e))
    context_nodes

(* result of collecting the join points should be sorted in nondecreasing
   order by line *)
let verify l =
  let get_info = function
      (Favored,info,_) | (Unfavored,info,_) | (Toplevel,info,_)
    | (Decl,info,_) -> info in
  let token_start_line      x = (get_info x).Ast0.logical_start in
  let token_end_line        x = (get_info x).Ast0.logical_end in
  let token_real_start_line x = (get_info x).Ast0.line_start in
  let token_real_end_line   x = (get_info x).Ast0.line_end in
  List.iter
    (function
	(index,((_::_) as l1)) ->
	  let _ =
	    List.fold_left
	      (function (prev,real_prev) ->
		function cur ->
		  let ln = token_start_line cur in
		  if ln < prev
		  then
		    failwith
		      (Printf.sprintf
			 "error in collection of - tokens %d less than %d"
			 (token_real_start_line cur) real_prev);
		  (token_end_line cur,token_real_end_line cur))
	      (token_end_line (List.hd l1), token_real_end_line (List.hd l1))
	      (List.tl l1) in
	  ()
      |	_ -> ()) (* dots, in eg f() has no join points *)
    l

let process_minus minus =
  create_root_token_table minus;
  List.concat
    (List.map
       (function x ->
	 let res = call_collect_minus (collect_context x) in
	 verify res;
	 res)
       minus)

(* --------------------------------------------------------------------- *)
(* --------------------------------------------------------------------- *)
(* collect the plus tokens *)

let mk_baseType x         = Ast.BaseTypeTag x
let mk_structUnion x      = Ast.StructUnionTag x
let mk_sign x             = Ast.SignTag x
let mk_ident x            = Ast.IdentTag (Ast0toast.ident x)
let mk_expression x       = Ast.ExpressionTag (Ast0toast.expression x)
let mk_constant x         = Ast.ConstantTag x
let mk_unaryOp x          = Ast.UnaryOpTag x
let mk_assignOp x         = Ast.AssignOpTag x
let mk_fixOp x            = Ast.FixOpTag x
let mk_binaryOp x         = Ast.BinaryOpTag x
let mk_arithOp x          = Ast.ArithOpTag x
let mk_logicalOp x        = Ast.LogicalOpTag x
let mk_declaration x      = Ast.DeclarationTag (Ast0toast.declaration x)
let mk_topdeclaration x   = Ast.DeclarationTag (Ast0toast.declaration x)
let mk_storage x          = Ast.StorageTag x
let mk_inc_file x         = Ast.IncFileTag x
let mk_statement x        = Ast.StatementTag (Ast0toast.statement x)
let mk_case_line x        = Ast.CaseLineTag (Ast0toast.case_line x)
let mk_const_vol x        = Ast.ConstVolTag x
let mk_token x info       = Ast.Token (x,Some info)
let mk_meta (_,x) info    = Ast.Token (x,Some info)
let mk_code x             = Ast.Code (Ast0toast.top_level x)

let mk_exprdots x  = Ast.ExprDotsTag (Ast0toast.expression_dots x)
let mk_paramdots x = Ast.ParamDotsTag (Ast0toast.parameter_list x)
let mk_stmtdots x  = Ast.StmtDotsTag (Ast0toast.statement_dots x)
let mk_decldots x  = Ast.DeclDotsTag (Ast0toast.declaration_dots x)
let mk_casedots x  = failwith "+ case lines not supported"
let mk_typeC x     = Ast.FullTypeTag (Ast0toast.typeC x)
let mk_init x      = Ast.InitTag (Ast0toast.initialiser x)
let mk_param x     = Ast.ParamTag (Ast0toast.parameterTypeDef x)

let collect_plus_nodes root =
  let root_index = Ast0.get_index root in

  let bind x y = x @ y in
  let option_default = [] in

  let mcode fn (term,_,info,mcodekind) =
    match mcodekind with Ast0.PLUS -> [(info,fn term)] | _ -> [] in

  let imcode fn (term,_,info,mcodekind) =
    match mcodekind with
      Ast0.PLUS -> [(info,fn term (Ast0toast.convert_info info))]
    | _ -> [] in

  let do_nothing fn r k ((term,info,index,mcodekind,ty,dots,arg) as e) =
    match !mcodekind with
      (Ast0.CONTEXT(_)) when not(!index = root_index) -> []
    | Ast0.PLUS -> [(info,fn e)]
    | _ -> k e in

  (* case for everything that is just a wrapper for a simpler thing *)
  let stmt r k e =
    match Ast0.unwrap e with
      Ast0.Exp(exp) -> r.V0.combiner_expression exp
    | Ast0.TopExp(exp) -> r.V0.combiner_expression exp
    | Ast0.Ty(ty) -> r.V0.combiner_typeC ty
    | Ast0.Decl(_,decl) -> r.V0.combiner_declaration decl
    | _ -> do_nothing mk_statement r k e in

  (* statementTag is preferred, because it indicates that one statement is
  replaced by one statement, in single_statement *)
  let stmt_dots r k e =
    match Ast0.unwrap e with
      Ast0.DOTS([s]) | Ast0.CIRCLES([s]) | Ast0.STARS([s]) ->
	r.V0.combiner_statement s
    | _ -> do_nothing mk_stmtdots r k e in

  let toplevel r k e =
    match Ast0.unwrap e with
      Ast0.DECL(s) -> r.V0.combiner_statement s
    | Ast0.CODE(sdots) -> r.V0.combiner_statement_dots sdots
    | _ -> do_nothing mk_code r k e in

  let initdots r k e = k e in

  V0.combiner bind option_default
    (imcode mk_meta) (imcode mk_token) (mcode mk_constant) (mcode mk_assignOp)
    (mcode mk_fixOp)
    (mcode mk_unaryOp) (mcode mk_binaryOp) (mcode mk_const_vol)
    (mcode mk_baseType) (mcode mk_sign) (mcode mk_structUnion)
    (mcode mk_storage) (mcode mk_inc_file)
    (do_nothing mk_exprdots) initdots
    (do_nothing mk_paramdots) stmt_dots (do_nothing mk_decldots)
    (do_nothing mk_casedots)
    (do_nothing mk_ident) (do_nothing mk_expression)
    (do_nothing mk_typeC) (do_nothing mk_init) (do_nothing mk_param)
    (do_nothing mk_declaration)
    stmt (do_nothing mk_case_line) toplevel

let call_collect_plus context_nodes :
    (int * (Ast0.info * Ast.anything) list) list =
  List.map
    (function e ->
      match e with
	Ast0.DotsExprTag(e) ->
	  (Ast0.get_index e,
	   (collect_plus_nodes e).V0.combiner_expression_dots e)
      | Ast0.DotsInitTag(e) ->
	  (Ast0.get_index e,
	   (collect_plus_nodes e).V0.combiner_initialiser_list e)
      | Ast0.DotsParamTag(e) ->
	  (Ast0.get_index e,
	   (collect_plus_nodes e).V0.combiner_parameter_list e)
      | Ast0.DotsStmtTag(e) ->
	  (Ast0.get_index e,
	   (collect_plus_nodes e).V0.combiner_statement_dots e)
      | Ast0.DotsDeclTag(e) ->
	  (Ast0.get_index e,
	   (collect_plus_nodes e).V0.combiner_declaration_dots e)
      | Ast0.DotsCaseTag(e) ->
	  (Ast0.get_index e,
	   (collect_plus_nodes e).V0.combiner_case_line_dots e)
      | Ast0.IdentTag(e) ->
	  (Ast0.get_index e,
	   (collect_plus_nodes e).V0.combiner_ident e)
      | Ast0.ExprTag(e) ->
	  (Ast0.get_index e,
	   (collect_plus_nodes e).V0.combiner_expression e)
      | Ast0.ArgExprTag(_) -> failwith "not possible - iso only"
      | Ast0.TypeCTag(e) ->
	  (Ast0.get_index e,
	   (collect_plus_nodes e).V0.combiner_typeC e)
      | Ast0.InitTag(e) ->
	  (Ast0.get_index e,
	   (collect_plus_nodes e).V0.combiner_initialiser e)
      | Ast0.ParamTag(e) ->
	  (Ast0.get_index e,
	   (collect_plus_nodes e).V0.combiner_parameter e)
      | Ast0.DeclTag(e) ->
	  (Ast0.get_index e,
	   (collect_plus_nodes e).V0.combiner_declaration e)
      | Ast0.StmtTag(e) ->
	  (Ast0.get_index e,
	   (collect_plus_nodes e).V0.combiner_statement e)
      | Ast0.CaseLineTag(e) ->
	  (Ast0.get_index e,
	   (collect_plus_nodes e).V0.combiner_case_line e)
      | Ast0.TopTag(e) ->
	  (Ast0.get_index e,
	   (collect_plus_nodes e).V0.combiner_top_level e))
    context_nodes

(* The plus fragments are converted to a list of lists of lists.
Innermost list: Elements have type anything.  For any pair of successive
elements, n and n+1, the ending line of n is the same as the starting line
of n+1.
Middle lists: For any pair of successive elements, n and n+1, the ending
line of n is one less than the starting line of n+1.
Outer list: For any pair of successive elements, n and n+1, the ending
line of n is more than one less than the starting line of n+1. *)

let logstart info = info.Ast0.logical_start
let logend info = info.Ast0.logical_end

let redo info start finish =
  {{info with Ast0.logical_start = start} with Ast0.logical_end = finish}

let rec find_neighbors (index,l) :
    int * (Ast0.info * (Ast.anything list list)) list =
  let rec loop = function
      [] -> []
    | (i,x)::rest ->
	(match loop rest with
	  ((i1,(x1::rest_inner))::rest_middle)::rest_outer ->
	    let finish1 = logend i in
	    let start2 = logstart i1 in
	    if finish1 = start2
	    then
	      ((redo i (logstart i) (logend i1),(x::x1::rest_inner))
	       ::rest_middle)
	      ::rest_outer
	    else if finish1 + 1 = start2
	    then ((i,[x])::(i1,(x1::rest_inner))::rest_middle)::rest_outer
	    else [(i,[x])]::((i1,(x1::rest_inner))::rest_middle)::rest_outer
	| _ -> [[(i,[x])]]) (* rest must be [] *) in
  let res =
    List.map
      (function l ->
	let (start_info,_) = List.hd l in
	let (end_info,_) = List.hd (List.rev l) in
	(redo start_info (logstart start_info) (logend end_info),
	 List.map (function (_,x) -> x) l))
      (loop l) in
  (index,res)

let process_plus plus :
    (int * (Ast0.info * Ast.anything list list) list) list =
  List.concat
    (List.map
       (function x ->
	 List.map find_neighbors (call_collect_plus (collect_context x)))
       plus)

(* --------------------------------------------------------------------- *)
(* --------------------------------------------------------------------- *)
(* merge *)
(*
let merge_one = function
    (m1::m2::minus_info,p::plus_info) ->
      if p < m1, then
         attach p to the beginning of m1.bef if m1 is Good, fail if it is bad
      if p > m1 && p < m2, then consider the following possibilities, in order
         m1 is Good and favored: attach to the beginning of m1.aft
         m2 is Good and favored: attach to the beginning of m2.bef; drop m1
         m1 is Good and unfavored: attach to the beginning of m1.aft
         m2 is Good and unfavored: attach to the beginning of m2.bef; drop m1
         also flip m1.bef if the first where > m1
         if we drop m1, then flip m1.aft first
      if p > m2
         m2 is Good and favored: attach to the beginning of m2.aft; drop m1
*)

(* end of first argument < start/end of second argument *)
let less_than_start info1 info2 =
  info1.Ast0.logical_end < info2.Ast0.logical_start
let less_than_end info1 info2 =
  info1.Ast0.logical_end < info2.Ast0.logical_end
let greater_than_end info1 info2 =
  info1.Ast0.logical_start > info2.Ast0.logical_end
let good_start info = info.Ast0.attachable_start
let good_end info = info.Ast0.attachable_end

let toplevel = function Toplevel -> true | Favored | Unfavored | Decl -> false
let decl = function Decl -> true | Favored | Unfavored | Toplevel -> false
let favored = function Favored -> true | Unfavored | Toplevel | Decl -> false

let top_code =
  List.for_all (List.for_all (function Ast.Code _ -> true | _ -> false))

(* The following is probably not correct.  The idea is to detect what
should be placed completely before the declaration.  So type/storage
related things do not fall into this category, and complete statements do
fall into this category.  But perhaps other things should be in this
category as well, such as { or ;? *)
let predecl_code =
  let tester = function
      (* the following should definitely be true *)
      Ast.DeclarationTag _
    | Ast.StatementTag _
    | Ast.Rule_elemTag _
    | Ast.StmtDotsTag _
    | Ast.Code _ -> true
      (* the following should definitely be false *)
    | Ast.FullTypeTag _ | Ast.BaseTypeTag _ | Ast.StructUnionTag _
    | Ast.SignTag _
    | Ast.StorageTag _ | Ast.ConstVolTag _ | Ast.TypeCTag _ -> false
      (* not sure about the rest *)
    | _ -> false in
  List.for_all (List.for_all tester)

let pr = Printf.sprintf

let insert thing thinginfo into intoinfo =
  let get_last l = let l = List.rev l in (List.rev(List.tl l),List.hd l) in
  let get_first l = (List.hd l,List.tl l) in
  let thing_start = thinginfo.Ast0.logical_start in
  let thing_end = thinginfo.Ast0.logical_end in
  let thing_offset = thinginfo.Ast0.offset in
  let into_start = intoinfo.Ast0.tline_start in
  let into_end = intoinfo.Ast0.tline_end in
  let into_left_offset = intoinfo.Ast0.left_offset in
  let into_right_offset = intoinfo.Ast0.right_offset in
  Printf.printf "thing start %d thing end %d into start %d into end %d\n"
    thing_start thing_end into_start into_end;
  if thing_end < into_start && thing_start < into_start
  then (thing@into,
	{{intoinfo with Ast0.tline_start = thing_start}
	with Ast0.left_offset = thing_offset})
  else if thing_end = into_start && thing_offset < into_left_offset
  then
    let (prev,last) = get_last thing in
    let (first,rest) = get_first into in
    (prev@[last@first]@rest,
     {{intoinfo with Ast0.tline_start = thing_start}
     with Ast0.left_offset = thing_offset})
  else if thing_start > into_end && thing_end > into_end
  then (into@thing,
	{{intoinfo with Ast0.tline_end = thing_end}
	with Ast0.right_offset = thing_offset})
  else if thing_start = into_end && thing_offset > into_right_offset
  then
    let (first,rest) = get_first thing in
    let (prev,last) = get_last into in
    (prev@[last@first]@rest,
     {{intoinfo with Ast0.tline_end = thing_end}
     with Ast0.right_offset = thing_offset})
  else
    begin
      Printf.printf "thing start %d thing end %d into start %d into end %d\n"
	thing_start thing_end into_start into_end;
      Printf.printf "thing offset %d left offset %d right offset %d\n"
	thing_offset into_left_offset into_right_offset;
      Pretty_print_cocci.print_anything "" thing;
      failwith "can't figure out where to put the + code"
    end

let init thing info =
  (thing,
   {Ast0.tline_start = info.Ast0.logical_start;
     Ast0.tline_end = info.Ast0.logical_end;
     Ast0.left_offset = info.Ast0.offset;
     Ast0.right_offset = info.Ast0.offset})

let attachbefore (infop,p) = function
    Ast0.MINUS(replacements) ->
      (match !replacements with
	([],ti) -> replacements := init p infop
      |	(repl,ti) -> replacements := insert p infop repl ti)
  | Ast0.CONTEXT(neighbors) ->
      let (repl,ti1,ti2) = !neighbors in
      (match repl with
	Ast.BEFORE(bef) ->
	  let (bef,ti1) = insert p infop bef ti1 in
	  neighbors := (Ast.BEFORE(bef),ti1,ti2)
      |	Ast.AFTER(aft) -> 
	  let (bef,ti1) = init p infop in
	  neighbors := (Ast.BEFOREAFTER(bef,aft),ti1,ti2)
      |	Ast.BEFOREAFTER(bef,aft) ->
	  let (bef,ti1) = insert p infop bef ti1 in
	  neighbors := (Ast.BEFOREAFTER(bef,aft),ti1,ti2)
      |	Ast.NOTHING ->
	  let (bef,ti1) = init p infop in
	  neighbors := (Ast.BEFORE(bef),ti1,ti2))
  | _ -> failwith "not possible for attachbefore"

let attachafter (infop,p) = function
    Ast0.MINUS(replacements) ->
      (match !replacements with
	([],ti) -> replacements := init p infop
      |	(repl,ti) -> replacements := insert p infop repl ti)
  | Ast0.CONTEXT(neighbors) ->
      let (repl,ti1,ti2) = !neighbors in
      (match repl with
	Ast.BEFORE(bef) ->
	  let (aft,ti2) = init p infop in
	  neighbors := (Ast.BEFOREAFTER(bef,aft),ti1,ti2)
      |	Ast.AFTER(aft) -> 
	  let (aft,ti2) = insert p infop aft ti2 in
	  neighbors := (Ast.AFTER(aft),ti1,ti2)
      |	Ast.BEFOREAFTER(bef,aft) ->
	  let (aft,ti2) = insert p infop aft ti2 in
	  neighbors := (Ast.BEFOREAFTER(bef,aft),ti1,ti2)
      |	Ast.NOTHING ->
	  let (aft,ti2) = init p infop in
	  neighbors := (Ast.AFTER(aft),ti1,ti2))
  | _ -> failwith "not possible for attachbefore"

let attach_all_before ps m =
  List.iter (function x -> attachbefore x m) ps

let attach_all_after ps m =
  List.iter (function x -> attachafter x m) ps

let split_at_end info ps =
  let split_point =  info.Ast0.logical_end in
  List.partition
    (function (info,_) -> info.Ast0.logical_end < split_point)
    ps

let allminus = function
    Ast0.MINUS(_) -> true
  | _ -> false

let rec before_m1 ((f1,infom1,m1) as x1) ((f2,infom2,m2) as x2) rest = function
    [] -> ()
  | (((infop,_) as p) :: ps) as all ->
      if less_than_start infop infom1 or
	(allminus m1 && less_than_end infop infom1) (* account for trees *)
      then
	if good_start infom1
	then (attachbefore p m1; before_m1 x1 x2 rest ps)
	else
	  failwith
	    (pr "%d: no available token to attach to" infop.Ast0.line_start)
      else after_m1 x1 x2 rest all

and after_m1 ((f1,infom1,m1) as x1) ((f2,infom2,m2) as x2) rest = function
    [] -> ()
  | (((infop,pcode) as p) :: ps) as all ->
      (* if the following is false, then some + code is stuck in the middle
	 of some context code (m1).  could drop down to the token level.
	 this might require adjustments in ast0toast as well, when + code on
	 expressions is dropped down to + code on expressions.  it might
	 also break some invariants on which iso depends, particularly on
	 what it can infer from something being CONTEXT with no top-level
	 modifications.  for the moment, we thus give an error, asking the
	 user to rewrite the semantic patch. *)
      if greater_than_end infop infom1
      then
	if less_than_start infop infom2
	then
	  if predecl_code pcode && good_end infom1 && decl f1
	  then (attachafter p m1; after_m1 x1 x2 rest ps)
	  else if predecl_code pcode && good_start infom2 && decl f2
	  then before_m2 x2 rest all
	  else if top_code pcode && good_end infom1 && toplevel f1
	  then (attachafter p m1; after_m1 x1 x2 rest ps)
	  else if top_code pcode && good_start infom2 && toplevel f2
	  then before_m2 x2 rest all
	  else if good_end infom1 && favored f1
	  then (attachafter p m1; after_m1 x1 x2 rest ps)
	  else if good_start infom2 && favored f2
	  then before_m2 x2 rest all
	  else if good_end infom1
	  then (attachafter p m1; after_m1 x1 x2 rest ps)
	  else if good_start infom2
	  then before_m2 x2 rest all
	  else
	    failwith
	      (pr "%d: no available token to attach to" infop.Ast0.line_start)
	else after_m2 x2 rest all
      else
	begin
	  Printf.printf "between: p start %d p end %d m1 start %d m1 end %d m2 start %d m2 end %d\n"
	    infop.Ast0.line_start infop.Ast0.line_end
	    infom1.Ast0.line_start infom1.Ast0.line_end
	    infom2.Ast0.line_start infom2.Ast0.line_end;
	  Pretty_print_cocci.print_anything "" pcode;
	  failwith
	    "The semantic patch is structured in a way that may give bad results with isomorphisms.  Please try to rewrite it by moving + code out from -/context terms."
	end

and before_m2 ((f2,infom2,m2) as x2) rest
    (p : (Ast0.info * Ast.anything list list) list) =
  match (rest,p) with
    (_,[]) -> ()
  | ([],((infop,_)::_)) ->
      let (bef_m2,aft_m2) = split_at_end infom2 p in (* bef_m2 isn't empty *)
      if good_start infom2
      then (attach_all_before bef_m2 m2; after_m2 x2 rest aft_m2)
      else
	failwith
	  (pr "%d: no available token to attach to" infop.Ast0.line_start)
  | (m::ms,_) -> before_m1 x2 m ms p

and after_m2 ((f2,infom2,m2) as x2) rest
    (p : (Ast0.info * Ast.anything list list) list) =
  match (rest,p) with
    (_,[]) -> ()
  | ([],((infop,_)::_)) ->
      if good_end infom2
      then attach_all_after p m2
      else
	failwith
	  (pr "%d: no available token to attach to" infop.Ast0.line_start)
  | (m::ms,_) -> after_m1 x2 m ms p

let merge_one : (minus_join_point * Ast0.info * 'a) list *
    (Ast0.info * Ast.anything list list) list -> unit = function (m,p) ->
  (*
  Printf.printf "minus code\n";
  List.iter
    (function (_,info,_) ->
      Printf.printf "start %d end %d real_start %d real_end %d\n"
	info.Ast0.logical_start info.Ast0.logical_end
	info.Ast0.line_start info.Ast0.line_end)
    m;
  Printf.printf "plus code\n";
  List.iter
    (function (info,p) ->
      Printf.printf "start %d end %d real_start %d real_end %d\n"
	info.Ast0.logical_start info.Ast0.logical_end
	info.Ast0.line_end info.Ast0.line_end;
      Pretty_print_cocci.print_anything "" p;
      Format.print_newline())
    p;
  *)
  match (m,p) with
    (_,[]) -> ()
  | (m1::m2::restm,p) -> before_m1 m1 m2 restm p
  | ([m],p) -> before_m2 m [] p
  | ([],_) -> failwith "minus tree ran out before the plus tree"

let merge minus_list plus_list =
  (*
  Printf.printf "minus list %s\n"
    (String.concat " "
       (List.map (function (x,_) -> string_of_int x) minus_list));
  Printf.printf "plus list %s\n"
    (String.concat " "
       (List.map (function (x,_) -> string_of_int x) plus_list));
  *)
  List.iter
    (function (index,minus_info) ->
      let plus_info = List.assoc index plus_list in
      merge_one (minus_info,plus_info))
    minus_list

(* --------------------------------------------------------------------- *)
(* --------------------------------------------------------------------- *)
(* Need to check that CONTEXT nodes have nothing attached to their tokens.
If they do, they become MIXED *)

let reevaluate_contextness =
   let bind = (@) in
   let option_default = [] in

   let mcode (_,_,_,mc) =
     match mc with
       Ast0.CONTEXT(mc) -> let (ba,_,_) = !mc in [ba]
     | _ -> [] in

   let donothing r k e =
     match Ast0.get_mcodekind e with
       Ast0.CONTEXT(mc) ->
	 if List.exists (function Ast.NOTHING -> false | _ -> true) (k e)
	 then Ast0.set_mcodekind e (Ast0.MIXED(mc));
	 []
     | _ -> let _ = k e in [] in

  let res =
    V0.combiner bind option_default
      mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode
      mcode
      donothing donothing donothing donothing donothing donothing donothing
      donothing
      donothing donothing donothing donothing donothing donothing donothing in
  res.V0.combiner_top_level

(* --------------------------------------------------------------------- *)
(* --------------------------------------------------------------------- *)
(* add markers for sgrep_mode *)
(* undesirable to add + markers in token stream because then have to parse them
can't merge with the above, because since there is no +, there will be just
one big bind node
in ast, lose easy access to left and rightmost tokens *)

(* first collect mcodes *)
let insert_markers e =
  let bind x y = () in
  let option_default = () in
  let mcode _ = () in

  let donothing r k e = k e in

  let start_marker ln = Ast.SgrepStartTag (Printf.sprintf "%d" ln) in
  let end_marker ln = Ast.SgrepEndTag (Printf.sprintf "%d" ln) in

  let add_start_marker e =
    let start_marker = start_marker ((Ast0.get_info e).Ast0.line_start) in
    match Ast0.get_mcodekind e with
      Ast0.MINUS(info) ->
	let (repl,repl_info) = !info in
	info := ([start_marker]::repl,repl_info)
    | Ast0.CONTEXT(info)
    | Ast0.MIXED(info) ->
	let (ba,before_info,after_info) = !info in
	let new_ba =
	  match ba with
	    Ast.NOTHING -> Ast.BEFORE([[start_marker]])
	  | Ast.BEFORE(bef) -> Ast.BEFORE(bef@[[start_marker]])
	  | Ast.AFTER(aft) -> Ast.BEFOREAFTER([[start_marker]],aft)
	  | Ast.BEFOREAFTER(bef,aft) ->
	      Ast.BEFOREAFTER(bef@[[start_marker]],aft) in
	info := (new_ba,before_info,after_info)
    | _ -> failwith "start: non-context is not possible" in
  
  let add_end_marker e =
    let end_marker = end_marker ((Ast0.get_info e).Ast0.line_end) in
    match Ast0.get_mcodekind e with
      Ast0.MINUS(info) ->
	let (repl,repl_info) = !info in
	info := (repl@[[end_marker]],repl_info)
    | Ast0.CONTEXT(info)
    | Ast0.MIXED(info) ->
	let (ba,before_info,after_info) = !info in
	let new_ba =
	  match ba with
	    Ast.NOTHING -> Ast.AFTER([[end_marker]])
	  | Ast.BEFORE(bef) -> Ast.BEFOREAFTER(bef,[[end_marker]])
	  | Ast.AFTER(aft) -> Ast.AFTER([end_marker]::aft)
	  | Ast.BEFOREAFTER(bef,aft) ->
	      Ast.BEFOREAFTER(bef,[end_marker]::aft) in
	info := (new_ba,before_info,after_info)
    | _ -> failwith "end: non-context is not possible" in

  let rec get_start_statements e =
    match Ast0.unwrap e with
      Ast0.Disj(_,s,_,_) ->
	List.concat
	  (List.map
	     (function sd ->
	       match Ast0.unwrap sd with
		 Ast0.DOTS(x::_) | Ast0.CIRCLES(x::_)
	       | Ast0.STARS(x::_) -> get_start_statements x
	       | _ -> [])
	     s)
    | Ast0.OptStm(s) | Ast0.UniqueStm(s) | Ast0.MultiStm(s) ->
	get_start_statements s
    | _ -> [e] in
  
  let rec get_end_statements e =
    let last l = List.hd(List.rev l) in
    match Ast0.unwrap e with
      Ast0.Disj(_,s,_,_) ->
	List.concat
	  (List.map
	     (function sd ->
	       match Ast0.unwrap sd with
		 Ast0.DOTS((_::_) as l) | Ast0.CIRCLES((_::_) as l)
	       | Ast0.STARS((_::_) as l) -> get_end_statements (last l)
	       | _ -> [])
	     s)
    | Ast0.OptStm(s) | Ast0.UniqueStm(s) | Ast0.MultiStm(s) ->
	get_end_statements s
    | _ -> [e] in
  
  let statement_dots r k e =
    let is_dots e =
      match Ast0.unwrap e with
	Ast0.Dots(_,_) | Ast0.Circles(_,_) | Ast0.Stars(_,_) -> true
      |	Ast0.Nest(_,_,_,_) -> true
      | _ -> false in
    let rec loop dots = function
	[] -> ()
      | x::xs ->
	  (if dots then List.iter add_start_marker (get_start_statements x));
	  (match xs with
	    [] -> ()
	  | y::rest when is_dots y ->
	      List.iter add_end_marker (get_end_statements x); loop true rest
	  | _ -> loop (is_dots x) xs) in
    match Ast0.unwrap e with
      Ast0.DOTS(l) | Ast0.CIRCLES(l) | Ast0.STARS(l) -> loop false l in

  let top_level r k e =
    k e;
    add_start_marker e;
    add_end_marker e in

  let res =
    V0.combiner bind option_default
      mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode
      mcode
      donothing donothing donothing statement_dots donothing donothing
      donothing donothing
      donothing donothing donothing donothing donothing donothing top_level in
  res.V0.combiner_top_level e

(* --------------------------------------------------------------------- *)
(* --------------------------------------------------------------------- *)

let insert_plus minus plus =
  let minus_stream = process_minus minus in
  let plus_stream = process_plus plus in
  merge minus_stream plus_stream;
  if !Flag_parsing_cocci.sgrep_mode
  then List.iter (function minus -> insert_markers minus) minus;
  List.iter (function x -> let _ =  reevaluate_contextness x in ()) minus
