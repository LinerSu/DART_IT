
let rec bot _ = bot ()
let fail _ = assert false

   let rec fib_without_checking_1060 set_flag_fib_1052 s_fib_n_1049 n_1031 =
     let set_flag_fib_1052 = true
     in
     let s_fib_n_1049 = n_1031
     in
       if n_1031 < 2 then
         1
       else
         fib_without_checking_1060 set_flag_fib_1052 s_fib_n_1049 (n_1031 - 1)
         +
         fib_without_checking_1060 set_flag_fib_1052 s_fib_n_1049 (n_1031 - 2)

   let rec fib_1030 prev_set_flag_fib_1051 s_prev_fib_n_1050 n_1031 =
     let u =if prev_set_flag_fib_1051 then
              let u_1078 = fail ()
              in
                bot()
            else () in
            fib_without_checking_1060 prev_set_flag_fib_1051 s_prev_fib_n_1050
              n_1031

   let main (r:int(*-:{v:Int | true}*)) =
     let set_flag_fib_1052 = false in
     let s_fib_n_1049 = 0 in
     fib_1030 set_flag_fib_1052 s_fib_n_1049 r