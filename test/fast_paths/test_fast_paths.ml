(**************************************************************************)
(*                                                                        *)
(*    Copyright 2026 OCamlPro                                             *)
(*                                                                        *)
(*  All rights reserved. This file is distributed under the terms of the  *)
(*  GNU Lesser General Public License version 2.1, with the special       *)
(*  exception on linking described in the file LICENSE.                   *)
(*                                                                        *)
(**************************************************************************)

(* The fast paths for solid rectangles and texts must draw what the
   general polygon rasterizer draws. The rasterizer is forced by
   filling with a gradient whose two stops have the same color.

   The fast path for rectangles computes the exact covered area of
   edge pixels, whereas the rasterizer rounds it to 1/8 of a pixel in
   each direction: on edges, colors may differ by up to 16 levels. *)

open OcamlCanvas.V1

let failures = ref 0

let check name cond =
  if not cond then begin
    incr failures;
    Printf.printf "FAIL: %s\n%!" name
  end

let family = if Sys.os_type = "Win32" then "Arial" else "Helvetica"

let w = 160 and h = 100

let solid c color = Canvas.setFillColor c color

let rasterized c color =
  let g = Gradient.createLinear ~pos1:(0.0, 0.0) ~pos2:(1.0, 1.0) in
  Gradient.addColorStop g color 0.0;
  Gradient.addColorStop g color 1.0;
  Canvas.setFillGradient c g

let channels col =
  let c = Color.to_int col in
  [ (c lsr 24) land 255; (c lsr 16) land 255; (c lsr 8) land 255; c land 255 ]

(* Largest difference between two canvases, over all channels, and
   number of pixels that differ by more than [tol] *)
let compare_canvases ?(tol = 0) c1 c2 =
  let worst = ref 0 and bad = ref 0 in
  for y = 0 to h - 1 do
    for x = 0 to w - 1 do
      let d = List.fold_left2 (fun m a b -> max m (abs (a - b))) 0
          (channels (Canvas.getPixel c1 (x, y)))
          (channels (Canvas.getPixel c2 (x, y))) in
      worst := max !worst d;
      if d > tol then incr bad
    done
  done;
  (!worst, !bad)

(* Draws [scene] twice, once with each fill style, on a striped
   background (so that compositing has something to work on) *)
let both scene =
  let draw style =
    let c = Canvas.createOffscreen ~size:(w, h) () in
    for i = 0 to w / 10 do
      Canvas.setFillColor c (if i mod 2 = 0 then Color.of_argb 255 30 60 90
                             else Color.of_argb 128 200 100 50);
      Canvas.fillRect c ~pos:(float (i * 10), 0.0) ~size:(10.0, float h)
    done;
    scene c (style c);
    c
  in
  (draw solid, draw rasterized)

let rects c fill =
  fill (Color.of_argb 255 250 220 0);
  Canvas.fillRect c ~pos:(10.0, 10.0) ~size:(40.0, 30.0);
  Canvas.fillRect c ~pos:(60.3, 12.7) ~size:(33.45, 20.2);
  Canvas.fillRect c ~pos:(140.5, 90.5) ~size:(-30.25, -25.75);
  Canvas.fillRect c ~pos:(100.0, 40.0) ~size:(0.4, 0.6);
  fill (Color.of_argb 160 0 200 255);
  Canvas.fillRect c ~pos:(5.5, 50.25) ~size:(150.0, 20.5);
  Canvas.fillRect c ~pos:(-20.0, -20.0) ~size:(30.0, 200.0)

let () =
  Backend.init ();

  let (s, r) = both rects in
  let (worst, _) = compare_canvases s r in
  Printf.printf "rectangles: largest difference %d\n" worst;
  check "rectangles" (worst <= 16);

  let (s, r) = both (fun c fill ->
      Canvas.translate c (3.25, -2.5);
      Canvas.scale c (1.5, -0.75);
      Canvas.translate c (0.0, -120.0);
      rects c fill) in
  let (worst, _) = compare_canvases s r in
  Printf.printf "scaled rectangles: largest difference %d\n" worst;
  check "scaled rectangles" (worst <= 16);

  let (s, r) = both (fun c fill ->
      Canvas.setGlobalAlpha c 0.6; rects c fill) in
  let (worst, _) = compare_canvases s r in
  Printf.printf "translucent rectangles: largest difference %d\n" worst;
  check "translucent rectangles" (worst <= 16);

  List.iter (fun (name, op) ->
      let (s, r) = both (fun c fill ->
          Canvas.setGlobalCompositeOperation c op; rects c fill) in
      let (worst, _) = compare_canvases s r in
      Printf.printf "%s: largest difference %d\n" name worst;
      check name (worst <= 16))
    CompositeOp.[ "destination-over", DestinationOver; "lighter", Lighter;
                  "xor", XOR; "multiply", Multiply; "copy", Copy;
                  "source-in", SourceIn; "destination-out", DestinationOut ];

  let (s, r) = both (fun c fill ->
      Canvas.clearPath c;
      Canvas.arc c ~center:(80.0, 50.0) ~radius:35.0
        ~theta1:0.0 ~theta2:(2.0 *. Const.pi) ~ccw:false;
      Canvas.clip c ~nonzero:true;
      rects c fill) in
  let (worst, _) = compare_canvases s r in
  Printf.printf "clipped rectangles: largest difference %d\n" worst;
  check "clipped rectangles" (worst <= 16);

  (* Texts: FreeType's rendering of the glyphs and the rasterizer may
     differ slightly on edges, and positions are rounded to a quarter
     of a pixel *)
  let texts c fill =
    fill Color.white;
    Canvas.setFont c family ~size:14.0 ~slant:Font.Roman ~weight:Font.regular;
    Canvas.fillText c "Status: nominal" (5.0, 20.0);
    Canvas.fillText c "Été 42,5 m/s" (7.3, 40.6);
    Canvas.setFont c family ~size:24.0 ~slant:Font.Roman ~weight:Font.bold;
    Canvas.translate c (0.5, 0.25);
    Canvas.fillText c "Wagon" (10.0, 80.0);
    Canvas.setGlobalAlpha c 0.5;
    Canvas.fillText c "jog" (100.0, 80.0)
  in
  let (s, r) = both texts in
  let (worst, bad) = compare_canvases ~tol:64 s r in
  Printf.printf "texts: largest difference %d, %d pixels beyond 64\n" worst bad;
  check "texts" (bad <= 10);

  (* Many fonts, so that the font cache evicts some: each one must
     still be the right one *)
  let c = Canvas.createOffscreen ~size:(w, h) () in
  let width size =
    Canvas.setFont c family ~size ~slant:Font.Roman ~weight:Font.regular;
    (Canvas.measureText c "Hello").TextMetrics.width in
  let sizes = Array.init 40 (fun i -> 8.0 +. float i) in
  let first = Array.map width sizes in
  let again = Array.map width sizes in
  check "font cache" (first = again);
  check "font sizes" (first.(39) > 3.0 *. first.(0));

  if !failures > 0 then exit 1
