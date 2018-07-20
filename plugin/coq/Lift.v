Add LoadPath "coq".
Require Import List.
Require Import Ornamental.Ornaments.
Require Import Test.

(*
 * Test lifting directly
 *)

(* --- Simple constructor tests ---- *)

Definition nil' := @nil.

Lift2 orn_list_vector orn_list_vector_inv in nil' as nil'_c.
Theorem testNil:
  forall A, nil'_c A = existT (vector A) 0 (nilV A).
Proof.
  intros. reflexivity.
Qed.

Definition nilV' (A : Type) :=
  existT (vector A) 0 (nilV A).

Lift2 orn_list_vector_inv orn_list_vector in nilV' as nilV'_c.
Theorem testNilV:
  forall A, nilV'_c A = @nil A.
Proof.
  intros. reflexivity.
Qed.

Definition cons' := @cons.

Lift2 orn_list_vector orn_list_vector_inv in cons' as cons'_c.
Theorem testCons:
  forall A a pv, 
    cons'_c A a pv = 
    existT (vector A) (S (projT1 pv)) (consV A (projT1 pv) a (projT2 pv)).
Proof.
  intros. reflexivity.
Qed.

Definition consV' (A : Type) (a : A) (pv : sigT (vector A)) :=
  existT (vector A) (S (projT1 pv)) (consV A (projT1 pv) a (projT2 pv)).

Lift2 orn_list_vector_inv orn_list_vector in consV' as consV'_c.
Theorem testConsV:
  forall A a l,
    consV'_c A a l = @cons A a l.
Proof.
  intros. reflexivity.
Qed.

(* --- Simple functions --- *)

Definition hd (A : Type) (default : A) (l : list A) :=
  list_rect
    (fun (_ : list A) => A)
    default
    (fun (x : A) (_ : list A) (_ : A) =>
      x)
    l.

Definition hd_vect (A : Type) (default : A) (pv : sigT (vector A)) :=
  vector_rect
    A
    (fun (n0 : nat) (_ : vector A n0) => A)
    default
    (fun (n0 : nat) (x : A) (_ : vector A n0) (_ : A) =>
      x)
    (projT1 pv)
    (projT2 pv).

Lift2 orn_list_vector orn_list_vector_inv in hd as hd_vect_lifted.

Theorem test_hd_vect:
  forall (A : Type) (default : A) (pv : packed_vector A),
    hd_vect A default pv = hd_vect_lifted A default pv.
Proof.
  intros. reflexivity.
Qed.

Lift2 orn_list_vector_inv orn_list_vector in hd_vect as hd_lifted.

Theorem test_hd:
  forall (A : Type) (default : A) (l : list A),
    hd A default l = hd_lifted A default l.
Proof.
  intros. reflexivity.
Qed.

(* flist/flector version *)

Definition hdF (default : nat) (l : natFlector.flist) :=
  natFlector.flist_rect
    (fun (_ : natFlector.flist) => nat)
    default
    (fun (x : nat) (_ : natFlector.flist) (_ : nat) =>
      x)
    l.

Definition hd_vectF (default : nat) (pv : sigT natFlector.flector) :=
  natFlector.flector_rect
    (fun (n0 : nat) (_ : natFlector.flector n0) => nat)
    default
    (fun (n0 : nat) (x : nat) (_ : natFlector.flector n0) (_ : nat) =>
      x)
    (projT1 pv)
    (projT2 pv).

Lift2 orn_flist_flector_nat orn_flist_flector_nat_inv in hdF as hd_vectF_lifted.

Theorem test_hd_vectF:
  forall (default : nat) (pv : sigT natFlector.flector),
    hd_vectF default pv = hd_vectF_lifted default pv.
Proof.
  intros. reflexivity.
Qed.

Lift2 orn_flist_flector_nat_inv orn_flist_flector_nat in hd_vectF as hdF_lifted.

Theorem test_hdF:
  forall (default : nat) (l : natFlector.flist),
    hdF default l = hdF_lifted default l.
Proof.
  intros. reflexivity.
Qed.

(* hd_error *)

Definition hd_error (A : Type) (l : list A) :=
  list_rect
    (fun (_ : list A) => option A)
    None
    (fun (x : A) (_ : list A) (_ : option A) =>
      Some x)
    l.

Definition hd_vect_error (A : Type) (v : sigT (vector A)) :=
  vector_rect
    A
    (fun (n0 : nat) (_ : vector A n0) => option A)
    None
    (fun (n0 : nat) (x : A) (_ : vector A n0) (_ : option A) =>
      Some x)
    (projT1 v)
    (projT2 v).

Lift2 orn_list_vector orn_list_vector_inv in hd_error as hd_vect_error_lifted.

Theorem test_hd_vect_error:
  forall (A : Type) (pv : packed_vector A),
    hd_vect_error A pv = hd_vect_error_lifted A pv.
Proof.
  intros. reflexivity.
Qed.

Lift2 orn_list_vector_inv orn_list_vector in hd_vect_error as hd_error_lifted.

Theorem test_hd_error:
  forall (A : Type) (l : list A),
    hd_error A l = hd_error_lifted A l.
Proof.
  intros. reflexivity.
Qed.

(* append *)

