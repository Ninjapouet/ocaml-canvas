(**************************************************************************)
(*                                                                        *)
(*    Copyright 2026 OCamlPro                                             *)
(*                                                                        *)
(*  All rights reserved. This file is distributed under the terms of the  *)
(*  GNU Lesser General Public License version 2.1, with the special       *)
(*  exception on linking described in the file LICENSE.                   *)
(*                                                                        *)
(**************************************************************************)

(* Smoke test: draw on an offscreen canvas and read the pixels back. *)

open OcamlCanvas.V1

let failures = ref 0

let check name cond =
  if not cond then begin
    incr failures;
    Printf.printf "FAIL: %s\n%!" name
  end

let () =
  Backend.init ();
  let c = Canvas.createOffscreen ~size:(64, 64) () in
  Canvas.setFillColor c Color.black;
  Canvas.fillRect c ~pos:(0.0, 0.0) ~size:(64.0, 64.0);
  Canvas.setFillColor c Color.red;
  Canvas.fillRect c ~pos:(16.0, 16.0) ~size:(32.0, 32.0);
  check "inside the rectangle" (Canvas.getPixel c (32, 32) = Color.red);
  check "outside the rectangle" (Canvas.getPixel c (4, 4) = Color.black);
  check "right edge excluded" (Canvas.getPixel c (48, 32) = Color.black);
  if !failures > 0 then exit 1
