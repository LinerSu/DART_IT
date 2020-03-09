(*
USED: PLDI2011 as ack
USED: PEPM2013 as ack
*)

let main mm mn =
    let rec ack m n =
      if m = 0 then n + 1
      else if n = 0 then ack (m - 1) 1
      else ack (m - 1) (ack m (n - 1))
    in

    if (mm >= 0 && mn >= 0)
    then ack mm mn >= mn
    else false
in assert( main 3 2 = true)