Require Import Ornamental.Ornaments.
Set DEVOID search prove equivalence.

(*
 * Talia: Let's start by moving all of the handwritten types into module.
 * This way, we can Preprocess them all at once before lifting.
 *)
Module Handwritten.

Record handwritten_input := MkInput
{
  firstBool  : bool;
  numberI    : nat;
  secondBool : bool;
}.

(*
 * For Preprocess to work, you need to have these:
 *)
Scheme Induction for handwritten_input Sort Set.
Scheme Induction for handwritten_input Sort Prop.
Scheme Induction for handwritten_input Sort Type.

Record handwritten_output := MkOutput
{
  numberO  : nat;
  andBools : bool;
}.

(*
 * For Preprocess to work, you need to have these:
 *)
Scheme Induction for handwritten_output Sort Set.
Scheme Induction for handwritten_output Sort Prop.
Scheme Induction for handwritten_output Sort Type.

Definition handwritten_op (r : handwritten_input) : handwritten_output :=
  {|
    numberO  := numberI r;
    andBools := firstBool r && secondBool r;
  |}.

Theorem handwritten_and_spec_true_true
  (r : handwritten_input)
  (F : firstBool  r = true)
  (S : secondBool r = true)
  : andBools (handwritten_op r) = true.
Proof.
  destruct r as [f n s].
  unfold handwritten_op.
  simpl in *.
  apply andb_true_intro.
  intuition.
Qed.

End Handwritten.

(*
 * Just for clarity, let's stick all of the generated types in a module too.
 *)
Module Generated.

Definition generated_input := (prod bool (prod nat bool)).

Definition generated_output := (prod nat bool).

Definition generated_firstBool (r : (prod bool (prod nat bool))) : bool :=
  (fst r).

Definition generated_numberI (r : (prod bool (prod nat bool))) : nat :=
  (fst (snd r)).

Definition generated_secondBool (r : (prod bool (prod nat bool))) : bool :=
  (snd (snd r)).

Definition generated_andBools (r : (prod nat bool)) : bool :=
  (snd r).

Definition generated_op (r : (prod bool (prod nat bool))) : (prod nat bool) :=
  (pair
    (generated_numberI r)
    (andb
      (generated_firstBool  r)
      (generated_secondBool r)
    )
  ).

End Generated.

