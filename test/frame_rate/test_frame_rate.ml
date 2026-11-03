(**************************************************************************)
(*                                                                        *)
(*    Copyright 2026 OCamlPro                                             *)
(*                                                                        *)
(*  All rights reserved. This file is distributed under the terms of the  *)
(*  GNU Lesser General Public License version 2.1, with the special       *)
(*  exception on linking described in the file LICENSE.                   *)
(*                                                                        *)
(**************************************************************************)

(* Backend.setFrameRate sets the rate of the frame event. The bounds on
   the measured rates are loose, so that the test does not depend on
   the load of the machine: what matters is that the rate goes well
   beyond the former fixed 60 Hz, and well below it. *)

open OcamlCanvas.V1

let failures = ref 0

let check name cond =
  if not cond then begin
    incr failures;
    Printf.printf "FAIL: %s\n%!" name
  end

let invalid fps =
  try Backend.setFrameRate fps; false with Invalid_argument _ -> true

let events = ref []

(* Frame rates to measure, each during [duration] seconds *)
let rates = [ 250; 20 ]
let duration = 1.0

let () =
  Backend.init ();

  check "default rate" (Backend.getFrameRate () = 60);
  check "zero rate rejected" (invalid 0);
  check "negative rate rejected" (invalid (-5));
  check "excessive rate rejected" (invalid 1001);
  check "rate unchanged after rejection" (Backend.getFrameRate () = 60);

  let c = Canvas.createOnscreen ~title:"frame rate"
            ~pos:(0, 0) ~size:(100, 100) () in
  Canvas.show c;

  let remaining = ref rates in
  let start = ref 0L and frames = ref 0 in
  let next_rate () =
    match !remaining with
    | [] -> Backend.stop ()
    | fps :: rest ->
        remaining := rest;
        Backend.setFrameRate fps;
        check "rate recorded" (Backend.getFrameRate () = fps);
        start := Backend.getCurrentTimestamp ();
        frames := 0
  in
  next_rate ();
  events := React.E.map (fun { Event.canvas = c'; timestamp; _ } ->
      if c' == c then begin
        incr frames;
        let elapsed = Int64.to_float (Int64.sub timestamp !start) /. 1e6 in
        if elapsed >= duration then begin
          let measured = float !frames /. elapsed in
          let fps = float (Backend.getFrameRate ()) in
          Printf.printf "requested %.0f Hz, measured %.1f Hz\n%!" fps measured;
          check (Printf.sprintf "rate %.0f Hz: not above the request" fps)
            (measured <= fps *. 1.05);
          check (Printf.sprintf "rate %.0f Hz: at least half the request" fps)
            (measured >= fps *. 0.5);
          next_rate ()
        end
      end) Event.frame :: !events;

  Backend.run (fun () -> if !failures > 0 then exit 1)
