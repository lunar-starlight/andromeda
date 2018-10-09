(** Runtime syntax *)

(** Bound variables are de Bruijn indices *)
type bound = int

(** AML type declarations are referred to by de Bruijn levels *)
type level = int

type 'a located = 'a Location.located

type ml_ty = Mlty.ty

type ml_schema = Mlty.ty_schema

type arg_annotation =
  | Arg_annot_none
  | Arg_annot_ty of ml_ty

type let_annotation =
  | Let_annot_none
  | Let_annot_schema of ml_schema

(** Computations *)
type comp = comp' located
and comp' =
  | Bound of bound
  | Function of Name.ident * comp
  | Handler of handler
  | AML_Constructor of Name.ident * comp list
  | Tuple of comp list
  | Operation of Name.ident * comp list
  | With of comp * comp
  | Let of let_clause list * comp
  | LetRec of letrec_clause list * comp
  | Now of comp * comp * comp
  | Current of comp
  | Lookup of comp
  | Update of comp * comp
  | Ref of comp
  | Sequence of comp * comp
  | Assume of (Name.ident * comp) * comp
  | Where of comp * comp * comp
  | Match of comp * match_case list
  | Ascribe of comp * comp
  | TT_Constructor of Name.ident * comp list
  | Apply of comp * comp
  | Abstract of Name.ident * comp option * comp
  | Yield of comp
  | CongrAbstractTy of comp * comp * comp
  | CongrAbstract of comp * comp * comp * comp
  | Reflexivity_type of comp
  | Symmetry_type of comp
  | Transitivity_type of comp * comp
  | Reflexivity_term of comp
  | Symmetry_term of comp
  | Transitivity_term of comp * comp
  | String of string
  | Occurs of comp * comp
  | Context of comp
  | Natural of comp

and let_clause =
  | Let_clause of Pattern.aml * ml_schema * comp

and letrec_clause = Name.ident * Name.ident * ml_schema * comp

and handler = {
  handler_val: match_case list;
  handler_ops: match_op_case list Name.IdentMap.t;
  handler_finally : match_case list;
}

and match_case = Pattern.aml * comp

(** Match multiple patterns at once, with shared pattern variables *)
and match_op_case = Pattern.aml list * Pattern.aml option * comp

type top_op_case = Name.ident list * Name.ident option * comp

type constructor_decl = Name.aml_constructor * ml_ty list

type ml_tydef = Dsyntax.ml_tydef

(** Toplevel commands *)
type toplevel = toplevel' located
and toplevel' =
  | DefMLType of (Name.ty * (Name.ty list * ml_tydef)) list
  | DefMLTypeRec of (Name.ty * (Name.ty list * ml_tydef)) list
  | DeclOperation of Name.operation * (ml_ty list * ml_ty)
  | DeclConstants of Name.constant list * comp
  | DeclExternal of Name.ident * ml_schema * string
  | TopHandle of (Name.operation * top_op_case) list
  | TopLet of let_clause list
  | TopLetRec of letrec_clause list
  | TopDynamic of Name.ident * ml_schema * comp
  | TopNow of comp * comp
  | TopDo of comp
  | TopFail of comp
  | Verbosity of int
  | Included of (string * toplevel list) list
