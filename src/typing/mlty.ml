type meta = {
  meta_index : int ;
  (* If we've shown this metavariable to the user, then
     [meta_shown] contains the string that was used *)
  mutable meta_shown : string option ;
}

let meta_compare {meta_index=i;_} {meta_index=j;_} = Pervasives.compare i j

let eq_meta {meta_index=i;_} {meta_index=j;_} = (i = j)

type param = int

let eq_param (i : param) j = (i = j)

module MetaSet = Set.Make(struct
  type t = meta
  let compare = meta_compare
  end)

let fresh_meta : unit -> meta =
  let counter = ref 0 in
  fun () ->
    let i = !counter in
    incr counter;
    { meta_index = i ; meta_shown = None }

let fresh_param : unit -> param =
  let counter = ref 0 in
  fun () ->
    let p = !counter in
    incr counter;
    p

module MetaOrd = struct
  type t = meta
  let compare = meta_compare
end

type judgement =
  | IsType
  | IsTerm
  | EqType
  | EqTerm

type abstracted_judgement =
  | NotAbstract of judgement
  | Abstract of abstracted_judgement

type ty =
  | Judgement of abstracted_judgement
  | String
  | Meta of meta
  | Param of param
  | Prod of ty list
  | Arrow of ty * ty
  | Handler of ty * ty
  | Apply of Path.t * ty list
  | Ref of ty
  | Dynamic of ty

type tt_constructor = abstracted_judgement list * judgement

let is_type = Judgement (NotAbstract IsType)

let is_term = Judgement (NotAbstract IsTerm)

let eq_type = Judgement (NotAbstract EqType)

let unit_ty = Prod []

let fresh_type () = Meta (fresh_meta ())

let rec shift mdl = function

  | (Judgement _ | String | Meta _ | Param _) as t -> t

  | Prod ts ->
     let ts = List.map (shift mdl) ts in
     Prod ts

  | Arrow (t1, t2) ->
     let t1 = shift mdl t1
     and t2 = shift mdl t2
     in Arrow (t1, t2)

  | Handler (t1, t2) ->
     let t1 = shift mdl t1
     and t2 = shift mdl t2
     in Handler (t1, t2)

  | Apply (pth, ts) ->
     let pth =
       match pth with
       | Path.Direct l -> Path.Module (mdl, l)
       | Path.Module _ -> pth
     and ts = List.map (shift mdl) ts in
     Apply (pth, ts)

  | Ref t ->
      let t = shift mdl t in
      Ref t

  | Dynamic t ->
      let t = shift mdl t in
      Dynamic t


(** Type parameters are generalised in the following values. *)
type 'a forall = param list * 'a

type ty_schema = ty forall

type ty_def =
  | Alias of ty forall
  | Sum of (Name.t * ty list) list forall

type error =
  | InvalidApplication of ty * ty * ty
  | TypeMismatch of ty * ty
  | UnsolvedApp of ty * ty * ty
  | HandlerExpected of ty
  | RefExpected of ty
  | DynamicExpected of ty
  | UnknownExternal of string
  | ValueRestriction
  | Ungeneralizable of param list * ty
  | UnknownJudgementForm
  | JudgementExpected of ty
  | AbstractionExpected of judgement
  | UnexpectedJudgementAbstraction of judgement

exception Error of error Location.located

let error ~loc err = Pervasives.raise (Error (Location.locate err loc))

(** We expect that most type metavariables are never shown to the user,
    and thus we reindex the ones that are shown to the user. We could
    keep around a reindexing map, but that would create a memory leak,
    so instead we keep a global counter and let metavariables carry
    their own indices.

    We still need to keep around a counter telling us how many metas
    were shown to the user.
*)
let meta_counter = ref 0

(*
    On the other hand, type parameters are local, so we use a fresh
    mapping every time we print a type.
*)
type print_env = (param * string) list ref

let fresh_penv () = ref []

