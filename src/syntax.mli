
(** Terms and types with exposed debruijn index 0 *)
type bare_term

type bare_ty

(** The type of Andromedan terms *)
type term = term' * Position.t
and term' = private
  | Name of Common.name
  | Bound of Common.bound
  | Ascribe of term * ty
  | Lambda of Common.name * ty * bare_ty * bare_term
  | App of (Common.name * ty * ty) * term * term
  | Type
  | Prod of Common.name * ty * ty
  | Eq of ty * term * term
  | Refl of ty * term

(** We do not ditinguish between names of types and types,
    but in the future we may have to. *)
and ty = term

type value =
  | Judge of term * ty
  | String of string

(** Term constructors *)
val mk_name: loc:Position.t -> Common.name -> term
val mk_bound: loc:Position.t -> Common.bound -> term
val mk_ascribe: loc:Position.t -> term -> ty -> term
val mk_lambda: loc:Position.t -> Common.name -> ty -> bare_ty -> term -> term
val mk_app: loc:Position.t -> Common.name -> ty -> bare_ty -> term -> term -> term
val mk_type: loc:Position.t -> term
val mk_prod: loc:Position.t -> Common.name -> ty -> bare_ty -> ty
val mk_eq: loc:Position.t -> ty -> term -> term -> ty
val mk_refl: loc:Position.t -> ty -> term -> term

(** The type Type *)
val typ : ty

(** Alpha equality of terms *)
val equal : term -> term -> bool

(** Alpha equality of types *)
val equal_ty : ty -> ty -> bool

(** Abstract a name to de Bruijn index 0. *)
val abstract : Common.name -> term -> bare_term

(** Instantiate de Bruijn index 0 to a term. *)
val instantiate : term -> bare_term -> term

val instantiate_ty : term -> bare_ty -> ty

val occurs : term -> bool

val occurs_ty : ty -> bool
