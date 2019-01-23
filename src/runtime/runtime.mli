(** Runtime values and computations *)

(** {6 Values} *)

(** The Ocaml equivalent of the ML coercible type *)
type coercible =
  | NotCoercible
  | Convertible of Nucleus.eq_type_abstraction
  | Coercible of Nucleus.is_term_abstraction

(** An ML reference cell. *)
type ml_ref

(** An ML dynamic variable. *)
type ml_dyn

type ml_constructor = Path.level

(** values are "finished" or "computed". They are inert pieces of data. *)
type value =
  | IsTerm of Nucleus.is_term_abstraction      (** A term judgment *)
  | IsType of Nucleus.is_type_abstraction      (** A type judgment *)
  | EqTerm of Nucleus.eq_term_abstraction      (** A term equality *)
  | EqType of Nucleus.eq_type_abstraction      (** A type equality *)
  | Closure of (value,value) closure           (** An ML function *)
  | Handler of handler                         (** Handler value *)
  | Tag of ml_constructor * value list         (** Application of a data constructor *)
  | Tuple of value list                        (** Tuple of values *)
  | Ref of ml_ref                              (** Ref cell *)
  | Dyn of ml_dyn                              (** Dynamic variable *)
  | String of string                           (** String constant (opaque, not a list) *)

and operation_args = { args : value list; checking : Nucleus.is_type_abstraction option }

(** A handler contains ML code for handling zero or more operations,
    plus the default case *)
and handler

