(*
    USED: PEPM2013 as copy_intro
*)

let rec copy (x:int) = 
    if x = 0 then 0 
    else 1 + copy (x - 1) 

let main (n:int(*-:{v:Int | true}*)) =
    assert (copy (copy n) = n)

let _ = main 100