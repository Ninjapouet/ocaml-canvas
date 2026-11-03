(**************************************************************************)
(*                                                                        *)
(*    Copyright 2026 OCamlPro                                             *)
(*                                                                        *)
(*  All rights reserved. This file is distributed under the terms of the  *)
(*  GNU Lesser General Public License version 2.1, with the special       *)
(*  exception on linking described in the file LICENSE.                   *)
(*                                                                        *)
(**************************************************************************)

(* Composite operations: those that only affect the drawn area leave
   the pixels that a shape does not cover unchanged, and lighter,
   source-atop and xor follow the Porter-Duff formulas, with colors
   that are not premultiplied. *)

open OcamlCanvas.V1

let failures = ref 0

let check name cond =
  if not cond then begin
    incr failures;
    Printf.printf "FAIL: %s\n%!" name
  end

let local_ops = CompositeOp.[
    "source-over", SourceOver; "source-atop", SourceAtop;
    "destination-over", DestinationOver; "lighter", Lighter; "xor", XOR;
    "multiply", Multiply; "screen", Screen; "overlay", Overlay;
    "darken", Darken; "lighten", Lighten; "color-dodge", ColorDodge;
    "color-burn", ColorBurn; "hard-light", HardLight;
    "soft-light", SoftLight; "difference", Difference;
    "exclusion", Exclusion; "hue", Hue; "saturation", Saturation;
    "color", Color; "luminosity", Luminosity ]

let src = Color.of_argb 255 250 220 0

(* A canvas filled with [bg], on which [draw] is applied with [op] *)
let compose bg op draw =
  let c = Canvas.createOffscreen ~size:(20, 20) () in
  Canvas.setGlobalCompositeOperation c CompositeOp.Copy;
  Canvas.setFillColor c bg;
  Canvas.fillRect c ~pos:(0.0, 0.0) ~size:(20.0, 20.0);
  Canvas.setGlobalCompositeOperation c op;
  Canvas.setFillColor c src;
  draw c;
  c

(* A triangle: its bounding box contains pixels that it does not cover,
   which the rasterizer composes with a null alpha *)
let triangle c =
  Canvas.clearPath c;
  Canvas.moveTo c (2.0, 2.0);
  Canvas.lineTo c (18.0, 2.0);
  Canvas.lineTo c (2.0, 18.0);
  Canvas.closePath c;
  Canvas.fill c ~nonzero:true

(* A full rectangle drawn with an alpha of 127 / 255 *)
let half c =
  Canvas.setGlobalAlpha c 0.5;
  Canvas.fillRect c ~pos:(0.0, 0.0) ~size:(20.0, 20.0)

let close (a1, r1, g1, b1) (a2, r2, g2, b2) =
  List.for_all (fun d -> abs d <= 2) [ a1 - a2; r1 - r2; g1 - g2; b1 - b2 ]

let () =
  Backend.init ();

  List.iter (fun (bg_name, bg) ->
      List.iter (fun (name, op) ->
          let c = compose bg op triangle in
          check (Printf.sprintf "%s on %s background: uncovered pixel"
                   name bg_name)
            (Canvas.getPixel c (16, 16) = bg))
        local_ops)
    [ "opaque", Color.of_argb 255 30 60 90;
      "translucent", Color.of_argb 128 30 60 90 ];

  (* Porter-Duff, with as = 127 / 255 and the source color cs, over the
     destination color cb with alpha ab; returns (alpha, colors) *)
  let ref_op name fa fb clamp =
    List.iter (fun ab ->
        let bg = Color.of_argb ab 30 60 90 in
        let c = compose bg (List.assoc name local_ops) half in
        let a_s = 127.0 /. 255.0 and a_b = float ab /. 255.0 in
        let a_o = min 1.0 (fa a_s a_b *. a_s +. fb a_s a_b *. a_b) in
        let (_, rs, gs, bs) = Color.to_argb src in
        let mix cs cb =
          if a_o = 0.0 then 0 else
            let v = (fa a_s a_b *. a_s *. float cs
                     +. fb a_s a_b *. a_b *. float cb) /. a_o in
            int_of_float (if clamp then min 255.0 v else v) in
        let expected = (int_of_float (a_o *. 255.0),
                        mix rs 30, mix gs 60, mix bs 90) in
        let (a, r, g, b) as got = Color.to_argb (Canvas.getPixel c (5, 5)) in
        if not (close expected got) then begin
          let (ea, er, eg, eb) = expected in
          Printf.printf "%s, destination alpha %d: expected %d %d %d %d, \
                         got %d %d %d %d\n" name ab ea er eg eb a r g b
        end;
        check (Printf.sprintf "%s, destination alpha %d" name ab)
          (close expected got))
      [ 255; 128; 0 ]
  in
  (* source-atop: Fa = ab, Fb = 1 - as *)
  ref_op "source-atop" (fun _ ab -> ab) (fun as_ _ -> 1.0 -. as_) false;
  (* xor: Fa = 1 - ab, Fb = 1 - as *)
  ref_op "xor" (fun _ ab -> 1.0 -. ab) (fun as_ _ -> 1.0 -. as_) false;
  (* lighter: Fa = Fb = 1, sum clamped *)
  ref_op "lighter" (fun _ _ -> 1.0) (fun _ _ -> 1.0) true;

  if !failures > 0 then exit 1
