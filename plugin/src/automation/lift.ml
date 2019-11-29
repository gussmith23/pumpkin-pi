(*
 * Core lifting algorithm
 *)

open Util
open Constr
open Environ
open Zooming
open Lifting
open Debruijn
open Utilities
open Indexing
open Hypotheses
open Names
open Caching
open Declarations
open Specialization
open Inference
open Typehofs
open Indutils
open Apputils
open Sigmautils
open Reducers
open Envutils
open Funutils
open Constutils
open Stateutils
open Hofs

(* --- Convenient shorthand --- *)

let dest_sigT_type = on_red_type_default (ignore_env dest_sigT)

(* --- Internal lifting configuration --- *)

(*
 * Lifting configuration, along with the types A and B, 
 * a cache for constants encountered as the algorithm traverses,
 * and a cache for the constructor rules that refolding determines
 *)
type lift_config =
  {
    l : lifting;
    typs : types * types;
    constr_rules : types array;
    cache : temporary_cache
  }

(* --- Index/deindex functions --- *)

let index l = insert_index (Option.get l.off)
let deindex l = remove_index (Option.get l.off)

(* --- Recovering types from ornaments --- *)

(*
 * Get the types A, B, and IB from the ornament
 * TODO my chai tea at Peet's in portland tastes like someone put something in 
 * it. The time is 2:11 PM. I got up to go to the bathroom at 1:30 PM or so for
 * a few minutes and left it there. Documenting it here in case anything
 * happens to me.
 *
 * Also, please stop following me.
 *)
let typs_from_orn l env sigma =
  let (a_i_t, b_i_t) = on_red_type_default (ignore_env ind_of_promotion_type) env sigma l.orn.promote in
  let a_t = first_fun a_i_t in
  match l.orn.kind with
  | Algebraic ->
     let b_t = zoom_sig b_i_t in
     let i_b_t = (dest_sigT b_i_t).index_type in
     (a_t, b_t, Some i_b_t)
  | CurryRecord ->
     let open Printing in
     debug_term env b_i_t "b_i_t";
     failwith "not yet implemented"

(* --- Premises --- *)

(*
 * Determine whether a type is the type we are ornamenting from
 * That is, A when we are promoting, and B when we are forgetting
 *)
let is_from c env sigma typ =
  let (a_typ, b_typ) = c.typs in
  if c.l.is_fwd then
    is_or_applies a_typ typ
  else
    if is_or_applies sigT typ then
      equal b_typ (first_fun (dummy_index env sigma (dest_sigT typ).packer))
    else
      false

(* 
 * Determine whether a term has the type we are ornamenting from
 *)
let type_is_from c env sigma trm =
  on_red_type
    reduce_nf
    (fun env sigma trm -> sigma, is_from c env sigma trm)
    env
    sigma
    trm

(* Premises for LIFT-CONSTR *)
let is_packed_constr c env sigma trm =
  let right_type = type_is_from c env sigma in
  match kind trm with
  | Construct _  ->
     right_type trm
  | App (f, args) ->
     if c.l.is_fwd then
       if isConstruct f then
         right_type trm
       else
         sigma, false
     else
       if equal existT f then
         let sigma, is_right_type = right_type trm in
         if is_right_type then
           let last_arg = last (Array.to_list args) in
           sigma, isApp last_arg && isConstruct (first_fun last_arg)
         else
           sigma, false
       else
         sigma, false
  | _ ->
     sigma, false

(* Premises for LIFT-PACKED *)
let is_packed c env sigma trm =
  let right_type = type_is_from c env sigma in
  if c.l.is_fwd then
    if isRel trm then
      right_type trm
    else
      sigma, false
  else
    match kind trm with
    | App (f, args) ->
       if equal existT f then
         right_type trm
       else
         sigma, false
    | _ ->
       sigma, false

(* Premises for LIFT-PROJ *)
let is_proj c env sigma trm =
  let right_type = type_is_from c env sigma in
  match kind trm with
  | App _ ->
     let f = first_fun trm in
     let args = unfold_args trm in
     if c.l.is_fwd then
       if equal (Option.get c.l.orn.indexer) f then
         right_type (last args)
       else
         sigma, false
     else
       if (equal projT1 f || equal projT2 f) then
         right_type (last args)
       else
         sigma, false
  | _ ->
     sigma, false

