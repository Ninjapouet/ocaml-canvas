(**************************************************************************)
(*                                                                        *)
(*    Copyright 2026 OCamlPro                                             *)
(*                                                                        *)
(*  All rights reserved. This file is distributed under the terms of the  *)
(*  GNU Lesser General Public License version 2.1, with the special       *)
(*  exception on linking described in the file LICENSE.                   *)
(*                                                                        *)
(**************************************************************************)

(* The font weight must reach the rendering: bold text covers more
   pixels than regular text, and thin text fewer. *)

open OcamlCanvas.V1

let family = if Sys.os_type = "Win32" then "Arial" else "Helvetica"

(* Number of pixels touched by the text drawn with weight [w] *)
let ink w =
  let c = Canvas.createOffscreen ~size:(200, 60) () in
  Canvas.setFillColor c Color.white;
  Canvas.fillRect c ~pos:(0.0, 0.0) ~size:(200.0, 60.0);
  Canvas.setFillColor c Color.black;
  Canvas.setFont c family ~size:40.0 ~slant:Font.Roman ~weight:w;
  Canvas.fillText c "HHHH" (10.0, 45.0);
  let n = ref 0 in
  for y = 0 to 59 do
    for x = 0 to 199 do
      if Canvas.getPixel c (x, y) <> Color.white then incr n
    done
  done;
  !n

let () =
  Backend.init ();
  let thin = ink Font.thin and regular = ink Font.regular
  and bold = ink Font.bold in
  Printf.printf "ink: thin %d, regular %d, bold %d\n" thin regular bold;
  if not (thin <= regular && regular < bold) then begin
    print_endline "FAIL: the font weight is not taken into account";
    exit 1
  end
