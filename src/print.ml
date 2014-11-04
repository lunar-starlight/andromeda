(** Pretty-printing of Andromedan type theory. *)

(** Printing of messages. *)

let verbosity = ref 2
let annotate = ref false

module StringSet = Set.Make(struct
                                type t = string
                                let compare = compare
                            end)

let displayable = ref (StringSet.singleton "all")

let message msg_type v =
  if v <= !verbosity then
    begin
      Format.eprintf "%s: @[" msg_type ;
      Format.kfprintf (fun ppf -> Format.fprintf ppf "@]@.") Format.err_formatter
    end
  else
    Format.ifprintf Format.err_formatter

let error (loc, err_type, msg) = message (err_type) 1 "%s" msg
let warning msg = message "Warning" 2 msg
let debug ?(category="all") msg =
  if StringSet.mem category (!displayable) then
    message "Debug" 3 msg
  else
    message "Dummy" (!verbosity + 1) msg

(** Given a variable [x] and a list of variable names [xs], find a variant of [x] which
    does not appear in [xs]. *)
let find_name x xs =
  (** Split a variable name into base and numerical postfix, e.g.,
      ["x42"] is split into [("x", 42)]. *)
  let split s =
    let n = String.length s in
    let i = ref (n - 1) in
      while !i >= 0 && '0' <= s.[!i] && s.[!i] <= '9' do decr i done ;
      if !i < 0 || !i = n - 1
      then (s, None)
      else
        let k = int_of_string (String.sub s (!i+1) (n - !i - 1)) in
          (String.sub s 0 (!i+1), Some k)
  in

  if not (List.mem x xs)
  then x
  else
    let (y, k) = split x in
    let k = ref (match k with Some k -> k | None -> 0) in
      while List.mem (y ^ string_of_int !k) xs do incr k done ;
      y ^ string_of_int !k

(** Print an term, possibly placing parentheses around it. We always
    print things at a given [at_level]. If the level exceeds the
    maximum allowed level [max_level] then the term should be parenthesized.

    Let us consider an example. When printing nested applications, we should print [App
    (App (a, b), c)] as ["a b c"] and [App(a, App(a, b))] as ["a (b c)"]. So
    if we assign level 1 to applications, then during printing of [App (e1, e2)] we should
    print [e1] at [max_level] 1 and [e2] at [max_level] 0.
*)
let print ?(max_level=9999) ?(at_level=0) ppf =
  if max_level < at_level then
    begin
      Format.fprintf ppf "(@[" ;
      Format.kfprintf (fun ppf -> Format.fprintf ppf "@])") ppf
    end
  else
    begin
      Format.fprintf ppf "@[" ;
      Format.kfprintf (fun ppf -> Format.fprintf ppf "@]") ppf
    end

(** Optionally print a typing annotation in brackets. *)
let annot ?(prefix="") k ppf =
  if !annotate then
    Format.fprintf ppf "%s[@[%t@]]" prefix k
  else
    Format.fprintf ppf ""

(** Print a sequence of things with the given (optional) separator. *)
let sequence ?(sep="") f lst ppf =
  let rec seq = function
    | [] -> print ppf ""
    | [x] -> print ppf "%t" (f x)
    | x :: xs -> print ppf "%t%s@ " (f x) sep ; seq xs
  in
    seq lst

let name x ppf = print ~at_level:0 ppf "%s" x

(** [prod xs x t1 t2 ppf] prints a dependent product using formatter [ppf]. *)
let rec prod ?max_level xs x t1 t2 ppf =
  if Syntax.occurs_ty t2 then
    let x = find_name x xs in
      print ?max_level ~at_level:3 ppf "forall (%s :@ %t), @ %t"
        x
        (ty ~max_level:4 xs t1)
        (ty ~max_level:3 (x :: xs) t2)
  else
    print ?max_level ~at_level:3 ppf "%t ->@ %t"
      (ty ~max_level:4 xs t1)
      (ty ~max_level:3 (Input.anonymous :: xs) t2)

