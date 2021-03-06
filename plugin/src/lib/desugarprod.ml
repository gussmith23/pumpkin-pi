(*
 * These are the produtils from the library, but extended to automatically
 * also preprocess rather than produce terms with match statements
 *)

open Constr
open Envutils
open Apputils
open Nametab
open Libnames
open Produtils
open Reducers
open Inference

(* --- Constants --- *)

let prod : types = prod
let pair : constr = pair
let prod_rect : constr = prod_rect

(*
 * Override fst and snd
 *)
let fst_elim () : constr =
  mkConst (locate_constant (qualid_of_string "Ornamental.Prod.fst"))

(* Second projection *)
let snd_elim () : constr =
  mkConst (locate_constant (qualid_of_string "Ornamental.Prod.snd"))

(* --- Representations --- *)

let apply_pair = apply_pair
let dest_pair = dest_pair
let apply_prod = apply_prod
let dest_prod = dest_prod
let elim_prod = elim_prod
let dest_prod_elim = dest_prod_elim

(*
 * First projection of a prod
 *)
let prod_fst_elim (app : prod_app) trm =
  mkAppl (fst_elim (), Produtils.[app.typ1; app.typ2; trm])

(*
 * Second projection of a prod
 *)
let prod_snd_elim (app : prod_app) trm =
  mkAppl (snd_elim (), Produtils.[app.typ1; app.typ2; trm])

(*
 * Both projections of a prod
 *)
let prod_projections_elim (app : prod_app) trm =
  (prod_fst_elim app trm, prod_snd_elim app trm)

(* --- Extra utilities --- *)

(*
 * Both types of a prod
 *)
let prod_typs (p : prod_app) =
  p.typ1, p.typ2

(*
 * All types of a nested prod
 *)
let prod_typs_rec typ =
  let rec prod_args typ =
    if is_or_applies prod typ then
      let typ_prod = dest_prod typ in
      let (typ1, typ2) = prod_typs typ_prod in
      typ1 :: prod_args typ2
    else
      [typ]
  in prod_args typ

(*
 * n types of a nested prod
 *)
let prod_typs_rec_n typ n =
  let rec prod_args typ n =
    if n <= 1 then
      [typ]
    else
      if is_or_applies prod typ then
        let typ_prod = dest_prod typ in
        let (typ1, typ2) = prod_typs typ_prod in
        typ1 :: prod_args typ2 (n - 1)
      else
        [typ]
  in prod_args typ n

(*
 * Eta expansion of a prod
 *)
let eta_prod trm typ =
  if is_or_applies prod typ then
    let typ_prod = dest_prod typ in
    let (typ1, typ2) = prod_typs typ_prod in
    let (trm1, trm2) = prod_projections_elim typ_prod trm in
    apply_pair {typ1; typ2; trm1; trm2}
  else
    trm

(*
 * Eta expansion of a nested prod
 *)
let eta_prod_rec trm typ =
  let rec eta trm typ =
    if is_or_applies prod typ then
      let typ_prod = dest_prod typ in
      let (typ1, typ2) = prod_typs typ_prod in
      let (trm1, trm2) = prod_projections_elim typ_prod trm in
      let trm2 = eta trm2 typ2 in
      apply_pair {typ1; typ2; trm1; trm2}
    else
      trm
  in eta trm typ

(*
 * Like dest_prod, but over the term's type
 *)
let dest_prod_type env trm sigma =
  let sigma, typ = reduce_type env sigma trm in
  let typ_f = unwrap_definition env (first_fun typ) in
  let typ_args = unfold_args typ in
  let typ_red = mkAppl (typ_f, typ_args) in
  let sigma, typ_red = reduce_term env sigma typ_red in
  if is_or_applies prod typ_red then
    sigma, dest_prod typ_red
  else
    failwith "not a product"

(*
 * Recursively project a nested product 
 *)
let prod_projections_rec env trm sigma =
  let rec proj trm sigma =
    try
      let sigma, typ_prod = dest_prod_type env trm sigma in
      let trm_fst, trm_snd = prod_projections_elim typ_prod trm in
      let sigma, proj_tl = proj trm_snd sigma in
      sigma, trm_fst :: proj_tl
    with _ ->
      sigma, [trm]
  in proj trm sigma

(*
 * Project all of the terms out of a pair, eta expanding each one
 * Stop when there are n left
 *)
let pair_projections_eta_rec_n trm n =
  let rec proj trm n =
    let p = dest_pair trm in
    let (trm1, trm2) = p.Produtils.trm1, p.Produtils.trm2 in
    if n <= 2 then
      [trm1; trm2]
    else
      if applies pair trm2 then
        trm1 :: proj trm2 (n - 1)
      else
        let typ2 = p.Produtils.typ2 in
        let trm2_eta = eta_prod trm2 typ2 in
        trm1 :: proj trm2_eta (n - 1)
  in proj trm n

(*
 * Recursively pack a list of arguments into a pair
 * Fail if the list is empty
 *)
let pack_pair_rec env trms sigma =
  let rec pack trms sigma =
    match trms with
    | trm1 :: (h :: tl) ->
       let sigma, typ1 = infer_type env sigma trm1 in
       let sigma, trm2 = pack (h :: tl) sigma in
       let sigma, typ2 = infer_type env sigma trm2 in
       sigma, apply_pair Produtils.{ typ1; typ2; trm1; trm2 }
    | h :: tl ->
       sigma, h
    | _ ->
       failwith "called pack_pair_rec with an empty list"
  in pack trms sigma
