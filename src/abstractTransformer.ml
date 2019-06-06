
open AbstractDomain
open Syntax
open SemanticsDomain
open Util

let rec prop v1 v2 = match v1, v2 with
    | Top, Bot | Table _, Top -> Top, Top
    | Table t, Bot -> v1, Table (init_T (dx_T v1))
    | Relation r1, Relation r2 -> Relation r1, Relation (join_R r1 r2)
    | Table t1, Table t2 -> let t1', t2' = alpha_rename t1 t2 in
        let (z1, v1i, v1o) = t1' and (z2, v2i, v2o) = t2' in
        let v1, v2 = let v2i', v1i' = prop v2i v1i and v1o', v2o' = prop (arrow_V "z" v1o v2i) (arrow_V "z" v2o v2i) in
        (v1i', join_V v1o v1o'), (v2i', join_V v2o v2o')
        in
        let t1'' = (z1, fst v1, snd v1) and t2'' = (z1, fst v2, snd v2) in
        Table t1'', Table t2''
    | _, _ -> v1, join_V v1 v2

let iterUpdate m v l = NodeMap.map (fun x -> arrow_V (string_of_int l) x v) m

let iterMap m c = NodeMap.fold (fun n x v -> let EN (env, label) = n in
    c_V v x (string_of_int label)) m (init_V_c c)

let iterEnv env v = VarMap.fold (fun var n a -> scop_V var n a) env v