(** Maps an ['a] to a ['b comp]. In practice ['b] is usually [value] *)
and ('a,'b) closure

(** A descriptive name of a value, e.g. the name of [Handler _] is ["a handler"] *)
val name_of : value -> string

(** Are ML constructors equal? *)
val equal_tag : ml_constructor -> ml_constructor -> bool

(** {b Value construction} *)

(** Build an [IsTerm] value *)
val mk_is_term : Nucleus.is_term_abstraction -> value

(** Build an [IsType] value *)
val mk_is_type : Nucleus.is_type_abstraction -> value

(** Build an [EqTerm] value *)
val mk_eq_term : Nucleus.eq_term_abstraction -> value

(** Build an [EqType] value *)
val mk_eq_type : Nucleus.eq_type_abstraction -> value

(** Build a [Handler] value *)
val mk_handler : handler -> value

(** Build a [Tag] value *)
val mk_tag : ml_constructor -> value list -> value

(** Build a [Tuple] value *)
val mk_tuple : value list -> value

(** Build a [String] value *)
val mk_string : string -> value


(** {b Value extraction} *)

(** Convert, or fail with [IsTermExpected] *)
val as_is_term : loc:Location.t -> value -> Nucleus.is_term

(** Convert, or fail with [IsTypeExpected] *)
val as_is_type : loc:Location.t -> value -> Nucleus.is_type

(** Convert, or fail with [EqTermExpected] *)
val as_eq_term : loc:Location.t -> value -> Nucleus.eq_term

(** Convert, or fail with [EqTypeExpected] *)
val as_eq_type : loc:Location.t -> value -> Nucleus.eq_type

(** Convert, or fail with [IsTermAbstractionExpected] *)
val as_is_term_abstraction : loc:Location.t -> value -> Nucleus.is_term_abstraction

(** Convert, or fail with [IsTypeAbstractionExpected] *)
val as_is_type_abstraction : loc:Location.t -> value -> Nucleus.is_type_abstraction

(** Convert, or fail with [EqTermAbstractionExpected] *)
val as_eq_term_abstraction : loc:Location.t -> value -> Nucleus.eq_term_abstraction

(** Convert, or fail with [EqTypeAbstractionExpected] *)
val as_eq_type_abstraction : loc:Location.t -> value -> Nucleus.eq_type_abstraction

(** Convert, or fail with [ClosureExpected] *)
val as_closure : loc:Location.t -> value -> (value,value) closure

(** Convert, or fail with [HandlerExpected] *)
val as_handler : loc:Location.t -> value -> handler

(** Convert, or fail with [RefExpected] *)
val as_ref : loc:Location.t -> value -> ml_ref

(** Convert, or fail with [DynExpected] *)
val as_dyn : loc:Location.t -> value -> ml_dyn

(** Convert, or fail with [StringExpected] *)
val as_string : loc:Location.t -> value -> string


(** {b Other operations} *)

(** Check whether two values are equal. *)
val equal_value: value -> value -> bool

(** Check whether the given value represents an ML list *)
val as_list_opt : value -> value list option

(** Pretty-print a value. *)
val print_value :
  ?max_level:Level.t -> names:(Name.t list) -> value -> Format.formatter -> unit


(** {6 Error Handling} *)

(** The runtime errors *)
type error =
  | ExpectedAtom of Nucleus.is_term
  | UnknownExternal of string
  | UnknownConfig of string
  | Inapplicable of value
  | AnnotationMismatch of Nucleus.is_type * Nucleus.is_type_abstraction
  | TypeMismatchCheckingMode of Nucleus.is_term_abstraction * Nucleus.is_type_abstraction
  | UnexpectedAbstraction of Nucleus.is_type
  | TermEqualityFail of Nucleus.is_term * Nucleus.is_term
  | TypeEqualityFail of Nucleus.is_type * Nucleus.is_type
  | UnannotatedAbstract of Name.t
  | MatchFail of value
  | FailureFail of value
  | InvalidComparison
  | InvalidEqualTerm of Nucleus.is_term * Nucleus.is_term
  | InvalidEqualType of Nucleus.is_type * Nucleus.is_type
  | BoolExpected of value
  | ListExpected of value
  | OptionExpected of value
  | IsTypeExpected of value
  | IsTermExpected of value
  | EqTypeExpected of value
  | EqTermExpected of value
  | IsTypeAbstractionExpected of value
  | IsTermAbstractionExpected of value
  | EqTypeAbstractionExpected of value
  | EqTermAbstractionExpected of value
  | AbstractionExpected of value
  | JudgementExpected of value
  | ClosureExpected of value
  | HandlerExpected of value
  | RefExpected of value
  | DynExpected of value
  | StringExpected of value
  | CoercibleExpected of value
  | InvalidConvertible of Nucleus.is_type_abstraction * Nucleus.is_type_abstraction * Nucleus.eq_type_abstraction
  | InvalidCoerce of Nucleus.is_type_abstraction * Nucleus.is_term_abstraction
  | UnhandledOperation of Ident.t * value list
  | InvalidPatternMatch of value
  | InvalidHandlerMatch

(** The exception that is raised on runtime error *)
exception Error of error Location.located

(** Pretty-print a runtime error *)
val print_error : names:(Name.t list) -> error -> Format.formatter -> unit

(** Report a runtime error (raises an Error exception) *)
val error : loc:Location.t -> error -> 'a


(** {6 Computation} *)

(** computations provide a dynamically scoped environment and operations *)
type 'a comp

val mk_closure : (value -> value comp) -> value

(** {b Monadic structure} *)

val bind: 'a comp -> ('a -> 'b comp)  -> 'b comp
val return : 'a -> 'a comp


(** {b Monadic shorthand} *)

val return_unit : value comp

val return_is_term : Nucleus.is_term_abstraction -> value comp
val return_is_type : Nucleus.is_type_abstraction -> value comp
val return_eq_term : Nucleus.eq_term_abstraction -> value comp
val return_eq_type : Nucleus.eq_type_abstraction -> value comp

val return_closure : (value -> value comp) -> value comp
val return_handler :
   (value -> value comp) option ->
   (operation_args -> value comp) Ident.map ->
   (value -> value comp) option ->
   value comp

(** {b Monadic interface} *)

(** A computation that applies the given closure to the given argument
    and produces the result. *)
val apply_closure : ('a,'b) closure -> 'a -> 'b comp

(** A computation that creates and returns a new reference cell. *)
val mk_ref : value -> value comp

(** A computation that dereferences the given reference cell. *)
val lookup_ref : ml_ref -> value comp

(** A computation that updates the given reference cell with the given value. *)
val update_ref : ml_ref -> value -> unit comp

(** A computation that invokes the specified operation. *)
val operation : Ident.t -> ?checking:Nucleus.is_type_abstraction -> value list -> value comp

(** Wrap the given computation with a handler. *)
val handle_comp : handler -> value comp -> value comp

(** Wrap the given computation with a dynamic variable binding. *)
val now : ml_dyn -> value -> 'a comp -> 'a comp

(** Lookup the current continuation. Only usable while handling an operation. *)
val continue : loc:Location.t -> value -> value comp

(** Get the list of names of bound variables *)
val lookup_names : Name.t list comp

(** Gets the current rules of inference. *)
val lookup_signature : Nucleus.signature comp

(** Bound and free variable stuff *)

(* A hack which will probably disappear: add an atom to the dynamic variable
   [hypotheses] *)
val add_abstracting : Nucleus.is_term Nucleus.abstraction -> 'a comp -> 'a comp

(** Add a bound variable to the environment. *)
val add_bound : value -> 'a comp -> 'a comp

val add_bound_rec :
  (value -> value comp) list -> 'a comp -> 'a comp

(** [add_free ~loc x t f] generates a fresh atom [a] from identifier [x],
    and runs [f a] in the environment extended with [a : t].
    NB: This is an effectful computation, as it increases a global counter. *)
val add_free: Name.t -> Nucleus.is_type -> (Nucleus.is_atom -> 'a comp) -> 'a comp

(** Lookup a free variable by its de Bruijn index *)
val lookup_bound : loc:Location.t -> Path.index -> value comp

(** Lookup the current value of a dynamic variable. *)
val lookup_dyn : ml_dyn -> value comp

(** {6 Toplevel} *)

(** state environment, no operations *)
type 'a toplevel

(** {b Monadic structure } *)

val top_bind : 'a toplevel -> ('a -> 'b toplevel) -> 'b toplevel
val top_return : 'a -> 'a toplevel

(** {b Monadic shorthand} *)

val top_return_closure : ('a -> 'b comp) -> ('a,'b) closure toplevel

val top_fold : ('a -> 'b -> 'a toplevel) -> 'a -> 'b list -> 'a toplevel

(** {b Monadic interface} *)

(** Add a bound variable with the given name to the environment. *)
val add_topbound : value -> unit toplevel

(** Add a list of mutually recursive definitions to the toplevel environment. *)
val add_topbound_rec : (value -> value comp) list -> unit toplevel

(** Add a dynamic variable. *)
val add_dynamic : loc:Location.t -> Name.t -> value -> unit toplevel

(** Modify the value bound by a dynamic variable *)
val top_now : ml_dyn -> value -> unit toplevel

(** Extend the signature with a new is_type rule *)
val add_rule_is_type : Ident.t -> Rule.rule_is_type -> unit toplevel

(** Extend the signature with a new is_term rule *)
val add_rule_is_term : Ident.t -> Rule.rule_is_term -> unit toplevel

(** Extend the signature with a new is_type rule *)
val add_rule_eq_type : Ident.t -> Rule.rule_eq_type -> unit toplevel

(** Extend the signature with a new is_term rule *)
val add_rule_eq_term : Ident.t -> Rule.rule_eq_term -> unit toplevel

(** Handle a computation at the toplevel. *)
val top_handle : loc:Location.t -> 'a comp -> 'a toplevel

val top_lookup_names : Name.t list toplevel

(** Get the signature from the toplevel monad *)
val top_lookup_signature : Nucleus.signature toplevel

(** {6 Running a toplevel computation} *)

(** toplevel environment *)
type topenv

(** The empty toplevel environment. *)
val empty : topenv

(** Get the list of rule names (used to print constructors). *)
val get_names : topenv -> Name.t list

(** Execute a toplevel command in the given environment. *)
val exec : 'a toplevel -> topenv -> 'a * topenv

(** {6 Poorly-Documented Functions used by Matching } *)

(** Runtime environment *)
type env

(** Extract the current environment (for matching) *)
val get_env : env comp

(** Run in the given environment (but not the state). *)
val with_env : env -> 'a comp -> 'a comp

(** Get the toplevel environment from the toplevel monad *)
val top_get_env : env toplevel

val get_signature : env -> Nucleus.signature

(** For matching *)
val get_bound : loc:Location.t -> Path.index -> env -> value

(** Add a bound variable (for matching). *)
val push_bound : value -> env -> env

(** {6 Conversion to JSON} *)

module Json :
sig
  val value : value -> Json.t
end
