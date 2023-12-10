(*
USED: PEPM2013 as sum_intro
*)

let add x y = x + y

let rec sum n =
  if n <= 0 then
    0
  else
    add n (sum (n-1))

let main (n:int(*-:{v:Int | true}*)) =
	assert (n <= sum n)