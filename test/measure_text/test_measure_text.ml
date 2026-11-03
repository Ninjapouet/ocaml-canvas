(**************************************************************************)
(*                                                                        *)
(*    Copyright 2026 OCamlPro                                             *)
(*                                                                        *)
(*  All rights reserved. This file is distributed under the terms of the  *)
(*  GNU Lesser General Public License version 2.1, with the special       *)
(*  exception on linking described in the file LICENSE.                   *)
(*                                                                        *)
(**************************************************************************)

(* Canvas.measureText must describe what fillText draws. *)

open OcamlCanvas.V1

let failures = ref 0

let check name cond =
  if not cond then begin
    incr failures;
    Printf.printf "FAIL: %s\n%!" name
  end

let family = if Sys.os_type = "Win32" then "Arial" else "Helvetica"

let w = 400 and h = 120
let x0 = 50.0 and y0 = 80.0 (* start of the text, on the baseline *)

let canvas () =
  let c = Canvas.createOffscreen ~size:(w, h) () in
  Canvas.setFillColor c Color.white;
  Canvas.fillRect c ~pos:(0.0, 0.0) ~size:(float w, float h);
  Canvas.setFillColor c Color.black;
  Canvas.setFont c family ~size:36.0 ~slant:Font.Roman ~weight:Font.regular;
  c

(* Bounding box of the pixels touched by the text, as distances from
   (x0, y0), with the conventions of TextMetrics *)
let ink_box text =
  let c = canvas () in
  Canvas.fillText c text (x0, y0);
  let l = ref w and r = ref (-1) and t = ref h and b = ref (-1) in
  for y = 0 to h - 1 do
    for x = 0 to w - 1 do
      if Canvas.getPixel c (x, y) <> Color.white then begin
        l := min !l x; r := max !r (x + 1);
        t := min !t y; b := max !b (y + 1)
      end
    done
  done;
  (x0 -. float !l, float !r -. x0, y0 -. float !t, float !b -. y0)

let close ?(tol = 1.5) a b = abs_float (a -. b) <= tol

let () =
  Backend.init ();
  let c = canvas () in
  let m = Canvas.measureText c in

  let e = m "" in
  check "empty text" (e.TextMetrics.width = 0.0
                      && e.TextMetrics.actualBoundingBoxRight = 0.0);
  check "font ascent and descent"
    (e.TextMetrics.fontBoundingBoxAscent > 0.0
     && e.TextMetrics.fontBoundingBoxDescent > 0.0);

  let a = m "Hg" and b = m "H" and g = m "g" in
  check "additive width" (close a.TextMetrics.width
                            (b.TextMetrics.width +. g.TextMetrics.width));
  check "space has width but no ink"
    (let s = m " " in
     s.TextMetrics.width > 0.0 && s.TextMetrics.actualBoundingBoxRight = 0.0);
  check "descender" (g.TextMetrics.actualBoundingBoxDescent > 3.0
                     && close b.TextMetrics.actualBoundingBoxDescent 0.0);
  check "x lower than H" (let x = m "x" in
                          x.TextMetrics.actualBoundingBoxAscent
                          < b.TextMetrics.actualBoundingBoxAscent);
  check "within the font box"
    (a.TextMetrics.actualBoundingBoxAscent
     <= a.TextMetrics.fontBoundingBoxAscent +. 1.0
     && a.TextMetrics.actualBoundingBoxDescent
        <= a.TextMetrics.fontBoundingBoxDescent +. 1.0);

  List.iter (fun text ->
      let t = m text in
      let (l, r, asc, desc) = ink_box text in
      Printf.printf "%-12s width %6.2f  box %6.2f %6.2f %6.2f %6.2f  \
                     ink %4.0f %4.0f %4.0f %4.0f\n" text t.TextMetrics.width
        t.TextMetrics.actualBoundingBoxLeft t.TextMetrics.actualBoundingBoxRight
        t.TextMetrics.actualBoundingBoxAscent
        t.TextMetrics.actualBoundingBoxDescent l r asc desc;
      check (text ^ ": left") (close t.TextMetrics.actualBoundingBoxLeft l);
      check (text ^ ": right") (close t.TextMetrics.actualBoundingBoxRight r);
      check (text ^ ": ascent") (close t.TextMetrics.actualBoundingBoxAscent asc);
      check (text ^ ": descent")
        (close t.TextMetrics.actualBoundingBoxDescent desc))
    [ "Hello"; "jog"; "Été"; "Wy, 42 !" ];

  let regular = m "Hello" in
  Canvas.setFont c family ~size:72.0 ~slant:Font.Roman ~weight:Font.regular;
  let big = m "Hello" in
  (* Hinting rounds the advance of each glyph *)
  check "font size" (close ~tol:(0.05 *. big.TextMetrics.width)
                       big.TextMetrics.width (2.0 *. regular.TextMetrics.width));
  Canvas.setFont c family ~size:36.0 ~slant:Font.Roman ~weight:Font.regular;
  let before = m "Hello" in
  Canvas.scale c (2.0, 2.0);
  check "transform ignored" ((m "Hello") = before);

  if !failures > 0 then exit 1
