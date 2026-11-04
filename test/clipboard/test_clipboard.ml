(* Clipboard: a read that goes through the system (asynchronous on X11),
   then a write followed by a read, with non-ASCII text. *)

open OcamlCanvas.V1

let texte = "Presse-papiers : défaut à T+04:10 ✓"

let () =
  Backend.init ();
  let c = Canvas.createOnscreen ~title:"clipboard" ~size:(10, 10) () in
  let initial = ref None and lu = ref None and images = ref 0 in
  let echec m = prerr_endline ("clipboard: " ^ m); exit 1 in
  (* Before any write, the clipboard belongs to someone else, or to no one:
     the answer comes back through the event loop on X11. *)
  Backend.getClipboardText (fun s -> initial := Some s);
  let suivi = React.E.map (fun _ ->
      incr images;
      if !images > 600 then echec "no answer from the clipboard";
      match !initial, !lu with
      | Some _, None ->
        if not (Backend.setClipboardText texte) then
          (print_endline "clipboard: not supported by this backend"; Backend.stop ())
        else Backend.getClipboardText (fun s -> lu := Some s)
      | Some _, Some s ->
        if s <> texte then echec (Printf.sprintf "read %S, expected %S" s texte);
        Backend.stop ()
      | None, _ -> ()) Event.frame in
  Canvas.show c;
  Backend.run (fun () ->
      ignore (Sys.opaque_identity suivi);
      print_endline "clipboard: OK")
