(** The type of contexts, currently dummy. *)
type t

(** The empty context. *)
val empty : t

(** Join two contexts into a single one. Return the new context
    and a list of equations that need to be satisfied in order
    for the contexts to be joinable. *)
val join : t -> t -> t * (t * Tt.ty list) list

(** [cone ctx x t] returns a context with a fresh atom [y]
    of type [t], which depends on everything in [ctx]. The assumption
    here is that [t] is a type in [ctx]. The function is called
    [cone] because it produces a cone in the graph-theoretic and topological
    sense of word. *)
val cone : t -> Name.ident -> Tt.ty -> Name.atom * t

(** Remove the given atoms from the context, in the order
    given by the list. Fails if this is not doable. *)
val abstract : loc:Location.t -> t -> Name.atom list -> t

val lookup1 : loc:Location.t -> Name.atom -> t -> Tt.ty option

type renaming

val rename : t -> renaming -> t

val refresh : t -> t * renaming

val print : t -> Format.formatter -> unit

val substitute : t -> Name.atom -> Tt.term -> t
