
let rec shrink t f d =
  if f () <= 0 then 0 
  else begin
    ev 1; (* ev[Shrink] *)
    let t' = f() - d in
    shrink t' (fun x -> t') d end

let main (gl_t:int) (gl_d:int) =   
    ev (t/d);
    shrink t (fun x -> t) d