(** We define an auxiliary "configuration" type which specifies
    exactly what needs to be done during equality checking. *)
type use_hints = {
  use_eqs : bool ; (* use both equations *)
  use_rws : bool   (* use rewrites *)
} 

(********************)
(* Helper Functions *)
(********************)

let print_ty ctx t =
  Print.ty (Context.names ctx) t

let print_term ctx term =
  Print.term (Context.names ctx) term

let print_pattern ctx k p =
  let rec names i =
    if i < k then ("?" ^ string_of_int i) :: names (i + 1) else Context.names ctx
  in
  let rec inst i =
    if i <= k then (i, (Syntax.Var i, Position.nowhere)) :: inst (i+1) else []
  in
  let p = Pattern.shift k 0 p in
  let e = (match Pattern.subst_term (inst 0) 0 p with Pattern.Term e -> e | _ -> assert false) in
    Print.term (names 0) e


(** Signal that pattern matching failed. *)
exception Mismatch

(* Check that an assoc list binds all numbers from 0 to k-1. *)
let rec is_complete_match lst k =
  (k > 0) &&
  (let k = k - 1 in
     List.mem_assoc k lst && is_complete_match lst k)

(*************************)
(* Weak-Head Normalizing *)
(*************************)

let rec whnf_ty ~use_rws ctx ((t',loc) as t) =
  (* Print.debug "whnf_ty: %t" (print_ty ctx t) ; *)
  let whnf = whnf ~use_rws in
  let whnf_ty = whnf_ty ~use_rws in
  begin match t' with

    (* tynorm-el *)
    | Syntax.El (alpha, e) ->
      begin match fst (whnf ctx (Syntax.Universe alpha, loc) e) with
          
        (* tynorm-pi *)
        | Syntax.NameProd (beta, gamma, x, e1, e2) 
            when Universe.eq alpha (Universe.max beta gamma) ->
          let t1 = (Syntax.El (beta, e1), snd e1) in
          let t2 = (Syntax.El (gamma, e2), snd e2) in
            Syntax.Prod (x, t1, t2),
            loc

        (* tynorm-unit *)
        | Syntax.NameUnit ->
          Syntax.Unit,
          loc
            
        (* tynorm-universe *)
        | Syntax.NameUniverse beta
            when Universe.eq alpha (Universe.succ beta) ->
          Syntax.Universe beta,
          loc

        (* tynorm-coerce *)
        | Syntax.Coerce (beta, gamma, e)
            when Universe.eq alpha gamma ->
          whnf_ty ctx (Syntax.El (beta, e), snd e)

        (* tynorm-paths *)
        | Syntax.NamePaths (beta, e1, e2, e3)
            when Universe.eq alpha beta ->
          let t1 = (Syntax.El (alpha, e1), snd e1) in
            Syntax.Paths (t1, e2, e3),
            loc

        (* tynorm-id *)
        | Syntax.NameId (beta, e1, e2, e3) 
            when Universe.eq alpha beta ->
          let t1 = (Syntax.El (alpha, e1), snd e1) in
            Syntax.Id (t1, e2, e3),
            loc

        (* tynorm-other *)
        | (Syntax.Var _ | Syntax.Equation _ | Syntax.Rewrite _ | Syntax.Ascribe _ 
              | Syntax.Lambda _ | Syntax.App _ | Syntax.UnitTerm | Syntax.Idpath _
              | Syntax.J _ | Syntax.Refl _ | Syntax.Coerce _ | Syntax.NameProd _
              | Syntax.NameUniverse _ | Syntax.NamePaths _ | Syntax.NameId _) as e' ->
          Syntax.El (alpha, (e', loc)),
          loc
      end

    | (Syntax.Universe _ | Syntax.Unit | Syntax.Prod _ | Syntax.Paths _ | Syntax.Id _) ->
      t
  end

and whnf ~use_rws ctx t ((e',loc) as e) =
  (* Print.debug "whnf (%b): %t" use_rws (print_term ctx e) ; *)
  let equal_ty' = equal_ty' ~use:{use_eqs=false; use_rws=use_rws}
  and whnf = whnf ~use_rws
  in
  let e =
    begin match e' with

      (* norm-var-def *)
      | Syntax.Var k ->
        begin match Context.lookup_def k ctx with
          | None -> e
          | Some e' -> whnf ctx t e'
        end

      (* norm-equation *)
      | Syntax.Equation (e1, t1, e2) ->
        let h = as_hint' ~use_rws ctx e1 t1 in
          whnf (Context.add_equation h ctx) t e2

      (* norm-rewrite *)
      | Syntax.Rewrite (e1, t1, e2)  ->
        let h = as_hint' ~use_rws ctx e1 t1 in
          whnf (Context.add_rewrite h ctx) t e2

      (* norm-ascribe *)
      | Syntax.Ascribe(e, _) ->
        whnf ctx t e

      | Syntax.App ((x, u1, u2), e1, e2) ->
        begin
          let e1 = whnf ctx (Syntax.Prod (x, u1, u2), loc) e1 in
            match fst e1 with
              (* norm-app-beta *)
              | Syntax.Lambda (y, t1, t2, e1')
                  when equal_ty' ctx u1 t1 && equal_ty' (Context.add_var x u1 ctx) u2 t2 ->
                whnf ctx (Syntax.beta_ty u2 e2) (Syntax.beta e1' e2)

              (* norm-app-other *)
              | _ ->
                Syntax.App ((x, u1, u2), e1, e2), loc
        end
          
      | Syntax.J (t, (x,y,p,u), (z,e1), e2, e3, e4) ->
        begin
          let e2 = whnf ctx (Syntax.Paths (t, e3, e4), loc) e2 in
            match fst e2 with
              (* norm-J-idpath *)
              | Syntax.Idpath (t', e2')
                  when equal_ty' ctx t t' ->
                whnf ctx (Syntax.betas_ty u [e2; e2'; e2]) (Syntax.beta e1 e2')

              (* norm-J-other *)
              | _ ->
                Syntax.J (t, (x, y, p, u), (z, e1), e2, e3, e4), loc
        end

      (* norm-coerce-trivial *)
      | Syntax.Coerce (alpha, beta, e)
          when Universe.eq alpha beta ->
        whnf ctx (Syntax.Universe alpha, loc) e

      | Syntax.Coerce (alpha, beta, e) ->
        begin match whnf ctx (Syntax.Universe alpha, loc) e with
          (* norm-coerce-trans *)
          | (Syntax.Coerce (gamma, delta, e), _) when Universe.eq delta alpha ->
            if Universe.eq gamma beta
            then 
              (* norm-coerce-trivial *)
              e
            else 
              Syntax.Coerce (gamma, beta, e), loc

          (* norm-coerce-other *)
          | e ->
            Syntax.Coerce (alpha, beta, e), loc
        end

      | (Syntax.Lambda _ | Syntax.UnitTerm | Syntax.Idpath _ |
         Syntax.Refl _ | Syntax.NameUnit | Syntax.NameProd _ |
         Syntax.NameUniverse _ | Syntax.NamePaths _ | Syntax.NameId _) ->
        e
    end
  in
    if use_rws
    then rewrite_term ctx e t
    else e

(* [rewrite_term ctx e t hs] attempts to rewrite term [e] of type [t] using
   rewrite hints [hs]. After rewriting it re-runs weak head-normalization
   on the resulting term. *)
and rewrite_term ctx e t =
  Print.debug "rewrite_term:@ %t at@ %t"
    (print_term ctx e) (print_ty ctx t) ;
  let match_hint pt pe1 pe2 =
Print.debug "PHASE 1" ;
    (* match [pe1] against [e] and instantiate, ignore magenta *)
    let inst = match_term ~magenta:false [] 0 ctx pe1 e t in
    let pt = Pattern.subst_ty inst 0 pt
    and pe1 = Pattern.subst_term inst 0 pe1
    and pe2 = Pattern.subst_term inst 0 pe2 in
    (* match [pt] against [e] and instantiate *)
    let inst = match_ty ~magenta:true [] 0 ctx pt t in
    let pt = Pattern.subst_ty inst 0 pt
    and pe1 = Pattern.subst_term inst 0 pe1
    and pe2 = Pattern.subst_term inst 0 pe2 in
      begin match pt, pe1, pe2 with
        | Pattern.Ty t', Pattern.Term e', Pattern.Term e2 ->
          let bt = equal_ty' ~use:{use_eqs=false; use_rws=false} ctx t t'
          and be = equal_term ~use:{use_eqs=false; use_rws=false} ctx e e' t
          in
            Print.debug "COMPARE TYPES %t AND %t RESULT %b" (print_ty ctx t) (print_ty ctx t') bt;
            Print.debug "COMPARE TERMS %t AND %t RESULT %b" (print_term ctx e) (print_term ctx e') be;
            if bt && be
            then e2
            else (Print.debug "final equal fail"; raise Mismatch)
        | _ -> Print.debug "did not get terms" ; raise Mismatch
      end
  in
  let rec match_hints = function
    | [] -> 
      Print.debug "rewrite_term failure" ;
      e
    | (k, pt, pe1, pe2) :: hs ->
      Print.debug "matching hint %t equal %t" (print_pattern ctx k pe1) (print_pattern ctx k pe2) ;
      begin try
        let e2 = match_hint pt pe1 pe2 in
          Print.debug "rewrite_term success ---> %t" (print_term ctx e2) ;
          whnf ~use_rws:true ctx t e2
        with
          | Mismatch -> match_hints hs
      end
  in
  let hs = Context.rewrites ctx in
    match_hints hs

(** See if terms [e1] and [e2] which have type [t] are equal
    *directly* by an equality hint. In other words, try to apply
    chk-eq-hint without any normalization *)
and equal_by_equation ctx t e1 e2 =
  Print.debug "equal_by_equation: %t and %t at %t"
    (print_term ctx e1) (print_term ctx e2) (print_ty ctx t) ;
  let match_hint pt pe1 pe2 =
    (* match [pe1] against [e1] and instantiate, ignore magenta *)
    let inst = match_term ~magenta:false [] 0 ctx pe1 e1 t in
    let pt = Pattern.subst_ty inst 0 pt
    and pe1 = Pattern.subst_term inst 0 pe1
    and pe2 = Pattern.subst_term inst 0 pe2 in
    (* match [pe2] against [e2] and instantiate, ignore magenta *)
    let inst = match_term ~magenta:false [] 0 ctx pe2 e2 t in
    let pt = Pattern.subst_ty inst 0 pt
    and pe1 = Pattern.subst_term inst 0 pe1
    and pe2 = Pattern.subst_term inst 0 pe2 in
    (* match [pt] against [t] and instantiate *)
    let inst = match_ty ~magenta:true [] 0 ctx pt t in
    let pt = Pattern.subst_ty inst 0 pt
    and pe1 = Pattern.subst_term inst 0 pe1
    and pe2 = Pattern.subst_term inst 0 pe2 in
      begin match pt, pe1, pe2 with
        | Pattern.Ty t', Pattern.Term e1', Pattern.Term e2' ->
          if equal_ty' ~use:{use_eqs=false; use_rws=false} ctx t t' &&
             equal_term ~use:{use_eqs=false; use_rws=false} ctx e1 e1' t &&
             equal_term ~use:{use_eqs=false; use_rws=false} ctx e2 e2' t
          then ()
          else (Print.debug "final equal fail"; raise Mismatch)
        | _ -> Print.debug "did not get terms" ; raise Mismatch
      end
  in
  let rec match_hints = function
    | [] -> false
    | (_, pt, pe1, pe2) :: hs ->
      begin try
        match_hint pt pe1 pe2 ;
        true
        with
          | Mismatch -> match_hints hs
      end
  in
    match_hints (Context.equations ctx)

(* equality of types *)
and equal_ty' ~use ctx t u =
  (* Print.debug "Equal.equal_ty': %t and %t" (print_ty ctx t) (print_ty ctx u) ; *)

  (* chk-tyeq-refl *)
  (Syntax.equal_ty t u)

  ||

  begin match Syntax.name_of t, Syntax.name_of u with
    (* chk-tyeq-el *)
    | Some (e1, alpha), Some (e2, beta) ->
      Universe.eq alpha beta && equal_term ~use ctx e1 e2 (Syntax.Universe alpha, snd t)
    | (_, None) | (None, _) -> false
  end

  ||

  begin
    let t = whnf_ty ~use_rws:use.use_rws ctx t
    and u = whnf_ty ~use_rws:use.use_rws ctx u
    in
      equal_whnf_ty ~use ctx (t : Syntax.ty) (u : Syntax.ty)
  end

(* equality of weak-head-normal types *)
and equal_whnf_ty ~use ctx ((t', tloc) as t) ((u', uloc) as u) =
  let equal_ty' = equal_ty' ~use
  and equal_term = equal_term ~use
  in
  begin
    Print.debug "equal_whnf_ty: %t == %t@." (print_ty ctx t) (print_ty ctx u);
    match t', u' with

    (* chk-tyeq-path-refl *)
    | _, _ when Syntax.equal_ty t u ->
        true

    (* chk-tyeq-prod *)
    | Syntax.Prod(x, t1, t2), Syntax.Prod(_, u1, u2) ->
        equal_ty' ctx t1 u1 &&
        equal_ty' (Context.add_var x t1 ctx) t2 u2

    (* chk-tyeq-paths *)
    | Syntax.Paths(t,e1,e2), Syntax.Paths(u,e1',e2') ->
        equal_ty' ctx t u &&
        equal_term ctx e1 e1' t &&
        equal_term ctx e2 e2' t

    (* chk-tyeq-id *)
    | Syntax.Id(t,e1,e2), Syntax.Id(u,e1',e2') ->
        equal_ty' ctx t u &&
        equal_term ctx e1 e1' t &&
        equal_term ctx e2 e2' t

    | (Syntax.Universe _ | Syntax.El _ | Syntax.Unit
       | Syntax.Prod _ | Syntax.Paths _ | Syntax.Id _), _ ->
           false
  end

(* equality of terms.

   Precondition: t is well-formed
                 e1 : t
                 e2 : t
 *)
and equal_term ~use ctx e1 e2 t =

  (* Print.debug "equal_term: %t == %t @@ %t"
      (print_term ctx e1) (print_term ctx e2) (print_ty ctx t) ; *)

  (* chk-eq-refl *)
  (Syntax.equal e1 e2)

  ||

  (* chk-eq-hint *)
  (use.use_eqs && (equal_by_equation ctx t e1 e2 || equal_by_equation ctx t e2 e1))

  ||
  begin
    let t' = whnf_ty ~use_rws:use.use_rws ctx t in
    equal_ext ~use ctx e1 e2 t'
  end


(* Equality of terms at a weak-head-normal type.

   Precondition: ty is well-formed *and weak-head-normal*
                 e1 : ty
                 e2 : ty
 *)
and equal_ext ~use ctx ((_, loc1) as e1) ((_, loc2) as e2) ((t', _) as t) =
  begin
    Print.debug "equal_ext: %t and %t at %t@."
      (print_term ctx e1) (print_term ctx e2) (print_ty ctx t);
    match t' with

    (* chk-eq-ext-prod *)
    | Syntax.Prod(x, t, u) ->
        (* To keep the two x binders straight, we'll call the one in
           the context z. *)
        let ctx' = Context.add_var x t ctx  in   (* ctx' === ctx, z *)
                                           (* ctx       |- e1  : ... *)
        let e1' = Syntax.weaken 0 e1 in    (* ctx, z    |- e1' : ... *)
                                           (* ctx       |- e2  : ... *)
        let e2' = Syntax.weaken 0 e2 in    (* ctx, z    |- e2' : ... *)
                                           (* ctx       |- t  type *)
        let t'  = Syntax.weaken_ty 0 t in  (* ctx, z    |- t' type *)
                                           (* ctx,    x |- u  type *)
        let u' = Syntax.weaken_ty 1 u  in  (* ctx, z, x |- u' type *)
        let z = (Syntax.Var 0,
                 Position.nowhere) in      (* ctx, z    |- z : ... *)
        equal_term ~use ctx'
              (Syntax.App((x, t', u'), e1', z), loc1)
              (Syntax.App((x, t', u'), e2', z), loc2)
              u

    (* chk-eq-ext-unit *)
    | Syntax.Unit ->
        true

    (* chk-eq-ext-K *)
    | Syntax.Id (_, _, _) ->
        true

    (* chk-eq-ext-whnf *)
      | Syntax.Universe _ | Syntax.El _ | Syntax.Paths _ ->
        let e1' = whnf ~use_rws:use.use_rws ctx t e1 in
        let e2' = whnf ~use_rws:use.use_rws ctx t e2  in
        equal_whnf ~use ctx e1' e2' t
  end

(* equality of two weak-head-normal terms.

   Precondition: term1 : ty
                 term2 : ty
                    for some (unspecified) common type ty.
 *)
and equal_whnf ~use ctx ((term1', loc1) as term1) ((term2', loc2) as term2) t =
  let equal_ty' = equal_ty' ~use
  and equal_term = equal_term ~use
  in
  begin
    match term1', term2' with

    (* chk-eq-whnf-reflexivity *)
    | _, _ when Syntax.equal term1 term2 ->
        true

    (* chk-eq-whnf-equation *)
    | _, _ when use.use_eqs && equal_by_equation ctx t term1 term2 ->
        true

    (* chk-eq-whnf-var *)
    | Syntax.Var index1, Syntax.Var index2 -> index1 = index2

    (* chk-eq-whnf-app *)
    | Syntax.App((x, t1, t2), e1, e2), Syntax.App((_, u1, u2), e1', e2') ->
        equal_ty' ctx t1 u1
        && equal_ty' (Context.add_var x t1 ctx) t2 u2
        && equal_whnf ~use ctx e1 e1' (Syntax.Prod (x, t1, t2), loc1)
        && equal_term ctx e2 e2' t1

    (* chk-eq-whnf-idpath *)
    | Syntax.Idpath(t, e1), Syntax.Idpath(u, e2) ->
        equal_ty' ctx t u && equal_term ctx e1 e2 t

    (* chk-eq-whnf-j *)
    | Syntax.J(t1,(x,y,p,u2),(z,e3),e4, e5, e6), Syntax.J(t7, (_,_,_,u8), (_,e9), e10, e11, e12) ->
      let ctx_xyp, ctx_z = Context.for_J t1 x y p z ctx in
      let e3_ty_expected =
                                                         (* ctx,    x, y, p |- u2 type *)
          let u2' = Syntax.weaken_ty 3 u2  in            (* ctx, z, x, y, p |- u2' type *)
                                                         (* ctx    |- t1 type *)
          let t1' = Syntax.weaken_ty 0 t1  in            (* ctx, z |- t1' type *)
          let zvar = (Syntax.Var 0, Position.nowhere) in (* ctx, z |- z *)
          Syntax.strengthen_ty u2'
             [zvar; zvar; (Syntax.Idpath(t1', zvar), Position.nowhere)]
                                              (* ctx, z |- u2'[x,y,p->z,z,idpath z]  type *)  in

        (*
        let j_ty_expected =
          Syntax.strengthen_ty u2 [e5; e6; e4]  in       (* ctx |- u2[x,y,p->e5,e6,e4] *)
        *)

        equal_ty' ctx t1 t7
        && equal_ty' ctx_xyp u2 u8
        && equal_term ctx_z e3 e9 e3_ty_expected
        && equal_term ctx e5 e11 t1
        && equal_term ctx e6 e12 t1
        && equal_whnf ~use ctx e4 e10 (Syntax.Paths (t1, e5, e6), loc1)

    (* chk-eq-whnf-refl *)
    | Syntax.Refl(t, e1), Syntax.Refl(u, e2) ->
        equal_ty' ctx t u && equal_term ctx e1 e2 t

    (* chk-eq-whnf-prod *)
    | Syntax.NameProd(alpha, beta, x, e1, e2), Syntax.NameProd(alpha', beta', _, e1', e2') ->
        Universe.eq alpha alpha' && Universe.eq beta beta'
        && equal_term ctx e1 e1' (Syntax.Universe alpha, Position.nowhere)
        && equal_term (Context.add_var x (Syntax.El(alpha,e1), Position.nowhere) ctx)
                 e2 e2' (Syntax.Universe beta, Position.nowhere)

    (* chk-eq-whnf-universe *)
    | Syntax.NameUniverse alpha, Syntax.NameUniverse beta ->
        Universe.eq alpha beta

    (* chk-eq-whnf-unit *)              (** Subsumed by reflexivity check! *)
    (*| Syntax.NameUnit, Syntax.NameUnit -> true *)

    (* chk-eq-whnf-paths *)
    | Syntax.NamePaths(alpha, e1, e2, e3), Syntax.NamePaths(alpha', e1', e2', e3') ->
        Universe.eq alpha alpha'
        && equal_term ctx e1 e1' (Syntax.Universe alpha, Position.nowhere)
        && equal_term ctx e2 e2' (Syntax.El (alpha, e1), Position.nowhere)
        && equal_term ctx e3 e3' (Syntax.El (alpha, e1), Position.nowhere)

    (* chk-eq-whnf-id *)
    | Syntax.NameId(alpha, e1, e2, e3), Syntax.NameId(alpha', e1', e2', e3') ->
        Universe.eq alpha alpha'
        && equal_term ctx e1 e1' (Syntax.Universe alpha, Position.nowhere)
        && equal_term ctx e2 e2' (Syntax.El (alpha, e1), Position.nowhere)
        && equal_term ctx e3 e3' (Syntax.El (alpha, e1), Position.nowhere)

    (* chk-eq-whnf-coerce *)
    | Syntax.Coerce(alpha, _beta, e1), Syntax.Coerce(alpha', _beta', e1') ->
        Universe.eq alpha alpha'
        && equal_term ctx e1 e1' (Syntax.Universe alpha, Position.nowhere)

    (* chk-eq-whnf-abs *)
    | Syntax.Lambda(x,t1,t2,e1), Syntax.Lambda(_,u1,u2,e2) ->
        equal_ty' ctx t1 u1
        && let ctx' = Context.add_var x t1 ctx  in
           equal_ty' ctx' t2 u2 && equal_term ctx' e1 e2 t2

    (* chk-eq-whnf-unit-right *)
    | _, Syntax.UnitTerm ->
        true

    (* chk-eq-whnf-unit-left *)
    | Syntax.UnitTerm, _ ->
        true

    (* chk-eq-whnf-refl-left *)
    | Syntax.Refl _, _ ->
        true

    (* chk-eq-whnf-refl-right *)
    | _, Syntax.Refl _ ->
        true

    | (Syntax.Var _ | Syntax.Equation _ | Syntax.Rewrite _ | Syntax.Ascribe _
      | Syntax.Lambda _ | Syntax.App _ | Syntax.Idpath _
      | Syntax.J _ | Syntax.Coerce _ | Syntax.NameUnit
      | Syntax.NameProd _ | Syntax.NameUniverse _ | Syntax.NamePaths _
      | Syntax.NameId _), _ -> false
  end

and as_hint' ~use_rws ctx (_, loc) t =
  let rec collect ctx' u =
    match fst (whnf_ty ~use_rws ctx' u) with
      | Syntax.Prod (x, t1, t2) ->
        let (k, t, e1, e2) = collect (Context.add_var x t1 ctx') t2 in
          (k + 1, t, e1, e2)
      | Syntax.Id (t, e1, e2) -> (0, t, e1, e2)
      | Syntax.Universe _ | Syntax.El _ | Syntax.Unit | Syntax.Paths _ ->
        Error.typing ~loc "this expression cannot be used as an equality hint, its type is %t"
          (print_ty ctx t)
  in
  let (k, t, e1, e2) = collect ctx t in
  let pt = Pattern.of_ty k t in
  let pe1 = Pattern.of_term k e1 in
  let pe2 = Pattern.of_term k e2 in
    (k, pt, pe1, pe2)

(* Simple matching of a type pattern against a type. *)
and match_ty ~magenta inst l ctx pt ((t',loc) as t) =
  let match_term = match_term ~magenta
  and match_magenta = if magenta then match_ty ~magenta else (fun inst _ _ _ _ -> inst)
  and match_ty = match_ty ~magenta
  in
  match pt with

    | Pattern.Ty u  ->
      if equal_ty' ~use:{use_eqs=false; use_rws=false} ctx t u
      then inst
      else raise Mismatch

    | Pattern.El (alpha, pe) ->
      begin match Syntax.name_of t with
        | None -> raise Mismatch
        | Some (e', beta) ->
          if Universe.eq alpha beta then
            let t = Syntax.Universe alpha, loc in
              match_term inst l ctx pe e' t
          else
            inst
      end

    | Pattern.Prod (_, pt1, pt2) ->
      begin match as_prod' ~use_rws:false ctx t with
        | None -> raise Mismatch
        | Some (x, t1, t2) ->
          let inst = match_ty inst l ctx pt1 t1 in
          let inst = match_ty inst (l+1) (Context.add_var x t1 ctx) pt2 t2 in
            inst
      end

    | Pattern.Paths (pt, pe1, pe2) ->
      begin match as_paths' ~use_rws:false ctx t with
        | None -> raise Mismatch
        | Some (t, e1, e2) ->
          let inst = match_magenta inst l ctx pt t in
          let inst = match_term inst l ctx pe1 e1 t in
          let inst = match_term inst l ctx pe2 e2 t in
            inst
      end

    | Pattern.Id (pt, pe1, pe2) ->
      begin match as_id' ~use_rws:false ctx t with
        | None -> raise Mismatch
        | Some (t, e1, e2) ->
          let inst = match_magenta inst l ctx pt t in
          let inst = match_term inst l ctx pe1 e1 t in
          let inst = match_term inst l ctx pe2 e2 t in
            inst
      end

(* Simple matching of a term pattern against a term. *)
and match_term ~magenta inst l ctx p e t =
  let match_term = match_term ~magenta
  and match_magenta = if magenta then match_ty ~magenta else (fun inst _ _ _ _ -> inst)
  and match_ty = match_ty ~magenta
  in
  match p with

  | Pattern.Term e' -> 
    if equal_term ~use:{use_eqs=false; use_rws=true} ctx e' e t
    then inst
    else raise Mismatch

  | Pattern.PVar i ->
    begin
      try
        let e' = List.assoc i inst in
        if equal_term ~use:{use_eqs=false; use_rws=true} ctx e' e t
        then inst
        else raise Mismatch
      with
        | Not_found -> (i,e) :: inst
    end

  | Pattern.Lambda (_, pt1, pt2, pe) ->
    begin match fst (whnf ~use_rws:false ctx t e) with
      | Syntax.Lambda (x, t1, t2, e) ->
        let inst = match_ty inst l ctx pt1 t1 in
        let ctx' = Context.add_var x t1 ctx in
        let inst = match_magenta inst (l+1) ctx' pt2 t2 in
        let inst = match_term inst (l+1) ctx' pe e t2 in
          inst
      | _ -> raise Mismatch
    end

  | Pattern.App ((_, pt1, pt2), pe1, pe2) ->
    begin match fst (whnf ~use_rws:false ctx t e) with
      | Syntax.App ((x, t1, t2), e1, e2) ->
        let inst = match_magenta inst l ctx pt1 t1 in
        let inst = match_magenta inst (l+1) (Context.add_var x t1 ctx) pt2 t2 in
        let inst = match_term inst l ctx pe1 e1 (Syntax.Prod (x, t1, t2), Position.nowhere) in
        let inst = match_term inst l ctx pe2 e2 t1 in
          inst
      | _ -> raise Mismatch
    end

  | Pattern.Idpath (pt, pe) ->
    begin match fst (whnf ~use_rws:false ctx t e) with
      | Syntax.Idpath (t, e) ->
        let inst = match_magenta inst l ctx pt t in
        let inst = match_term inst l ctx pe e t in
          inst
      | _ -> raise Mismatch
    end

  | Pattern.J (pt, (_,_,_,pu), (_,pe1), pe2, pe3, pe4) ->
    begin match fst (whnf ~use_rws:false ctx t e) with
      | Syntax.J (t, (x,y,p,u), (z,e1), e2, e3, e4) ->
        let inst = match_magenta inst l ctx pt t in
        let ctx_xyp, ctx_z = Context.for_J t x y p z ctx in
        let inst = match_ty inst (l+3) ctx_xyp pu u in
        let inst = match_term inst (l+1) ctx_z pe1 e1 t in
        let inst = match_term inst l ctx pe2 e2 t in
        (* XXX strictly speaking, [e3] and [e4] are magenta, so we could skip them *)
        let inst = match_term inst l ctx pe3 e3 t in
        let inst = match_term inst l ctx pe4 e4 t in
          inst
      | _ -> raise Mismatch
    end

  | Pattern.Refl (pt, pe) ->
    begin match fst (whnf ~use_rws:false ctx t e) with
      | Syntax.Refl (t, e) ->
        let inst = match_magenta inst l ctx pt t in
        let inst = match_term inst l ctx pe e t in
          inst
      | _ -> raise Mismatch
    end

   (** XXX should switch to comparing type names *)

  | Pattern.Coerce (alpha, beta, pe) ->
    begin match fst (whnf ~use_rws:false ctx t e) with
      | Syntax.Coerce (gamma, delta, e) 
          when Universe.eq alpha gamma && Universe.eq beta delta ->
        let inst = match_term inst l ctx pe e (Syntax.Universe alpha, Position.nowhere) in
          inst
      | _ -> raise Mismatch
    end
    
  | Pattern.NameProd (alpha, beta, _, pe1, pe2) ->
    begin match fst (whnf ~use_rws:false ctx t e) with
      | Syntax.NameProd (gamma, delta, x, e1, e2) 
          when Universe.eq alpha gamma && Universe.eq beta delta ->
        let inst = match_term inst l ctx pe1 e1 (Syntax.Universe gamma, Position.nowhere) in
        let inst =
          match_term
            inst
            (l+1)
            (Context.add_var x (Syntax.El (gamma, e1), Position.nowhere) ctx)
            pe2
            e2
            (Syntax.Universe delta, Position.nowhere)
        in
          inst
      | _ -> raise Mismatch
    end

  | Pattern.NamePaths (alpha, pe1, pe2, pe3) ->
    begin match fst (whnf ~use_rws:false ctx t e) with
      | Syntax.NamePaths (beta, e1, e2, e3) 
          when Universe.eq alpha beta ->
        let inst = match_term inst l ctx pe1 e1 (Syntax.Universe beta, Position.nowhere) in
        let inst = match_term inst l ctx pe2 e1 (Syntax.El (beta, e1), Position.nowhere) in
        let inst = match_term inst l ctx pe3 e1 (Syntax.El (beta, e1), Position.nowhere) in
          inst
      | _ -> raise Mismatch
    end

  | Pattern.NameId (alpha, pe1, pe2, pe3) ->
    begin match fst (whnf ~use_rws:false ctx t e) with
      | Syntax.NameId (beta, e1, e2, e3) 
          when Universe.eq alpha beta ->
        let inst = match_term inst l ctx pe1 e1 (Syntax.Universe beta, Position.nowhere) in
        let inst = match_term inst l ctx pe2 e1 (Syntax.El (beta, e1), Position.nowhere) in
        let inst = match_term inst l ctx pe3 e1 (Syntax.El (beta, e1), Position.nowhere) in
          inst
      | _ -> raise Mismatch
    end

and as_prod' ~use_rws ctx t =
  match fst (whnf_ty ~use_rws ctx t) with

    | Syntax.Prod (x, t1, t2) ->
      Some (x, t1, t2)

    | Syntax.Universe _ | Syntax.El _ | Syntax.Unit | Syntax.Paths _ | Syntax.Id _ ->
      None

and as_universe' ~use_rws ctx t =
  match fst (whnf_ty ~use_rws ctx t) with

    | Syntax.Universe alpha ->
      Some alpha

    | Syntax.El _ | Syntax.Unit | Syntax.Prod _ | Syntax.Paths _ | Syntax.Id _ ->
        None

and as_paths' ~use_rws ctx t =
  match fst (whnf_ty ~use_rws ctx t) with

    | Syntax.Paths (t, e1, e2) ->
      Some (t, e1, e2)

    | Syntax.Universe _ | Syntax.El _ | Syntax.Unit | Syntax.Prod _ | Syntax.Id _ ->
      None

and as_id' ~use_rws ctx t =
  match fst (whnf_ty ~use_rws ctx t) with

    | Syntax.Id (t, e1, e2) ->
      Some (t, e1, e2)

    | Syntax.Universe _ | Syntax.El _ | Syntax.Unit | Syntax.Prod _ | Syntax.Paths _ ->
      None

let equal_ty = equal_ty' ~use:{use_eqs=true;use_rws=true}

let as_prod = as_prod' ~use_rws:true
let as_paths = as_paths' ~use_rws:true
let as_id = as_id' ~use_rws:true
let as_universe = as_universe' ~use_rws:true
let as_hint = as_hint' ~use_rws:true