let print_meta (m : meta) ppf =
  let s =
    match m.meta_shown with
    | Some s -> s
    | None ->
       let s = Name.greek !meta_counter in
       m.meta_shown <- Some s ;
       incr meta_counter ;
       s
  in
  Format.fprintf ppf "_%s" s

let print_param ~penv (p : param) ppf =
  let s =
    try List.assoc p !penv
    with Not_found ->
      let l = List.length !penv in
      let s = Name.greek l in
      penv := (p, s) :: !penv;
      s
  in
  Format.fprintf ppf "%s" s

let print_judgement frm ppf =
  Format.fprintf ppf
  (match frm with
   | IsType -> "is_type"
   | IsTerm -> "is_term"
   | EqType -> "eq_type"
   | EqTerm -> "eq_term")

let rec print_abstracted_judgement abstr ppf =
  match abstr with
  | NotAbstract frm -> print_judgement frm ppf
  | Abstract abstr ->
     Format.fprintf ppf "{}%t"
       (print_abstracted_judgement abstr)

let rec print_ty ~penv ?max_level t ppf =
  match t with

  | Judgement abstr -> print_abstracted_judgement abstr ppf

  | String -> Format.fprintf ppf "mlstring"

  | Meta m -> print_meta m ppf

  | Param p -> print_param ~penv p ppf

  | Prod [] -> Format.fprintf ppf "mlunit"

  | Prod ts -> Print.print ?max_level ~at_level:Level.ml_prod ppf "@[<hov 1>%t@]"
                 (Print.sequence (print_ty ~penv ~max_level:Level.ml_prod_arg) " *" ts)

  | Arrow (t1, t2) ->
     Print.print ?max_level ~at_level:Level.ml_arr ppf "%t@ %s@ %t"
                 (print_ty ~penv ~max_level:(Level.ml_arr_left) t1)
                 (Print.char_arrow ())
                 (print_ty ~penv ~max_level:(Level.ml_arr_right) t2)

  | Handler (t1, t2) ->
     Print.print ?max_level ~at_level:(Level.ml_handler) ppf "%t@ %s@ %t"
                 (print_ty ~penv ~max_level:(Level.ml_handler_left) t1)
                 (Print.char_darrow ())
                 (print_ty ~penv ~max_level:(Level.ml_handler_right) t2)

  | Apply (pth, []) ->
     Format.fprintf ppf "%t" (Path.print pth)

  | Apply (pth, ts) ->
     Print.print ?max_level ~at_level:Level.ml_app ppf "%t@ %t"
                 (Path.print pth)
                 (Print.sequence (print_ty ~penv ~max_level:Level.ml_app_arg) "" ts)

  | Ref t -> Print.print ?max_level ~at_level:Level.ml_app ppf "ref@ %t"
                        (print_ty ~penv ~max_level:Level.ml_app_arg t)

  | Dynamic t -> Print.print ?max_level~at_level:Level.ml_app ppf "dynamic@ %t"
                        (print_ty ~penv ~max_level:Level.ml_app_arg t)

let print_ty_schema ~penv ?max_level (ms, t) ppf =
  match ms with
    | [] ->
      print_ty ~penv ?max_level t ppf
    | _ :: _ ->
      Format.fprintf ppf "mlforall@ %t,@ %t"
                     (Print.sequence (print_param ~penv) "" ms)
                     (print_ty ~penv ~max_level:Level.ml_forall_r t)

