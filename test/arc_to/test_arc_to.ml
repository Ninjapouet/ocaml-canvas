(**************************************************************************)
(*                                                                        *)
(*    Copyright 2026 OCamlPro                                             *)
(*                                                                        *)
(*  All rights reserved. This file is distributed under the terms of the  *)
(*  GNU Lesser General Public License version 2.1, with the special       *)
(*  exception on linking described in the file LICENSE.                   *)
(*                                                                        *)
(**************************************************************************)

(* Degenerate path arguments, which used to crash the rasterizer:
   - arcTo with a zero radius behaves as lineTo to the corner point;
   - path operations with a non-finite argument (NaN or infinity)
     are ignored.
   Both as in the HTML5 canvas specification, on canvases and on Path2D
   objects. *)

open OcamlCanvas.V1

let failures = ref 0

let check name cond =
  if not cond then begin
    incr failures;
    Printf.printf "FAIL: %s\n%!" name
  end

let blank () =
  let c = Canvas.createOffscreen ~size:(60, 60) () in
  Canvas.setFillColor c Color.black;
  Canvas.fillRect c ~pos:(0.0, 0.0) ~size:(60.0, 60.0);
  Canvas.setFillColor c Color.white;
  c

(* A 40x40 square whose top right corner is drawn with arcTo,
   so the corner is sharp if and only if the radius is zero. *)
let square_with_arc_to arc_to radius =
  arc_to ~p1:(50.0, 10.0) ~p2:(50.0, 50.0) ~radius

let check_square name c =
  check (name ^ ": inside") (Canvas.getPixel c (30, 30) = Color.white);
  check (name ^ ": sharp corner") (Canvas.getPixel c (48, 11) = Color.white);
  check (name ^ ": outside") (Canvas.getPixel c (55, 5) = Color.black)

let () =
  Backend.init ();

  let c = blank () in
  Canvas.clearPath c;
  Canvas.moveTo c (10.0, 10.0);
  square_with_arc_to (Canvas.arcTo c) 0.0;
  Canvas.lineTo c (50.0, 50.0);
  Canvas.lineTo c (10.0, 50.0);
  Canvas.closePath c;
  Canvas.fill c ~nonzero:true;
  check_square "Canvas.arcTo" c;

  let c = blank () in
  let p = Path.create () in
  Path.moveTo p (10.0, 10.0);
  square_with_arc_to (Path.arcTo p) 0.0;
  Path.lineTo p (50.0, 50.0);
  Path.lineTo p (10.0, 50.0);
  Path.close p;
  Canvas.fillPath c p ~nonzero:true;
  check_square "Path.arcTo" c;

  (* A positive radius still rounds the corner *)
  let c = blank () in
  Canvas.clearPath c;
  Canvas.moveTo c (10.0, 10.0);
  square_with_arc_to (Canvas.arcTo c) 10.0;
  Canvas.lineTo c (50.0, 50.0);
  Canvas.lineTo c (10.0, 50.0);
  Canvas.closePath c;
  Canvas.fill c ~nonzero:true;
  check "rounded corner" (Canvas.getPixel c (49, 11) = Color.black);
  check "rounded corner: inside" (Canvas.getPixel c (30, 30) = Color.white);

  (* Non-finite arguments: the call is ignored, the rest of the path
     is drawn as if it had not been made *)
  let ignored name op =
    let c = blank () in
    Canvas.clearPath c;
    Canvas.moveTo c (10.0, 10.0);
    Canvas.lineTo c (50.0, 10.0);
    op c;
    Canvas.lineTo c (50.0, 50.0);
    Canvas.lineTo c (10.0, 50.0);
    Canvas.closePath c;
    Canvas.fill c ~nonzero:true;
    check_square name c
  in
  ignored "lineTo NaN" (fun c -> Canvas.lineTo c (nan, 30.0));
  ignored "lineTo infinity" (fun c -> Canvas.lineTo c (infinity, 30.0));
  ignored "moveTo NaN" (fun c -> Canvas.moveTo c (30.0, nan));
  ignored "bezierCurveTo NaN" (fun c ->
    Canvas.bezierCurveTo c ~cp1:(nan, 0.0) ~cp2:(0.0, 0.0) ~p:(50.0, 30.0));
  ignored "quadraticCurveTo NaN" (fun c ->
    Canvas.quadraticCurveTo c ~cp:(0.0, nan) ~p:(50.0, 30.0));
  ignored "arc NaN radius" (fun c ->
    Canvas.arc c ~center:(30.0, 30.0) ~radius:nan
      ~theta1:0.0 ~theta2:1.0 ~ccw:false);
  ignored "arcTo NaN radius" (fun c ->
    Canvas.arcTo c ~p1:(50.0, 50.0) ~p2:(10.0, 50.0) ~radius:nan);
  ignored "ellipse NaN" (fun c ->
    Canvas.ellipse c ~center:(30.0, 30.0) ~radius:(10.0, nan) ~rotation:0.0
      ~theta1:0.0 ~theta2:1.0 ~ccw:false);
  ignored "rect NaN" (fun c ->
    Canvas.rect c ~pos:(0.0, 0.0) ~size:(nan, 10.0));

  if !failures > 0 then exit 1
