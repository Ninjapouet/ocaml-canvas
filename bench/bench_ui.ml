(**************************************************************************)
(*                                                                        *)
(*    Copyright 2026 OCamlPro                                             *)
(*                                                                        *)
(*  All rights reserved. This file is distributed under the terms of the  *)
(*  GNU Lesser General Public License version 2.1, with the special       *)
(*  exception on linking described in the file LICENSE.                   *)
(*                                                                        *)
(**************************************************************************)

(* Cost of drawing a typical user interface screen: solid rectangles
   (backgrounds, panels, bars) and short texts in a few fonts.

   Usage: bench_ui [frames] *)

open OcamlCanvas.V1

let family = if Sys.os_type = "Win32" then "Arial" else "Helvetica"

let w = 1280 and h = 720

let frame c k =
  Canvas.setFillColor c Color.black;
  Canvas.fillRect c ~pos:(0.0, 0.0) ~size:(float w, float h);
  for i = 0 to 39 do
    let x = float (20 + (i mod 8) * 155) and y = float (20 + (i / 8) * 135) in
    Canvas.setFillColor c (Color.of_rgb 40 40 48);
    Canvas.fillRect c ~pos:(x, y) ~size:(145.0, 125.0);
    Canvas.setFillColor c (Color.of_rgb 0 (100 + i) 200);
    (* a bar whose length changes at every frame *)
    Canvas.fillRect c ~pos:(x +. 5.0, y +. 100.0)
      ~size:(float ((i * 7 + k) mod 135) +. 0.5, 12.0);
    Canvas.setFillColor c Color.white;
    Canvas.setFont c family ~size:16.0 ~slant:Font.Roman ~weight:Font.bold;
    Canvas.fillText c (Printf.sprintf "Panel %d" i) (x +. 5.0, y +. 22.0);
    Canvas.setFont c family ~size:12.0 ~slant:Font.Roman ~weight:Font.regular;
    Canvas.fillText c (Printf.sprintf "Value: %d.%02d m/s" (k + i) (k * i mod 100))
      (x +. 5.0, y +. 50.0);
    Canvas.fillText c "Status: nominal" (x +. 5.0, y +. 75.0)
  done

let () =
  let n = if Array.length Sys.argv > 1 then int_of_string Sys.argv.(1) else 50 in
  Backend.init ();
  let c = Canvas.createOffscreen ~size:(w, h) () in
  frame c 0; (* warm up *)
  let t = Array.init n (fun k ->
      let t0 = Unix.gettimeofday () in
      frame c (k + 1);
      Unix.gettimeofday () -. t0) in
  Array.sort compare t;
  let ms q = 1000.0 *. t.(min (n - 1) (int_of_float (q *. float n))) in
  Printf.printf "%d frames of %dx%d: median %.2f ms, p90 %.2f ms, max %.2f ms\n"
    n w h (ms 0.5) (ms 0.9) (ms 1.0)