(* Premises for LIFT-ELIM *)
let is_eliminator c env trm =
  let (a_typ, b_typ) = c.typs in
  match kind trm with
  | App (f, args) when isConst f ->
     let maybe_ind = inductive_of_elim env (destConst f) in
     if Option.has_some maybe_ind then
       let ind = Option.get maybe_ind in
       equal (mkInd (ind, 0)) (directional c.l a_typ b_typ)
     else
       false
  | _ ->
     false

(* --- Configuring the constructor liftings --- *)
       
(*
 * For packing constructor aguments: Pack, but only if it's B
 *)
let pack_to_typ env sigma c unpacked =
  let (_, b_typ) = c.typs in
  if on_red_type_default (ignore_env (is_or_applies b_typ)) env sigma unpacked then
    pack env (Option.get c.l.off) unpacked sigma
  else
    sigma, unpacked

(*
 * NORMALIZE (the result of this is cached)
 *)
let lift_constr env sigma c trm =
  let l = c.l in
  let args = unfold_args (map_backward last_arg l trm) in
  let pack_args (sigma, args) = map_state (fun arg sigma -> pack_to_typ env sigma c arg) args sigma in
  let sigma, packed_args = map_backward pack_args l (sigma, args) in
  let sigma, rec_args = filter_state (fun tr sigma -> type_is_from c env sigma tr) packed_args sigma in
  let sigma, app = lift env l trm sigma in
  if List.length rec_args = 0 then
    (* base case - don't bother refolding *)
    reduce_nf env sigma app
  else
    (* inductive case - refold *)
    refold l env (lift_to l) app rec_args sigma

(*
 * Wrapper around NORMALIZE
 *)
let initialize_constr_rule c env constr sigma =
  let sigma, constr_exp = expand_eta env sigma constr in
  let (env_c_b, c_body) = zoom_lambda_term env constr_exp in
  let c_body = reduce_stateless reduce_term env_c_b sigma c_body in
  let sigma, to_refold = map_backward (fun (sigma, t) -> pack env_c_b (Option.get c.l.off) t sigma) c.l (sigma, c_body) in
  let sigma, refolded = lift_constr env_c_b sigma c to_refold in
  sigma, reconstruct_lambda_n env_c_b refolded (nb_rel env)

(*
 * Run NORMALIZE for all constructors, so we can cache the result
 *)
let initialize_constr_rules env sigma c =
  let (a_typ, b_typ) = c.typs in
  let ((i, i_index), u) = destInd (directional c.l a_typ b_typ) in
  let mutind_body = lookup_mind i env in
  let ind_bodies = mutind_body.mind_packets in
  let ind_body = ind_bodies.(i_index) in
  map_state_array
    (initialize_constr_rule c env)
    (Array.mapi
       (fun c_index _ -> mkConstructU (((i, i_index), c_index + 1), u))
       ind_body.mind_consnames)
    sigma

(* Initialize the lift_config *)
let initialize_lift_config env sigma l typs =
  let cache = initialize_local_cache () in
  let c = { l ; typs ; constr_rules = Array.make 0 (mkRel 1) ; cache } in
  let sigma, constr_rules = initialize_constr_rules env sigma c in
  sigma, { c with constr_rules }

(* --- Lifting the induction principle --- *)

(*
 * This implements the rules for lifting the eliminator.
 * The rules here look a bit different because of de Bruijn indices,
 * some optimizations, and non-primitive eliminators.
 *)

(*
 * In LIFT-ELIM, this is what gets a or the projection of b
 * The one difference is that there are extra arguments because of
 * non-primitve eliminators, and also parameters
 *)
let lift_elim_args env sigma l npms args =
  let arg = map_backward last_arg l (last args) in
  let sigma, typ_args = non_index_typ_args (Option.get l.off) env sigma arg in
  let lifted_arg = mkAppl (lift_to l, snoc arg typ_args) in
  let value_off = List.length args - 1 in
  let l = { l with off = Some (Option.get l.off - npms) } in (* we no longer have parameters *)
  if l.is_fwd then
    (* project and index *)
    let b_sig = lifted_arg in
    let b_sig_typ = dest_sigT_type env sigma b_sig in
    let i_b = project_index b_sig_typ b_sig in
    let b = project_value b_sig_typ b_sig in
    sigma, index l i_b (reindex value_off b args)
  else
    (* don't project and deindex *)
    let a = lifted_arg in
    sigma, deindex l (reindex value_off a args)

(*
 * MOTIVE
 *)
let lift_motive env sigma l npms parameterized_elim p =
  let sigma, parameterized_elim_type = reduce_type env sigma parameterized_elim in
  let (_, p_to_typ, _) = destProd parameterized_elim_type in
  let env_p_to = zoom_env zoom_product_type env p_to_typ in
  let nargs = new_rels2 env_p_to env in
  let p = shift_by nargs p in
  let args = mk_n_rels nargs in
  let sigma, lifted_arg = pack_lift env_p_to (flip_dir l) (last args) sigma in
  let value_off = nargs - 1 in
  let l = { l with off = Some (Option.get l.off - npms) } in (* no parameters here *)
  if l.is_fwd then
    (* forget packed b to a, don't project, and deindex *)
    let a = lifted_arg in
    let args = deindex l (reindex value_off a args) in
    let p_app = reduce_stateless reduce_term env_p_to sigma (mkAppl (p, args)) in
    sigma, reconstruct_lambda_n env_p_to p_app (nb_rel env)
  else
    (* promote a to packed b, project, and index *)
    let b_sig = lifted_arg in
    let b_sig_typ = dest_sigT_type env_p_to sigma b_sig in
    let i_b = project_index b_sig_typ b_sig in
    let b = project_value b_sig_typ b_sig in
    let args = index l i_b (reindex value_off b args) in
    let p_app = reduce_stateless reduce_term env_p_to sigma (mkAppl (p, args)) in
    sigma, reconstruct_lambda_n env_p_to p_app (nb_rel env)

(*
 * The argument rules for lifting eliminator cases in the promotion direction.
 * Note that since we save arguments and reduce at the end, this looks a bit
 * different, and the call to new is no longer necessary.
 *)
let promote_case_args env sigma c args =
  let (_, b_typ) = c.typs in
  let rec lift_args sigma args i_b =
    match args with
    | n :: tl ->
       if equal n i_b then
         (* DROP-INDEX *)
         Util.on_snd
           (fun tl -> shift n :: tl)
           (lift_args sigma (shift_all tl) i_b)
       else
         let sigma, t = reduce_type env sigma n in
         if is_or_applies b_typ t then
           (* FORGET-ARG *)
           let sigma, a = pack_lift env (flip_dir c.l) n sigma in
           Util.on_snd
             (fun tl -> a :: tl)
             (lift_args sigma tl (get_arg (Option.get c.l.off) t))
         else
           (* ARG *)
           Util.on_snd (fun tl -> n :: tl) (lift_args sigma tl i_b)
    | _ ->
       (* CONCL in inductive case *)
       sigma, []
  in lift_args sigma args (mkRel 0)

(*
 * The argument rules for lifting eliminator cases in the forgetful direction.
 * Note that since we save arguments and reduce at the end, this looks a bit
 * different, and the call to new is no longer necessary.
 *)
let forget_case_args env_c_b env sigma c args =
  let (_, b_typ) = c.typs in
  let rec lift_args sigma args (i_b, proj_i_b) =
    match args with
    | n :: tl ->
       if equal n i_b then
         (* ADD-INDEX *)
         Util.on_snd
           (fun tl -> proj_i_b :: tl)
           (lift_args sigma (unshift_all tl) (i_b, proj_i_b))
       else
         let sigma, t = reduce_type env_c_b sigma n in
         if is_or_applies b_typ t then
           (* PROMOTE-ARG *)
           let sigma, b_sig =  pack_lift env (flip_dir c.l) n sigma in
           let b_sig_typ = dest_sigT_type env sigma b_sig in
           let proj_b = project_value b_sig_typ b_sig in
           let proj_i_b = project_index b_sig_typ b_sig in
           Util.on_snd
             (fun tl -> proj_b :: tl)
             (lift_args sigma tl (get_arg (Option.get c.l.off) t, proj_i_b))
         else
           (* ARG *)
           Util.on_snd
             (fun tl -> n :: tl)
             (lift_args sigma tl (i_b, proj_i_b))
    | _ ->
       (* CONCL in inductive case *)
       sigma, []
  in lift_args sigma args (mkRel 0, mkRel 0)

(* Common wrapper function for both directions *)
let lift_case_args env_c_b env sigma c args =
  let lifter =
    if c.l.is_fwd then
      promote_case_args
    else
      forget_case_args env_c_b
  in Util.on_snd List.rev (lifter env sigma c (List.rev args))

(*
 * CASE
 *)
let lift_case env sigma c p c_elim constr =
  let (a_typ, b_typ) = c.typs in
  let to_typ = directional c.l b_typ a_typ in
  let sigma, c_eta = expand_eta env sigma constr in
  let sigma, c_elim_type = reduce_type env sigma c_elim in
  let (_, to_c_typ, _) = destProd c_elim_type in
  let nihs = num_ihs env sigma to_typ to_c_typ in
  if nihs = 0 then
    (* base case *)
    sigma, constr
  else
    (* inductive case---need to get the arguments *)
    let env_c = zoom_env zoom_product_type env to_c_typ in
    let nargs = new_rels2 env_c env in
    let c_eta = shift_by nargs c_eta in
    let (env_c_b, c_body) = zoom_lambda_term env_c c_eta in
    let (c_f, c_args) = destApp c_body in
    let split_i = if c.l.is_fwd then nargs - nihs else nargs + nihs in
    let (c_args, b_args) = take_split split_i (Array.to_list c_args) in
    let c_args = unshift_all_by (List.length b_args) c_args in
    let sigma, args = lift_case_args env_c_b env_c sigma c c_args in
    let f = unshift_by (new_rels2 env_c_b env_c) c_f in
    let body = reduce_stateless reduce_term env_c sigma (mkAppl (f, args)) in
    sigma, reconstruct_lambda_n env_c body (nb_rel env)

(* Lift cases *)
let lift_cases env c p p_elim cs =
  bind
    (fold_left_state
       (fun (p_elim, cs) constr sigma ->
         let sigma, constr = lift_case env sigma c p p_elim constr in
         let p_elim = mkAppl (p_elim, [constr]) in
         sigma, (p_elim, snoc constr cs))
       (p_elim, [])
       cs)
    (fun (_, cs) -> ret cs)

(*
 * LIFT-ELIM steps before recursing into the rest of the algorithm
 *)
let lift_elim env sigma c trm_app =
  let (a_t, b_t) = c.typs in
  let to_typ = directional c.l b_t a_t in
  let npms = List.length trm_app.pms in
  let elim = type_eliminator env (fst (destInd to_typ)) in
  let param_elim = mkAppl (elim, trm_app.pms) in
  let sigma, p = lift_motive env sigma c.l npms param_elim trm_app.p in
  let p_elim = mkAppl (param_elim, [p]) in
  let sigma, cs = lift_cases env c p p_elim trm_app.cs sigma in
  let sigma, final_args = lift_elim_args env sigma c.l npms trm_app.final_args in
  sigma, apply_eliminator {trm_app with elim; p; cs; final_args}

(*
 * REPACK
 *
 * This is to deal with non-primitive projections
 *)
let repack env ib_typ lifted typ =
  let lift_typ = dest_sigT (shift typ) in
  let n = project_index lift_typ (mkRel 1) in
  let b = project_value lift_typ (mkRel 1) in
  let packer = lift_typ.packer in
  let e = pack_existT {index_type = ib_typ; packer; index = n; unpacked = b} in
  mkLetIn (Anonymous, lifted, typ, e)
    
(* --- Core algorithm --- *)

(*
 * Core lifting algorithm for algebraic ornaments.
 * A few extra rules to deal with real Coq terms as opposed to CIC,
 * including caching.
 *)
let lift_algebraic env sigma c ib_typ trm =
  let l = c.l in
  let (a_typ, b_typ) = c.typs in
  let sigma, a_typ_eta = expand_eta env sigma a_typ in
  let a_arity = arity a_typ_eta in
  let rec lift_rec en sigma ib_typ tr : types state =
    let (sigma, lifted), try_repack =
      let lifted_opt = search_lifted_term en sigma tr in
      if Option.has_some lifted_opt then
        (* GLOBAL CACHING *)
        (sigma, Option.get lifted_opt), false
      else if is_locally_cached c.cache tr then
        (* LOCAL CACHING *)
        (sigma, lookup_local_cache c.cache tr), false
      else if is_from c en sigma tr then
        (* EQUIVALENCE *)
        if l.is_fwd then
          let sigma, is = map_rec_args lift_rec en sigma ib_typ (Array.of_list (unfold_args tr)) in
          let b_is = mkApp (b_typ, is) in
          let n = mkRel 1 in
          let abs_ib = reindex_body (reindex_app (index l n)) in
          let packer = abs_ib (mkLambda (Anonymous, ib_typ, shift b_is)) in
          (sigma, pack_sigT { index_type = ib_typ; packer }), false
        else
          let packed = dummy_index en sigma (dest_sigT tr).packer in
          let is = deindex l (unfold_args packed) in
          (sigma, mkAppl (a_typ, is)), false
      else
        let sigma, run_lift_constr = is_packed_constr c en sigma tr in
        if run_lift_constr then
          (* LIFT-CONSTR *)
          (* The extra logic here is an optimization *)
          (* It also deals with the fact that we are lazy about eta *)
          let inner = map_backward last_arg l tr in
          let constr = first_fun inner in
          let args = unfold_args inner in
          let (((_, _), i), _) = destConstruct constr in
          let lifted_constr = c.constr_rules.(i - 1) in
          map_if
            (fun ((sigma, tr'), _) ->
              let lifted_inner = map_forward last_arg l tr' in
              let (f', args') = destApp lifted_inner in
              let sigma, args'' = map_rec_args lift_rec en sigma ib_typ args' in
              map_forward
                (fun ((sigma, b), _) ->
                  (* pack the lifted term *)
                  let ex = dest_existT tr' in
                  let sigma, n = lift_rec en sigma ib_typ ex.index in
                  let sigma, packer = lift_rec en sigma ib_typ ex.packer in
                  (sigma, pack_existT { ex with packer; index = n; unpacked = b }), false)
                l
                ((sigma, mkApp (f', args'')), false))
            (List.length args > 0)
            (reduce_term en sigma (mkAppl (lifted_constr, args)), false)
        else
          let sigma, run_lift_pack = is_packed c en sigma tr in
          if run_lift_pack then
            (* LIFT-PACK (extra rule for non-primitive projections) *)
            if l.is_fwd then
              (sigma, tr), true
            else
              lift_rec en sigma ib_typ (dest_existT tr).unpacked, false
          else
            let sigma, run_coherence = is_proj c en sigma tr in
            if run_coherence then
              (* COHERENCE *)
              if l.is_fwd then
                let a = last_arg tr in
                let sigma, b_sig = lift_rec en sigma ib_typ a in
                let sigma, a_typ = reduce_type en sigma a in
                let sigma, b_sig_typ = Util.on_snd dest_sigT (lift_rec en sigma ib_typ a_typ) in
                (sigma, project_index b_sig_typ b_sig), false
              else
                let b_sig = last_arg tr in
                let sigma, a = lift_rec en sigma ib_typ b_sig in
                if equal projT1 (first_fun tr) then
                  let sigma, args = non_index_typ_args (Option.get l.off) en sigma b_sig in
                  (sigma, mkAppl (Option.get l.orn.indexer, snoc a args)), false
                else
                  (sigma, a), false
            else if is_eliminator c en tr then
              (* LIFT-ELIM *)
              let sigma, tr_eta = expand_eta en sigma tr in
              if arity tr_eta > arity tr then
                (* lazy eta expansion; recurse *)
                lift_rec en sigma ib_typ tr_eta, false
              else
                let sigma, tr_elim = deconstruct_eliminator en sigma tr in
                let npms = List.length tr_elim.pms in
                let value_i = a_arity - npms in
                let (final_args, post_args) = take_split (value_i + 1) tr_elim.final_args in
                let sigma, tr' = lift_elim en sigma c { tr_elim with final_args } in
                let sigma, tr'' = lift_rec en sigma ib_typ tr' in
                let sigma, post_args' = map_rec_args lift_rec en sigma ib_typ (Array.of_list post_args) in
                (sigma, mkApp (tr'', post_args')), l.is_fwd
            else
              match kind tr with
              | App (f, args) ->
                 if equal (lift_back l) f then
                   (* SECTION/RETRACTION *)
                   lift_rec en sigma ib_typ (last_arg tr), false
                 else if equal (lift_to l) f then
                   (* INTERNALIZE *)
                   lift_rec en sigma ib_typ (last_arg tr), false
                 else
                   (* APP *)
                   let sigma, args' = map_rec_args lift_rec en sigma ib_typ args in
                   if (is_or_applies projT1 tr || is_or_applies projT2 tr) then
                     (* optimize projections of existentials, which are common *)
                     let arg' = last (Array.to_list args') in
                     let arg'' = reduce_stateless reduce_term en sigma arg' in
                     if is_or_applies existT arg'' then
                       let ex' = dest_existT arg'' in
                       if equal projT1 f then
                         (sigma, ex'.index), false
                       else
                         (sigma, ex'.unpacked), false
                     else
                       let sigma, f' = lift_rec en sigma ib_typ f in
                       (sigma, mkApp (f', args')), false
                   else
                     let sigma, f' = lift_rec en sigma ib_typ f in
                     (sigma, mkApp (f', args')), l.is_fwd
              | Cast (ca, k, t) ->
                 (* CAST *)
                 let sigma, ca' = lift_rec en sigma ib_typ ca in
                 let sigma, t' = lift_rec en sigma ib_typ t in
                 (sigma, mkCast (ca', k, t')), false
              | Prod (n, t, b) ->
                 (* PROD *)
                 let sigma, t' = lift_rec en sigma ib_typ t in
                 let en_b = push_local (n, t) en in
                 let sigma, b' = lift_rec en_b sigma (shift ib_typ) b in
                 (sigma, mkProd (n, t', b')), false
              | Lambda (n, t, b) ->
                 (* LAMBDA *)
                 let sigma, t' = lift_rec en sigma ib_typ t in
                 let en_b = push_local (n, t) en in
                 let sigma, b' = lift_rec en_b sigma (shift ib_typ) b in
                 (sigma, mkLambda (n, t', b')), false
              | LetIn (n, trm, typ, e) ->
                 (* LETIN *)
                 if l.is_fwd then
                   let sigma, trm' = lift_rec en sigma ib_typ trm in
                   let sigma, typ' = lift_rec en sigma ib_typ typ in
                   let en_e = push_let_in (n, trm, typ) en in
                   let sigma, e' = lift_rec en_e sigma (shift ib_typ) e in
                   (sigma, mkLetIn (n, trm', typ', e')), false
                 else
                   (* Needed for #58 we implement #42 *)
                   lift_rec en sigma ib_typ (reduce_stateless whd en sigma tr), false
              | Case (ci, ct, m, bs) ->
                 (* CASE (will not work if this destructs over A; preprocess first) *)
                 let sigma, ct' = lift_rec en sigma ib_typ ct in
                 let sigma, m' = lift_rec en sigma ib_typ m in
                 let sigma, bs' = map_rec_args lift_rec en sigma ib_typ bs in
                 (sigma, mkCase (ci, ct', m', bs')), false
              | Fix ((is, i), (ns, ts, ds)) ->
                 (* FIX (will not work if this destructs over A; preprocess first) *)
                 let sigma, ts' = map_rec_args lift_rec en sigma ib_typ ts in
                 let sigma, ds' = map_rec_args (fun env sigma a trm -> map_rec_env_fix lift_rec shift en sigma a ns ts trm) en sigma ib_typ ds in
                 (sigma, mkFix ((is, i), (ns, ts', ds'))), false
              | CoFix (i, (ns, ts, ds)) ->
                 (* COFIX (will not work if this destructs over A; preprocess first) *)
                 let sigma, ts' = map_rec_args lift_rec en sigma ib_typ ts in
                 let sigma, ds' = map_rec_args (fun env sigma a trm -> map_rec_env_fix lift_rec shift en sigma a ns ts trm) en sigma ib_typ ds in
                 (sigma, mkCoFix (i, (ns, ts', ds'))), false
              | Proj (pr, co) ->
                 (* PROJ *)
                 let sigma, co' = lift_rec en sigma ib_typ co in
                 (sigma, mkProj (pr, co')), false
              | Construct (((i, i_index), _), u) ->
                 let ind = mkInd (i, i_index) in
                 if equal ind (directional l a_typ b_typ) then
                   (* lazy eta expansion *)
                   let sigma, tr_eta = expand_eta en sigma tr in
                   lift_rec en sigma ib_typ tr_eta, false
                 else
                   (sigma, tr), false
              | Const (co, u) ->
                 let sigma, lifted =
                   (try
                      (* CONST *)
                      let def = lookup_definition en tr in
                      let sigma, try_lifted = lift_rec en sigma ib_typ def in
                      if equal def try_lifted then
                        sigma, tr
                      else
                        reduce_term en sigma try_lifted
                    with _ ->
                      (* AXIOM *)
                      sigma, tr)
                 in cache_local c.cache tr lifted; (sigma, lifted), false
              | _ ->
                 (sigma, tr), false
    in
    (* sometimes we must repack because of non-primitive projections *)
    map_if
      (fun (sigma, lifted) ->
        let sigma_typ, typ = infer_type en sigma tr in
        let typ = reduce_stateless reduce_nf en sigma_typ typ in
        let is_from_typ = is_from c en sigma_typ typ in
        map_if
          (fun (sigma, t) ->
            Util.on_snd (repack en ib_typ t) (lift_rec en sigma_typ ib_typ typ))
          (is_from_typ && not (is_or_applies existT (reduce_stateless reduce_nf en sigma lifted)))
          (sigma, lifted))
      try_repack
      (sigma, lifted)
  in lift_rec env sigma ib_typ trm

(*
 * Run the core lifting algorithm on a term
 *)
let do_lift_term env sigma (l : lifting) trm =
  let (a_t, b_t, i_b_t_o) = typs_from_orn l env sigma in
  match l.orn.kind with
  | Algebraic ->
     let sigma, c = initialize_lift_config env sigma l (a_t, b_t) in
     lift_algebraic env sigma c (Option.get i_b_t_o) trm
  | CurryRecord ->
     failwith "not yet implemented"

(*
 * Run the core lifting algorithm on a definition
 *)
let do_lift_defn env sigma (l : lifting) def =
  let trm = unwrap_definition env def in
  do_lift_term env sigma l trm

(************************************************************************)
(*                           Inductive types                            *)
(************************************************************************)

let define_lifted_eliminator ?(suffix="_sigT") ind0 ind sort =
  let env = Global.env () in
  let ident =
    let ind_name = (Inductive.lookup_mind_specif env ind |> snd).mind_typename in
    let raw_ident = Indrec.make_elimination_ident ind_name sort in
    Nameops.add_suffix raw_ident suffix
  in
  let elim0 = Indrec.lookup_eliminator ind0 sort in
  let elim = Indrec.lookup_eliminator ind sort in
  let env, term = open_constant env (Globnames.destConstRef elim) in
  let expr = Eta.eta_extern env (Evd.from_env env) Id.Set.empty term in
  ComDefinition.do_definition
    ~program_mode:false ident (Decl_kinds.Global, false, Decl_kinds.Scheme)
    None [] None expr None (Lemmas.mk_hook (fun _ -> declare_lifted elim0))

let declare_inductive_liftings ind ind' ncons =
  declare_lifted (Globnames.IndRef ind) (Globnames.IndRef ind');
  List.iter2
    declare_lifted
    (List.init ncons (fun i -> Globnames.ConstructRef (ind, i + 1)))
    (List.init ncons (fun i -> Globnames.ConstructRef (ind', i + 1)))

(*
 * Lift the inductive type using sigma-packing.
 *
 * This algorithm assumes that type parameters are left constant and will lift
 * every binding and every term of the base type to the sigma-packed ornamented
 * type. (IND and CONSTR via caching)
 *)
let do_lift_ind env sigma typename suffix lift ind =
  let (mind_body, ind_body) as mind_specif = Inductive.lookup_mind_specif env ind in
  check_inductive_supported mind_body;
  let env, univs, arity, constypes = open_inductive ~global:true env mind_specif in
  let sigma = Evd.update_sigma_env sigma env in
  let nparam = mind_body.mind_nparams_rec in
  let sigma, arity' = do_lift_term env sigma lift arity in
  let sigma, constypes' = map_state (fun trm sigma -> do_lift_term env sigma lift trm) constypes sigma in
  let consnames =
    Array.map_to_list (fun id -> Nameops.add_suffix id suffix) ind_body.mind_consnames
  in
  let is_template = is_ind_body_template ind_body in
  let ind' =
    declare_inductive typename consnames is_template univs nparam arity' constypes'
  in
  List.iter (define_lifted_eliminator ind ind') [Sorts.InType; Sorts.InProp];
  declare_inductive_liftings ind ind' (List.length constypes);
  ind'
