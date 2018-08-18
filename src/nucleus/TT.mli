(** Abstract syntax of value types and terms *)

(** An [('a, 'b) abstraction] is a ['b] bound by (x, 'a) *)
type ('a, 'b) abstraction = (Name.ident * 'a) * 'b

type bound

(** A thing labeled with some assumptions. *)
type 'a assumptions = {
  thing : 'a ;
  assumptions : Assumption.t
}

(** The type of TT terms.
    (For details on the mutual definition with [term'], see module Location.)

    We use locally nameless syntax: names for free variables and deBruijn
    indices for bound variables. In terms of type [term], bound variables are
    not allowed to appear "bare", i.e., without an associated binder.
*)
type term = (term' assumptions) Location.located
and term' = private
  (** a free variable *)
  | Atom of Name.atom

  (** a bound variable *)
  | Bound of bound

  (** a constant *)
  | Constant of Name.constant

  (** a lambda abstraction [fun (x1 : t1) -> e : t] *)
  | Abstract of (term * ty) ty_abstraction

  (** an application tagged with the type at wich it happens *)
  | Apply of term * ty ty_abstraction * term

(** Since we have [Type : Type] we do not distinguish terms from types,
    so the type of type [ty] is just a synonym for the type of terms.
    However, we tag types with the [Ty] constructor to avoid nasty bugs. *)

and ty = (ty' assumptions) Location.located
and ty' = private

  (** the universe *)
  | Type

  (** a dependent product [forall (x1 : t1), t] *)
  | Prod of ty ty_abstraction

  (** The extension of an element of the universe. *)
  | El of term

(** A ['a ty_abstraction] is a n abstraction where the [a1, ..., an] are types *)
and 'a ty_abstraction = (ty, 'a) abstraction

(** Term constructors, these do not check for legality of constructions. *)
val mk_atom: loc:Location.t -> Name.atom -> term
val mk_constant: loc:Location.t -> Name.ident -> term
val mk_abstract: loc:Location.t -> Name.ident -> ty -> term -> ty -> term
val mk_apply: loc:Location.t -> term -> Name.ident -> ty -> ty -> term -> term

val mk_type: loc:Location.t -> ty
val mk_prod: loc:Location.t -> Name.ident -> ty -> ty -> ty
val mk_el: loc:Location.t -> term -> ty

(** The type Type (without location) *)
val typ : ty

(** Add the given set of atoms as assumption to a term. *)
val mention_atoms : Name.AtomSet.t -> term -> term

val mention_atoms_ty : Name.AtomSet.t -> ty -> ty

(** Add an assumption to a term. *)
val mention : Assumption.t -> term -> term

(** [instantiate [e0,...,e{n-1}] k e] replaces bound variables indexed by [k, ..., k+n-1]
    with terms [e0, ..., e{n-1}]. *)
val instantiate: term list -> ?lvl:int -> term -> term

val instantiate_ty: term list -> ?lvl:int -> ty -> ty

(** [unabstract [x0,...,x{n-1}] k e] replaces bound variables in [e] indexed by [k, ..., k+n-1]
    with names [x0, ..., x{n-1}]. *)
val unabstract: Name.atom list -> ?lvl:int -> term -> term

(** [unabstract_ty [x0,...,x{n-1}] k t] replaces bound variables in [t] indexed by [k, ..., k+n-1]
    with names [x0, ..., x{n-1}]. *)
val unabstract_ty: Name.atom list -> ?lvl:int -> ty -> ty

(** [abstract xs k e] replaces names [xs] in term [e] with bound variables [k, ..., k+n-1] where
    [xs] is the list [x0,...,x{n-1}]. *)
val abstract : Name.atom list -> ?lvl:int -> term -> term

val abstract_ty : Name.atom list -> ?lvl:int -> ty -> ty

(** abstract followed by instantiate *)
val substitute : Name.atom list -> term list -> term -> term

val substitute_ty : Name.atom list -> term list -> ty -> ty

(** The asssumptions used by a term. *)
val assumptions_term : term -> Name.AtomSet.t

(** The assumptions used by a type. *)
val assumptions_ty : ty -> Name.AtomSet.t

(** [alpha_equal e1 e2] returns [true] if term [e1] and [e2] are alpha equal. *)
val alpha_equal: term -> term -> bool

(** [alpha_equal_ty t1 t2] returns [true] if types [t1] and [t2] are alpha equal. *)
val alpha_equal_ty: ty -> ty -> bool

type print_env =
  { forbidden : Name.ident list ;
    atoms : Name.atom_printer ; }

val print_ty : ?max_level:Level.t -> penv:print_env -> ty -> Format.formatter -> unit
val print_term : ?max_level:Level.t -> penv:print_env -> term -> Format.formatter -> unit

module Json :
sig

  (** Convert a term to JSON *)
  val term : term -> Json.t

  (** Convert a type to JSON *)
  val ty : ty -> Json.t

end
