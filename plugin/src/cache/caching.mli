open Environ
open Constr
open Evd

(* --- Database for higher lifting --- *)

(*
 * Register a lifting to the database
 *)
val declare_lifted : evar_map -> types -> types -> unit

(*
 * Search the database for a lifting (return the reduced version if it exists)
 *)                                       
val search_lifted : env -> types -> types option
                            
(* --- Temporary cache of constants --- *)

type temporary_cache

(*
 * Initialize the local cache
 *)
val initialize_local_cache : unit -> temporary_cache

(*
 * Check whether a constant is in the local cache
 *)
val is_locally_cached : temporary_cache -> types -> bool

(*
 * Lookup a value in the local cache
 *)
val lookup_local_cache : temporary_cache -> types -> types

(*
 * Add a value to the local cache
 *)
val cache_local : temporary_cache -> types -> types -> unit

(* --- Database of ornaments --- *)
      
(* TODO *)
