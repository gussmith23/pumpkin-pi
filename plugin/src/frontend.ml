open Constr
open Names
open Declarations
open Coqterms
open Lifting
open Caching
open Search
open Lift
open Desugar
open Utilities
open Pp
open Printer

(*
 * Identify an algebraic ornament between two types
 * Define the components of the corresponding equivalence
 * (Don't prove section and retraction)
 *)
let find_ornament n_o d_old d_new =
  let (evd, env) = Pfedit.get_current_context () in
  let trm_o = unwrap_definition env (intern env evd d_old) in
  let trm_n = unwrap_definition env (intern env evd d_new) in
  match map_tuple kind (trm_o, trm_n) with
  | Ind ((m_o, _), _), Ind ((m_n, _), _) ->
    let (_, _, lab_o) = KerName.repr (MutInd.canonical m_o) in
    let (_, _, lab_n) = KerName.repr (MutInd.canonical m_n) in
    let name_o = Label.to_id lab_o in
    let name_n = Label.to_string lab_n in
    let auto_n = with_suffix (with_suffix name_o "to") name_n in
    let n = Option.default auto_n n_o in
    let idx_n = with_suffix n "index" in
    let orn = search_orn_inductive env evd idx_n trm_o trm_n in
    ignore (define_term idx_n evd orn.indexer true);
    Printf.printf "Defined indexing function %s.\n\n" (Id.to_string idx_n);
    let promote = define_term n evd orn.promote true in
    Printf.printf "Defined promotion %s.\n\n" (Id.to_string n);
    let inv_n = with_suffix n "inv" in
    let forget = define_term inv_n evd orn.forget true in
    Printf.printf "Defined forgetful function %s.\n\n" (Id.to_string inv_n);
    (try
       save_ornament (trm_o, trm_n) (promote, forget)
     with _ ->
       Printf.printf "WARNING: Failed to cache ornamental promotion.")
  |_ ->
    failwith "Only inductive types are supported"

(*
 * Lift a definition according to a lifting configuration, defining the lifted
 * definition and declaring it as a lifting of the original definition.
 *)
let lift_definition_by_ornament env evd n l c_old =
  let lifted = do_lift_defn env evd l c_old in
  ignore (define_term n evd lifted true);
  try
    let old_gref = Globnames.global_of_constr c_old in
    let new_gref = Globnames.ConstRef (Lib.make_kn n |> Constant.make1) in
    declare_lifted old_gref new_gref;
  with _ ->
    Printf.printf "WARNING: Failed to cache lifting."

(*
 * Lift an inductive type according to a lifting configuration, defining the
 * new lifted version and declaring type-to-type, constructor-to-constructor,
 * and eliminator-to-eliminator liftings.
 *)
let lift_inductive_by_ornament env evm n s l c_old =
  let ind, _ = destInd c_old in
  let ind' = do_lift_ind env evm n s l ind in
  let env' = Global.env () in
  Feedback.msg_notice (str "Defined lifted inductive type " ++ pr_inductive env' ind')

(*
 * Lift the supplied definition or inductive type along the supplied ornament
 * Define the lifted version
 *)
let lift_by_ornament ?(suffix=false) n d_orn d_orn_inv d_old =
  let (evd, env) = Pfedit.get_current_context () in
  let c_orn = intern env evd d_orn in
  let c_orn_inv = intern env evd d_orn_inv in
  let c_old = intern env evd d_old in
  let n_new = if suffix then suffix_term_name c_old n else n in
  let s = if suffix then Id.to_string n else "_" ^ Id.to_string n in
  let are_inds = isInd c_orn && isInd c_orn_inv in
  let lookup os = map_tuple Universes.constr_of_global (lookup_ornament os) in
  let (c_from, c_to) = map_if lookup are_inds (c_orn, c_orn_inv) in
  let l = initialize_lifting env evd c_from c_to in
  if isInd c_old then
    lift_inductive_by_ornament env evd n_new s l c_old
  else
    lift_definition_by_ornament env evd n_new l c_old

(*
 * Translate each fix or match subterm into an equivalent application of an
 * eliminator, defining the new term with the given name.
 *
 * Mutual fix or cofix subterms are not supported.
 *)
let desugar_definition n d =
  let (evm, env) = Pfedit.get_current_context () in
  let term = intern env evm d |> unwrap_definition env in
  let evm, term', _ = desugar_term env evm Constmap.empty term in
  ignore (define_term n evm term' false)

let desugar_constant subst ident const_body =
  (* TODO: Call directly from singular Vernacular command *)
  let evm, env = Pfedit.get_current_context () in
  let term = force_constant_body const_body in
  let evm', term', type' = desugar_term env evm subst term in
  (* TODO: Preserve opacity and other associated properties *)
  (* FIXME: Assertion failure in Declare under interactive module context *)
  ignore (define_term ~typ:type' ident evm' term' true)

let decompose_module_signature mod_sign =
  let rec aux mod_arity mod_sign =
    match mod_sign with
    | MoreFunctor (mod_name, mod_type, mod_sign) ->
      aux ((mod_name, mod_type) :: mod_arity) mod_sign
    | NoFunctor mod_fields ->
      mod_arity, mod_fields
  in
  aux [] mod_sign

(*
 * Translate fix and match expressions into eliminations, as in
 * desugar_definition, compositionally throughout a whole module.
 *)
let desugar_module mod_name mod_ref =
  let mod_path =
    Libnames.qualid_of_reference mod_ref |> CAst.with_val Nametab.locate_module
  in
  let mod_body = Global.lookup_module mod_path in
  let mod_arity, mod_fields = decompose_module_signature mod_body.mod_type in
  (* FIXME: Currently defining translated constants without a wrapping module *)
  (* let mod_path' = Global.start_module mod_name in *)
  let mod_path' = Global.current_modpath () in
  let cache_constant label subst =
    let const = Constant.make2 mod_path label in
    let const' = Constant.make2 mod_path' label in
    Constmap.add const const' subst
  in
  ignore
    begin
      List.fold_left
        (fun subst (label, body) ->
           (* TODO: Axioms? Submodules? *)
           match body with
           | SFBconst const_body ->
             begin
               try
                 desugar_constant subst (Label.to_id label) const_body;
                 cache_constant label subst
               with exn ->
                 let env = Global.env () in
                 let const = Constant.make2 mod_path label in
                 Feedback.msg_debug
                   (str "failed to translate " ++ Printer.pr_constant env const);
                 Feedback.msg_debug (CErrors.print_no_report exn);
                 subst
             end
           | _ -> subst)
        Constmap.empty
        mod_fields
    end
(* ignore (Global.end_module (Summary.freeze_summaries ~marshallable:`Shallow) mod_name None) *)