let print_error err ppf =
  let penv = fresh_penv () in
  match err with

  | InvalidApplication (h, arg, out) ->
    Format.fprintf ppf "invalid application of@ @[<hov>%t]@ to@ @[<hov>%t]@ producing@ @[<hov>%t]"
      (print_ty ~penv h)
      (print_ty ~penv arg)
      (print_ty ~penv out)

  | TypeMismatch (t1, t2) ->
    Format.fprintf ppf "expected@ @[%t@] but got@ @[%t@]"
      (print_ty ~penv t2)
      (print_ty ~penv t1)

  | UnsolvedApp (h, arg, out) ->
    Format.fprintf ppf "unsolved application of@ @[<hov>%t]@ to@ @[<hov>%t]@ producing@ @[<hov>%t]"
      (print_ty ~penv h)
      (print_ty ~penv arg)
      (print_ty ~penv out)

  | HandlerExpected t ->
    Format.fprintf ppf "expected a handler but got@ @[<hov>%t]"
      (print_ty ~penv t)

  | RefExpected t ->
    Format.fprintf ppf "expected a reference but got@ @[<hov>%t]"
      (print_ty ~penv t)

  | DynamicExpected t ->
    Format.fprintf ppf "expected a dynamic but got@ @[<hov>%t]"
      (print_ty ~penv t)

  | UnknownExternal s ->
    Format.fprintf ppf "unknown external %s" s

  | ValueRestriction ->
     Format.fprintf ppf "this computation cannot be polymorphic (value restriction)"

  | Ungeneralizable (ps, ty) ->
     Format.fprintf ppf "cannot generalize@ @[<hov>%t]@ in@ @[<hov>%t]"
                    (Print.sequence (print_param ~penv) "," ps)
                    (print_ty ~penv ty)

  | UnknownJudgementForm ->
     Format.fprintf ppf "cannot infer the judgement form"

  | JudgementExpected t ->
    Format.fprintf ppf "expected a judgement but got@ @[<hov>%t]"
      (print_ty ~penv t)

  | AbstractionExpected t ->
    Format.fprintf ppf "expected an abstraction but got@ @[<hov>%t]"
      (print_judgement t)

  | UnexpectedJudgementAbstraction jdg_actual ->
     Format.fprintf ppf "expected@ @[<hov>%t]@ but got an abstraction"
       (print_judgement jdg_actual)

let rec occurs m = function
  | Judgement _ | String | Param _ -> false
  | Meta m' -> eq_meta m m'
  | Prod ts  | Apply (_, ts) -> List.exists (occurs m) ts
  | Arrow (t1, t2) | Handler (t1, t2) -> occurs m t1 || occurs m t2
  | Ref t | Dynamic t -> occurs m t

let rec occuring = function
  | Judgement _ | String | Param _ -> MetaSet.empty
  | Meta m -> MetaSet.singleton m
  | Prod ts  | Apply (_, ts) ->
    List.fold_left (fun s t -> MetaSet.union s (occuring t)) MetaSet.empty ts
  | Arrow (t1, t2) | Handler (t1, t2) ->
    MetaSet.union (occuring t1) (occuring t2)
  | Ref t | Dynamic t -> occuring t

let occuring_schema ((_, t) : ty_schema) : MetaSet.t =
  occuring t

let instantiate pus t =
  let rec inst = function

    | Judgement _ | String | Meta _ as t -> t

    | Param p as t ->
       begin
         try
           List.assoc p pus
         with Not_found -> t
       end

    | Prod ts ->
       let ts = List.map inst ts in
       Prod ts

    | Arrow (t1, t2) ->
       let t1 = inst t1
       and t2 = inst t2 in
       Arrow (t1, t2)

    | Handler (t1, t2) ->
       let t1 = inst t1
       and t2 = inst t2 in
       Handler (t1, t2)

    | Apply (pth, ts) ->
       let ts = List.map inst ts in
       Apply (pth, ts)

    | Ref t ->
       let t = inst t in
       Ref t

    | Dynamic t ->
       let t = inst t in
       Dynamic t

  in
  inst t

let params_occur ps t =
  let rec occurs = function
  | Judgement _ | String | Meta _ -> false
  | Param p -> List.mem p ps
  | Prod ts  | Apply (_, ts) ->
    List.exists occurs ts
  | Arrow (t1, t2) | Handler (t1, t2) ->
    occurs t1 || occurs t2
  | Ref t | Dynamic t -> occurs t
  in
  occurs t
