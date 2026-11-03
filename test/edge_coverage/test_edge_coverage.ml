(**************************************************************************)
(*                                                                        *)
(*    Copyright 2026 OCamlPro                                             *)
(*                                                                        *)
(*  All rights reserved. This file is distributed under the terms of the  *)
(*  GNU Lesser General Public License version 2.1, with the special       *)
(*  exception on linking described in the file LICENSE.                   *)
(*                                                                        *)
(**************************************************************************)

(* Pixels partially covered by a shape get a coverage proportional to
   the covered area, on every edge, with or without a shadow. *)

open OcamlCanvas.V1

let failures = ref 0

let check name cond =
  if not cond then begin
    incr failures;
    Printf.printf "FAIL: %s\n%!" name
  end

let size = 20

(* Coverage (0..255) of each pixel by the square of side 4 at (x, y),
   drawn in white on black, with an optional far away shadow *)
let draw ?(shadow = false) (x, y) =
  let c = Canvas.createOffscreen ~size:(size, size) () in
  Canvas.setFillColor c Color.black;
  Canvas.fillRect c ~pos:(0.0, 0.0) ~size:(float size, float size);
  if shadow then begin
    Canvas.setShadowColor c Color.red;
    Canvas.setShadowOffset c (0.0, 10.0)
  end;
  Canvas.setFillColor c Color.white;
  Canvas.clearPath c;
  Canvas.moveTo c (x, y);
  Canvas.lineTo c (x +. 4.0, y);
  Canvas.lineTo c (x +. 4.0, y +. 4.0);
  Canvas.lineTo c (x, y +. 4.0);
  Canvas.closePath c;
  Canvas.fill c ~nonzero:true;
  Array.init 10 (fun i -> Array.init size (fun j ->
      Color.to_int (Canvas.getPixel c (j, i)) land 255))

(* Exact coverage of pixel (i, j) by the square at (x, y) *)
let exact (x, y) i j =
  let overlap a b k =
    max 0.0 (min b (float (k + 1)) -. max a (float k)) in
  overlap x (x +. 4.0) j *. overlap y (y +. 4.0) i *. 255.0

let check_square ?shadow name pos =
  let pixels = draw ?shadow pos in
  let worst = ref 0.0 in
  Array.iteri (fun i row -> Array.iteri (fun j v ->
      worst := max !worst (abs_float (float v -. exact pos i j))) row) pixels;
  Printf.printf "%s: largest difference %.1f\n" name !worst;
  check name (!worst <= 2.0)

let () =
  Backend.init ();
  check_square "integer square" (3.0, 3.0);
  check_square "fractional square" (3.5, 3.25);
  check_square "fractional square, other side" (3.75, 2.5);
  check_square ~shadow:true "fractional square with shadow" (3.5, 3.25);
  if !failures > 0 then exit 1