(*
 * Test applying ornaments to lift functions, without internalizing
 * the ornamentation (so the type won't be useful yet).
 *)

Definition append (A : Type) (l1 : list A) (l2 : list A) :=
  list_rect
    (fun (_ : list A) => list A)
    l2
    (fun (a : A) (_ : list A) (IH : list A) =>
      a :: IH)
    l1.

Definition append_vect (A : Type) (pv1 : sigT (vector A)) (pv2 : sigT (vector A)) :=
  vector_rect
    A
    (fun (n0 : nat) (v0 : vector A n0) => sigT (fun (n : nat) => vector A n))
    pv2
    (fun (n0 : nat) (a : A) (v0 : vector A n0) (IH : sigT (fun (n : nat) => vector A n)) =>
      existT
        (vector A)
        (S (projT1 IH))
        (consV A (projT1 IH) a (projT2 IH)))
    (projT1 pv1)
    (projT2 pv1).

Lift2 orn_list_vector orn_list_vector_inv in append as append_vect_lifted.

Theorem test_append_vect:
  forall (A : Type) (pv1 : packed_vector A) (pv2 : packed_vector A),
    append_vect A pv1 pv2  = append_vect_lifted A pv1 pv2.
Proof.
  intros. reflexivity.
Qed.

Lift2 orn_list_vector_inv orn_list_vector in append_vect as append_lifted.

Theorem test_append :
  forall (A : Type) (l1 : list A) (l2 : list A),
    append A l1 l2  = append_lifted A l1 l2.
Proof.
  intros. reflexivity.
Qed.

(* append for flectors *)

Definition appendF (l1 : natFlector.flist) (l2 : natFlector.flist) :=
  natFlector.flist_rect
    (fun (_ : natFlector.flist) => natFlector.flist)
    l2
    (fun (a : nat) (_ : natFlector.flist) (IH : natFlector.flist) =>
      natFlector.consF a IH)
    l1.

Definition append_vectF (pv1 : sigT natFlector.flector) (pv2 : sigT natFlector.flector) :=
  natFlector.flector_rect
    (fun (n0 : nat) (v0 : natFlector.flector n0) => sigT natFlector.flector)
    pv2
    (fun (n0 : nat) (a : nat) (v0 : natFlector.flector n0) (IH : sigT natFlector.flector) =>
      existT
        natFlector.flector
        (natFlector.SIfEven a (projT1 IH))
        (natFlector.consFV (projT1 IH) a (projT2 IH)))
    (projT1 pv1)
    (projT2 pv1).

Lift2 orn_flist_flector_nat orn_flist_flector_nat_inv in appendF as append_vectF_lifted.

Theorem test_append_vectF:
  forall (pv1 : sigT natFlector.flector) (pv2 : sigT natFlector.flector),
    append_vectF pv1 pv2 = append_vectF_lifted pv1 pv2.
Proof.
  intros. reflexivity.
Qed.

Lift2 orn_flist_flector_nat_inv orn_flist_flector_nat in append_vectF as appendF_lifted.

Theorem test_appendF :
  forall (l1 : natFlector.flist) (l2 : natFlector.flist),
    appendF l1 l2  = appendF_lifted l1 l2.
Proof.
  intros. reflexivity.
Qed.

(* tl *)

Definition tl (A : Type) (l : list A) :=
  @list_rect
    A
    (fun (l0 : list A) => list A)
    (@nil A)
    (fun (a : A) (l0 : list A) (_ : list A) =>
      l0)
    l.

Definition tl_vect (A : Type) (pv : packed_vector A) :=
  vector_rect
    A
    (fun (n0 : nat) (v0 : vector A n0) => sigT (fun (n : nat) => vector A n))
    (existT (vector A) 0 (nilV A))
    (fun (n0 : nat) (a : A) (v0 : vector A n0) (_ : sigT (fun (n : nat) => vector A n)) =>
      existT (vector A) n0 v0)
    (projT1 pv)
    (projT2 pv).

Lift2 orn_list_vector orn_list_vector_inv in tl as tl_vect_lifted.

Theorem test_tl_vect:
  forall (A : Type) (pv : packed_vector A),
    tl_vect A pv = tl_vect_lifted A pv.
Proof.
  intros. reflexivity.
Qed.

Lift2 orn_list_vector_inv orn_list_vector in tl_vect as tl_lifted.

Theorem test_tl:
  forall (A : Type) (l : list A),
    tl A l = tl_lifted A l.
Proof.
  intros. reflexivity.
Qed.

(*
 * In as an application of an induction principle
 *)
Definition In (A : Type) (a : A) (l : list A) : Prop :=
  @list_rect
    A
    (fun (_ : list A) => Prop)
    False
    (fun (b : A) (l0 : list A) (IHl : Prop) =>
      a = b \/ IHl)
    l.

Definition In_vect (A : Type) (a : A) (pv : sigT (vector A)) : Prop :=
  @vector_rect
    A
    (fun (n1 : nat) (_ : vector A n1) => Prop)
    False
    (fun (n1 : nat) (b : A) (_ : vector A n1) (IHv : Prop) =>
      a = b \/ IHv)
    (projT1 pv)
    (projT2 pv).

Lift2 orn_list_vector orn_list_vector_inv in In as In_vect_lifted.

Theorem test_in_vect:
  forall (A : Type) (a : A) (pv : packed_vector A),
    In_vect A a pv = In_vect_lifted A a pv.
Proof.
  intros. reflexivity.
Qed.

Lift2 orn_list_vector_inv orn_list_vector in In_vect as In_lifted.

Theorem test_in:
  forall (A : Type) (a : A) (l : list A),
    In A a l = In_lifted A a l.
Proof.
  intros. reflexivity.
Qed.

(* TODO rest of tests, eta, case study *)
