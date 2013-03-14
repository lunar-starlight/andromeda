(** Desugaring of input syntax to internal syntax. *)

(** [index ~loc x xs] finds the location of [x] in the list [xs]. *)
let index ~loc x =
  let rec index k = function
    | [] -> Error.typing ~loc "unknown identifier %s" x
    | y :: ys -> if x = y then k else index (k + 1) ys
  in
    index 0

(** [desugar ctx e] converts an expression of type [Input.expr] to type
    [Syntax.expr] by replacing names in [e] with de Bruijn indices. *)
let desugar ctx =
  let rec desugar xs (e, loc) =
    (match e with
      | Input.Var x -> Syntax.Var (index ~loc x xs)
      | Input.Type -> Syntax.Type
      | Input.Eq (t, e1, e2) -> Syntax.Eq (desugar xs t, desugar xs e1, desugar xs e2)
      | Input.Pi (x, t1, t2) -> Syntax.Pi (x, desugar xs t1, desugar (x :: xs) t2)
      | Input.Lambda (x, None, e) -> Syntax.Lambda (x, None, desugar (x :: xs) e)
      | Input.Lambda (x, Some t, e) -> Syntax.Lambda (x, Some (desugar xs t), desugar (x :: xs) e)
      | Input.App (e1, e2) -> Syntax.App (desugar xs e1, desugar xs e2)
      | Input.Ascribe (e, t) -> Syntax.Ascribe (desugar xs e, desugar xs t)),
    loc
  in
    desugar ctx.Context.names