(* Let's Preprocess Handwritten for lifting. *)
Preprocess Module Handwritten as Handwritten'.

(* The code that automatically runs Find Ornament first is still finnicky, so better to run it: *)
Find ornament Handwritten'.handwritten_input Generated.generated_input.

(* 
 * Now you can lift. Because of caching bug, you should lift everything along
 * this ornament before you find and lift along the next one!
 * I hope to fix that bug soon.
 *
 * There's no need to unpack for this relation.
 *)
Lift Handwritten'.handwritten_input Generated.generated_input in Handwritten'.firstBool as lifted_firstBool.
Lift Handwritten'.handwritten_input Generated.generated_input in Handwritten'.numberI as lifted_numberI.
Lift Handwritten'.handwritten_input Generated.generated_input in Handwritten'.secondBool as lifted_secondBool.
Lift Handwritten'.handwritten_input Generated.generated_input in Handwritten'.handwritten_op as generated_op'.
Lift Handwritten'.handwritten_input Generated.generated_input in Handwritten'.handwritten_and_spec_true_true as handwritten_and_spec_true_true'.

(*
 * Now let's handle outputs. Find ornament again:
 *)
Find ornament Handwritten'.handwritten_output Generated.generated_output.

(*
 * Then lift:
 *)
Lift Handwritten'.handwritten_output Generated.generated_output in Handwritten'.numberO as lifted_numberO.
Lift Handwritten'.handwritten_output Generated.generated_output in Handwritten'.andBools as lifted_andBools.
Lift Handwritten'.handwritten_output Generated.generated_output in generated_op' as generated_op''.
Lift Handwritten'.handwritten_output Generated.generated_output in handwritten_and_spec_true_true' as generated_and_spec_true_true'.

(*
 * Now we get our proof over generated types with just one catch: We need to call
 * induction first, since we have something defined over Preprocessed types
 * (induction principles) and we want something defined over the original types
 * (pattern matching and so on).
 *)
Theorem generated_and_spec_true_true
  (r : Generated.generated_input)
  (F : Generated.generated_firstBool  r = true)
  (S : Generated.generated_secondBool r = true)
  : Generated.generated_andBools (Generated.generated_op r) = true.
Proof.
  induction r. (* <-- NOTE: You will need this because you used Preprocess *)
  apply generated_and_spec_true_true'; auto.
Qed.

(* We are done! *)

(* -----------------------------------------------------------------------------*)

(*
 * TODO everything below is for Talia: Later testing and so on.
 *)

(* TODO roundtrip tests for above *)
(* TODO fix auto find ornament *)
(* TODO fix caching bug *)


Record handwritten_input_4 := MkInput4
{
  field1  : bool;
  field2    : nat;
  field3 : bool;
  field4 : nat; 
}.

Definition generated_input_4 := (prod bool (prod nat (prod bool nat))).

Scheme Induction for handwritten_input_4 Sort Set.
Scheme Induction for handwritten_input_4 Sort Prop.
Scheme Induction for handwritten_input_4 Sort Type.

Find ornament handwritten_input_4 generated_input_4.

Record handwritten_input_5 := MkInput5
{
  field1'  : bool;
  field2'    : nat;
  field3' : bool;
  field4' : nat;
  field5' : bool; 
}.

Definition generated_input_5 := (prod bool (prod nat (prod bool (prod nat bool)))).

Scheme Induction for handwritten_input_5 Sort Set.
Scheme Induction for handwritten_input_5 Sort Prop.
Scheme Induction for handwritten_input_5 Sort Type.

Find ornament handwritten_input_5 generated_input_5.

Definition generated_input_param_test (T1 T2 T3 : Type) := (prod T1 (prod T2 T3)).

Record handwritten_input_param_test (T1 T2 T3 : Type) := MkInputT
{
  firstT : T1;
  secondT : T2;
  thirdT : T3;
}.

Scheme Induction for handwritten_input_param_test Sort Set.
Scheme Induction for handwritten_input_param_test Sort Prop.
Scheme Induction for handwritten_input_param_test Sort Type.

(* The most basic test: When this works, should just give us fst *)
(* TODO set options to prove equiv: Set DEVOID search prove equivalence. Then get working. Then try w/ params. Then clean. Then do lift, same process.*)
Find ornament handwritten_input_param_test generated_input_param_test. (* TODO can omit once lift works *)
(*Fail Lift handwritten_input generated_input in firstBool as lifted_firstBool.*)

(* TODO test: failure cases, dependent parameters, eta expanded or not expanded variations, 2 fields, 4 fields, taking prod directly, etc *)
(* TODO check test results *)
(* TODO integrate into below *)
(* TODO lift tests for all of the other things here w/ params *)
(* TODO be better about the names you choose for the lifted types above *)

Definition generated_input_param_test2 (T1 T2 T3 T4 : Type) := (prod T1 (prod T2 (prod T3 T4))).

Record handwritten_input_param_test2 (T1 T2 T3 T4 : Type) := MkInputT2
{
  firstT' : T1;
  secondT' : T2;
  thirdT' : T3;
  fourthT' : T4;
}.

Scheme Induction for handwritten_input_param_test2 Sort Set.
Scheme Induction for handwritten_input_param_test2 Sort Prop.
Scheme Induction for handwritten_input_param_test2 Sort Type.

(* The most basic test: When this works, should just give us fst *)
(* TODO set options to prove equiv: Set DEVOID search prove equivalence. Then get working. Then try w/ params. Then clean. Then do lift, same process.*)
Find ornament handwritten_input_param_test2 generated_input_param_test2. (* TODO can omit once lift works *)
(*Fail Lift handwritten_input generated_input in firstBool as lifted_firstBool.*)

Record handwritten_input_param_test3 (T : Type) (t : T) (F : T -> Prop) := mkInput3
{
  firstT'' : F t;
  secondT'' : T;
  thirdT'' : exists t', t <> t' -> F t';
}.

Definition generated_input_param_test3 (T : Type) (t : T) (F : T -> Prop) :=
  (prod (F t) (prod T (exists t', t <> t' -> F t'))).


Scheme Induction for handwritten_input_param_test3 Sort Set.
Scheme Induction for handwritten_input_param_test3 Sort Prop.
Scheme Induction for handwritten_input_param_test3 Sort Type.

(* The most basic test: When this works, should just give us fst *)
(* TODO set options to prove equiv: Set DEVOID search prove equivalence. Then get working. Then try w/ params. Then clean. Then do lift, same process.*)
Find ornament handwritten_input_param_test3 generated_input_param_test3. (* TODO can omit once lift works *)
(*Fail Lift handwritten_input generated_input in firstBool as lifted_firstBool.*)
