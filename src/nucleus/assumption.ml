module BoundSet = Set.Make (struct
                    type t = int
                    let compare = compare
                  end)

module AtomMap = Name.AtomMap

type 'a t = { free : 'a AtomMap.t; bound : BoundSet.t }

let empty = { free = AtomMap.empty; bound = BoundSet.empty }

let is_empty {free;bound} =
  AtomMap.is_empty free && BoundSet.is_empty bound

let mem_atom x s = AtomMap.mem x s.free

let mem_bound k s = BoundSet.mem k s.bound

let shift lvl s =
  { s with
    bound = BoundSet.fold
              (fun k s -> if k < lvl then s else BoundSet.add (k - lvl) s)
              s.bound BoundSet.empty }

let singleton_free x t =
  {free = AtomMap.add x t AtomMap.empty; bound = BoundSet.empty}

let singleton_bound k =
  {free = AtomMap.empty; bound = BoundSet.singleton k}

let add_free x t asmp = {asmp with free = AtomMap.add x t asmp.free}

let add_bound k asmp = {asmp with bound = BoundSet.add k asmp.bound}

let union a1 a2 =
  { free = AtomMap.union (fun _ t1 t2 -> assert (t1 == t2) ; Some t1) a1.free a2.free
  ; bound = BoundSet.union a1.bound a2.bound
  }

let instantiate l0 ~lvl asmp =
  if BoundSet.mem lvl asmp.bound
  then
    { free = AtomMap.union (fun _ t1 t2 -> assert (t1 == t2) ; Some t1) asmp.free l0.free
    ; bound = BoundSet.union (BoundSet.remove lvl asmp.bound) l0.bound }
    (* XXX think whether the above is correct, in particular:
       1. could tehre be bound variables larger than lvl in asmp.bound, and if so, should they be shifted?
       2. do we need to reindex the bound variables of l0 or some such? *)
  else
    asmp

let abstract x ~lvl abstr =
  if AtomMap.mem x abstr.free
  then
    { free = AtomMap.remove x abstr.free
    ; bound = BoundSet.add lvl abstr.bound
    }
  else
    abstr

let bind1 {free;bound} =
  let bound = BoundSet.fold (fun n bound ->
      if n = 0
      then bound
      else BoundSet.add (n - 1) bound)
    bound BoundSet.empty
  in
  {free;bound}

let equal {free=free1;bound=bound1} {free=free2;bound=bound2} =
  AtomMap.equal (fun t1 t2 -> assert (t1 == t2) ; true) free1 free2 && BoundSet.equal bound1 bound2

module Json =
struct

  let assumptions {free; bound} =
    let free =
      if AtomMap.is_empty free
      then []
      else [("free", Name.Json.atommap free)]
    and bound =
      if BoundSet.is_empty bound
      then []
      else [("bound", Json.List (List.map (fun k -> Json.Int k) (BoundSet.elements bound)))]
    in
      Json.record (free @ bound)

end