(** [lambda xs x t u e ppf] prints a lambda abstraction using formatter [ppf]. *)
and lambda xs x t u e ppf =
  let rec collect xs y ys t e =
    let y =
      if Syntax.occurs_ty u || Syntax.occurs e
      then find_name y xs
      else Input.anonymous
    in
      match fst e with
        | Syntax.Lambda (z, t', u, e') ->
          if Syntax.equal_ty t t'
          then collect (y::xs) z (y::ys) t' e'
          else (y::xs, y::ys, e)
        | _ ->
          (y::xs, y::ys, e)
  in
  let rec abstraction xs x t u e ppf =
    if !annotate then
      print ~max_level:4 ppf "(%s :@ %t) =>%t@ %t"
        x
        (ty ~max_level:4 xs t)
        (ty ~max_level:4 (x::xs) u)
        (term ~max_level:4 (x::xs) e)
    else
      let (xs', ys, e) = collect xs x [] t e in
      let ys = List.rev ys in
      print ~at_level:0 ppf "@[<h>(%t :@ %t)@]@ "
          (sequence name ys)
          (ty ~max_level:4 xs t) ;
        match fst e with
          | Syntax.Lambda (x, t, u, e) -> abstraction xs' x t u e ppf
          | _ -> print ~at_level:0 ppf "=>@ %t" (term ~max_level:4 xs' e)
  in
    print ~at_level:3 ppf "@[<hov 2>fun@ %t@]" (abstraction xs x t u e)

and term ?max_level xs (e,_) ppf =
  let print' = print
  and print ?at_level = print ?max_level ?at_level ppf in
    match e with

      | Syntax.Name x ->
        print ~at_level:0 "%s" x

      | Syntax.Bound k ->
          begin
            try
              (*if (!annotate) then                           *)
              (*  print ~at_level:0 "%s<%d>" (List.nth xs k) k*)
              (*else                                          *)
                print ~at_level:0 "%s" (List.nth xs k)
            with
              _ ->
                print ~at_level:0 "BAD_INDEX[%d/%d]" k (List.length xs)
          end

      | Syntax.Ascribe (e, t) ->
        print ~at_level:4 "%t :: %t"
          (term ~max_level:3 xs e)
          (ty ~max_level:4 xs t)

      | Syntax.Lambda (x, t, u, e) ->
        print ~at_level:3 "%t" (lambda xs x t u e)

      | Syntax.App ((x, t, u), e1, e2) ->
          print ~at_level:1 "@[<hov 2>%t%t@ %t@]"
          (term ~max_level:1 xs e1)
          (annot ~prefix:" @"
             (fun ppf -> print' ~max_level:4 ppf "%s :@ %t .@ %t"
                           x
                           (ty ~max_level:4 xs t)
                           (ty ~max_level:4 (x::xs)
                           u)))
          (term ~max_level:0 xs e2)

      | Syntax.Type ->
        print ~at_level:0 "Type"

      | Syntax.Refl (t, e) ->
        print ~at_level:0 "refl%t %t"
          (annot (ty ~max_level:4 xs t))
          (term ~max_level:0 xs e)

      | Syntax.Prod (x, t1, t2) ->
        print ~at_level:3 "%t" (prod xs x t1 t2)

      | Syntax.Eq (t, e1, e2) ->
        print ~at_level:2 "@[<hv 2>%t@ ==%t %t@]"
          (term ~max_level:1 xs e1)
          (annot (ty ~max_level:4 xs t))
          (term ~max_level:1 xs e2)

and ty ?max_level xs e ppf = term ?max_level xs e ppf

let value ?max_level xs v ppf =
  match v with
    | Syntax.Judge (e, t) ->
      print ~at_level:0 ppf "%t : %t"
        (term ~max_level:0 xs e)
        (ty ~max_level:0 xs t)

    | Syntax.String s ->
      print ~at_level:0 ppf "\"%s\"" (String.escaped s)