let rec step term env m =
    let n = EN (env, loc term) in
    let find n m = NodeMap.find_opt n m |> Opt.get_or_else Bot in
    match term with
    | Const (c, l) ->
        let v = find n m in (*M[env*l]*)
        if v = Bot then
        let cv = iterMap m c in
        let v' = join_V v cv in
        m |> NodeMap.add n v'
        else m
    | Var (x, l) ->
      let nx = VarMap.find x env in
      let vx = equal_V (find nx m) (string_of_int l) x in
      let v = find n m in (*M[env*l]*)
      let tx', t' = prop vx v in
      m |> NodeMap.add nx tx' |> NodeMap.add n t'
    | App (e1, e2, l) ->
        let m1 = step e1 env m in
        let n1 = EN (env, loc e1) in
        let t1 = find n1 m1 in
        if t1 = Bot then m1
        else if not @@ is_table t1 then
        (Printf.printf "Error at location %s: expected function, but found %s.\n"
        (string_of_int (loc e1)) (string_of_value t1);
        m1 |> NodeMap.add n Top)
        else
            let m2 = step e2 env m1 in
            let n2 = EN (env, loc e2) in
            let t2 = find n2 m2 in (*M[env*l2]*)
            (match t2 with
                | Bot -> m2
                | Top -> m2 |> NodeMap.add n Top
                | _ -> let t = find n m2 in
                let t_temp = (dx_T t1), t2, t in
                let t1', t0 = prop t1 (Table t_temp) in
                let t2', t' = io_T t0 in
                m2 |> NodeMap.add n1 t1' |> NodeMap.add n2 t2' |> NodeMap.add n t'
            )
    | BinOp (bop, e1, e2, l) ->
        let m1 = step e1 env m in
        let m2 = step e2 env m in
        let n1 = EN (env, loc e1) in
        let t1 = find n1 m1 in
        let n2 = EN (env, loc e2) in
        let t2 = find n2 m2 in
        let t' = op_V t1 t2 bop in
        let t'' = arrow_V (string_of_int (loc e1)) t' t1 in
        let res_t = arrow_V (string_of_int (loc e2)) t'' t2 in
        (if is_Relation t1 then 
            if is_Relation t2 then ()
            else (Printf.printf "Error at location %s: expected value, but found %s.\n"
            (string_of_int (loc e2)) (string_of_value t2))
        else (Printf.printf "Error at location %s: expected value, but found %s.\n"
        (string_of_int (loc e1)) (string_of_value t1))) ;
        m2 |> NodeMap.add n1 t1 |> NodeMap.add n2 t2 |> NodeMap.add n res_t
    | Ite (e0, e1, e2, l) ->
        let m0 = step e0 env m in
        let n0 = EN (env, loc e0) in
        let t0 = find n0 m0 in
        if t0 = Bot then m0 else
        if not @@ SemanticsDomain.is_bool_V t0 then m0 |> NodeMap.add n Top else
        begin
            let t_true = meet_V (init_V_b true) t0 in
            let t_false = meet_V (init_V_b false) t0 in
            let m1 = step e1 env (iterUpdate m t_true (loc e0)) in
            let m2 = step e2 env (iterUpdate m t_false (loc e0)) in
            let n1 = EN (env, loc e1) in
            let t1 = find n1 m1 in
            let n2 = EN (env, loc e2) in
            let t2 = find n2 m2 in
            let t1', t' = prop t1 (find n m1) and t2', t'' = prop t2 (find n m2) in
            let m1' = m1 |> NodeMap.add n1 t1' |> NodeMap.add n t' and
            m2' = m2 |> NodeMap.add n2 t2' |> NodeMap.add n t'' in
            join_M (join_M m0 m1') m2'
        end
    | Rec (f_opt, x, lx, e1, l) -> 
        let t0 = find n m in
        let t = if t0 = Bot then Table (init_T "z") else t0 in
        let tl, tr = io_T t in
        if tl = Bot then m |> NodeMap.add n t
        else 
        if tr = Top then top_M m else
        begin
            let nx = EN (env, lx) in
            let f_nf_opt = Opt.map (fun (f, lf) -> f, EN (env, lf)) f_opt in
            let env1 =
                env |> VarMap.add x nx |>
                (Opt.map (uncurry VarMap.add) f_nf_opt |>
                 Opt.get_or_else (fun env -> env))
            in
            let n1 = EN (env, loc e1) in 
            let tx = find nx m in
            let t1 = equal_V (find n1 m) (dx_T t) (string_of_int lx) in
            let prop_t = Table ((dx_T t), tx, t1) in
            let px_t, t1' = prop prop_t t in
            let nf_t2_tf'_opt =
                Opt.map (fun (_, nf) ->
                  let tf = find nf m in
                  let t2, tf' = prop t tf in
                  nf, t2, tf') f_nf_opt
            in
            let tx', t1' = io_T px_t in
            let m1 = m |> NodeMap.add nx tx' |> NodeMap.add n1 (equal_V t1' (string_of_int lx) (dx_T t)) |>
            (Opt.map (fun (nf, t'', tf') -> fun m' -> m' |> NodeMap.add nf tf' |> NodeMap.add n (join_V t1' t''))
            nf_t2_tf'_opt |> Opt.get_or_else (NodeMap.add n t1')) in
            step e1 env1 m1
        end 
        

(** Widening **)
let widening m1 m2 = let find n m = NodeMap.find_opt n m |> Opt.get_or_else Bot in
    NodeMap.mapi (fun n a -> wid_V a (find n m1)) m2

(** Fixpoint loop *)
let rec fix e k env m =
  Printf.printf "step %d\n" k;
  print_exec_map stdout m;
  let m' = step e env m in
  let m'' = widening m m' in
  if leq_M m'' m then m
  else fix e (k + 1) env m''

(** Semantic function *)
let s e = fix e 0 VarMap.empty NodeMap.empty

let label e =
    let rec l k = function
      | Const (c, _) -> Const (c, k), k + 1
      | Var (x, _) -> Var (x, k), k + 1
      | App (e1, e2, _) ->
          let e1', k1 = l k e1 in
          let e2', k2 = l k1 e2 in
          App (e1', e2', k2), k2 + 1
      | Rec (fopt, x, _, e1, _) ->
          let fopt', k1 =
            fopt |>
            Opt.map (function (f, _) -> Some (f, k), k + 1) |>
            Opt.get_or_else (None, k)
          in
          let e1', k2 = l (k1 + 1) e1 in
        Rec (fopt', x, k1, e1', k2), k2 + 1
      | Ite (e0, e1, e2, _) ->
          let e0', k0 = l k e0 in
          let e1', k1 = l k0 e1 in
          let e2', k2 = l k1 e2 in
          Ite (e0', e1', e2', k2), k2 + 1
      | BinOp (bop, e1, e2, _) ->
        let e1', k1 = l k e1 in
        let e2', k2 = l k1 e2 in
        BinOp (bop, e1, e2, k2), k2 + 1
    in
    l 0 e |> fst