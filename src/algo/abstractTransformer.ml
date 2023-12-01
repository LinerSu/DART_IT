open AbstractDomain
open Syntax
open SemanticDomain
open SemanticsDomain
open SensitiveDomain
open SenSemantics
open TracePartDomain
open Printer
open Util
open Config
open AbstractEv
(*
** c[M] is a single base refinement type that pulls in all the environment dependencies from M
M = n1 |-> {v: int | v >= 2}, n2 |-> z:{v: int | v >= 0} -> {v: int | v = z}, n3 |-> {v: bool | v = true}
c[M] = {v: int | v = c && n1 >= 2}

** t[M]
    t' = {v:int | v = 2}
    x in scope and M^t[x] = {v: bool | v = true}
    the scope of t is the set of all nodes in the range (i.e. codomain) of the environment component of n.
    t'[M^t] = {v: int | v = 2 && x = true}
** True False
    Using v = 1 be true once inside vt and v = 1 be false inside vf
*)

type stage_t =
  | Widening
  | Narrowing
  
module AssertionPosMap =  Map.Make(struct
  type t = Syntax.pos
  let compare = compare
  end)

type asst_map_t = (int * int) AssertionPosMap.t

let sens : asst_map_t ref = ref AssertionPosMap.empty

module UpdatedNodeMap =  Map.Make(struct
  type t = node_s_t
  let compare = compare_node
  end)

type updated_nodes_map_t = (bool) UpdatedNodeMap.t

(* let updated_nodes = ref UpdatedNodeMap.empty *)

let env0, m0 = 
    let enva, ma = array_M VarMap.empty (NodeMap.create 500) in
    let envb, mb = list_M enva ma in
    envb, mb

(* Create a fresh variable name *)
let fresh_z= fresh_func "z"

let arrow_V x1 x2 = measure_call "arrow_V" (arrow_V x1 x2)
let forget_V x = measure_call "forget_V" (forget_V x)
let stren_V x = measure_call "stren_V" (stren_V x)
let join_V e = measure_call "join_V" (join_V e)
let meet_V e = measure_call "meet_V" (meet_V e)
let equal_V e = measure_call "equal_V" (equal_V e)
let proj_V e = measure_call "proj_V" (proj_V e)
let sat_equal_V e = measure_call "sat_equal_V" (sat_equal_V e)


let rec prop (ve1: value_te) (ve2: value_te): (value_te * value_te) = 
    match ve1, ve2 with
    | TEBot, _ -> TEBot, ve2 
    | TypeAndEff _, TETop -> TETop, TETop
    | TypeAndEff (v,e), TEBot -> 
       let (v1, v2) = prop_v v Bot in 
       (TypeAndEff (v1, e)), (TypeAndEff (v2, e))
    | TypeAndEff (v1, e1), TypeAndEff(v2, e2) -> 
       if v2 = Top then (TETop, TETop)
       else
         let v1', v2' = prop_v v1 v2 in
         let e1', e2' = prop_eff e1 e2 in 
         (TypeAndEff (v1', e1'), TypeAndEff (v2', e2'))
    | TETop, _ -> TETop, TETop
and prop_eff eff1 eff2 = match eff1, eff2 with
    | EffTop, _ -> EffTop, EffTop
    | _, EffTop -> eff1, EffTop
    | _, EffBot -> eff1, eff1 
    | EffBot, _ -> EffBot, eff2
    | Effect _, Effect _ -> eff1, (join_Eff eff1 eff2)
and prop_v (v1: value_tt) (v2: value_tt): (value_tt * value_tt) = match v1, v2 with
    | Top, Bot | Table _, Top -> Top, Top
    | Table t, Bot ->
        let t' = init_T (dx_T (TypeAndEff (v1, empty_eff))) in
        v1, Table t'
    | Relation r1, Relation r2 ->
        if leq_R r1 r2 then v1, v2 else
        Relation r1, Relation (join_R r1 r2)
    | Table t1, Table t2 ->
       let prop_table_entry cs (ve1i, ve1o) (ve2i, ve2o) =
         let destruct_VE = function 
           | TEBot -> Bot, EffBot
           | TypeAndEff (v, e) -> v, e
           | TETop -> Top, EffTop 
         in
         let z = cs in
         let z = get_trace_data z in
         let v1i, e1i = destruct_VE ve1i in
         let v2i, e2i = destruct_VE ve2i in
         let ve1ot, ve2ip = 
           if (is_Array v1i && is_Array v2i) || (is_List v1i && is_List v2i) then
             let l1 = get_len_var_V v1i in
             let e1 = get_item_var_V v1i in
             let l2 = get_len_var_V v2i in
             let e2 = get_item_var_V v2i in
             let ve = replace_VE ve1o l1 l2 in
             replace_VE ve e1 e2, (forget_VE l1 ve2i |> forget_VE e1)
           else ve1o, ve2i
         in
         let ve1i', ve2i', ve1o', ve2o' = 
           let opt_i = false 
                       (*Optimization 1: If those two are the same, ignore the prop step*)
                       || (ve1i <> TEBot && ve2i <> TEBot && eq_VE ve2i ve1i) in
           let ve2i', ve1i' = 
             if opt_i then ve2i, ve1i else 
               prop ve2i ve1i 
           in
           let opt_o = false
                       (*Optimization 2: If those two are the same, ignore the prop step*)
                       || (ve2o <> TEBot && ve1o <> TEBot && eq_VE ve1ot ve2o)
           in
           let ve1o', ve2o' = 
             let v2ip = match ve2ip with 
               | TEBot -> Bot
               | TypeAndEff (v, _) -> v
               | TETop -> Top 
             in
             if opt_o then ve1ot, ve2o else
               prop (arrow_VE z ve1ot v2ip) (arrow_VE z ve2o v2ip)
           in
           let v1i', e1i' = destruct_VE ve1i' in
           let v2i', e2i' = destruct_VE ve2i' in
           let ve1o' =
             if (is_Array v1i' && is_Array v2i') || (is_List v1i' && is_List v2i') then
                let l1 = get_len_var_V v1i' in
                let e1 = get_item_var_V v1i' in
                let l2 = get_len_var_V v2i' in
                let e2 = get_item_var_V v2i' in
                let ve = replace_VE ve1o' l2 l1 in
                replace_VE ve e2 e1
             else ve1o'
           in
           (* if true then
              begin
              (if true then
              begin
              Format.printf "\n<=== prop o ===>%s\n" z;
              pr_value Format.std_formatter v1ot;
              Format.printf "\n";
              Format.printf "\n<--- v2i --->\n";
              pr_value Format.std_formatter v2i;
              Format.printf "\n";
              pr_value Format.std_formatter v2ip;
              Format.printf "\n";
              pr_value Format.std_formatter (arrow_V z v1ot v2ip);
              Format.printf "\n<<~~~~>>\n";
              pr_value Format.std_formatter (arrow_V z v2o v2ip);
              Format.printf "\n";
              end
              );
              (if true then
              begin
              Format.printf "\n<=== res ===>%s\n" z;
              pr_value Format.std_formatter v1o';
              Format.printf "\n<<~~~~>>\n";
              pr_value Format.std_formatter v2o';
              Format.printf "\n";
              end
              );
              end; *)
           let ve1o', ve2o' = 
              if opt_o then ve1o', ve2o' else (join_VE ve1o ve1o', join_VE ve2o ve2o')
           in
           ve1i', ve2i', ve1o', ve2o'
         in
         (ve1i', ve1o'), (ve2i', ve2o') 
       in
       let t1', t2' =
         prop_table prop_table_entry alpha_rename_VE t1 t2
       in
       Table t1', Table t2'
    | Ary ary1, Ary ary2 -> let ary1', ary2' = alpha_rename_Arys ary1 ary2 in
                           let ary' = (join_Ary ary1' ary2') in
                           let _, ary2'' = alpha_rename_Arys ary2 ary'  in
                           (* let _ = alpha_rename_Arys ary1 ary' in *)
                           Ary ary1, Ary ary2''
    | Lst lst1, Lst lst2 ->
       (* (if true then
          begin
          Format.printf "\n<=== prop list ===>\n";
          pr_value Format.std_formatter (Lst lst1);
          Format.printf "\n<<~~~~>>\n";
          pr_value Format.std_formatter (Lst lst2);
          Format.printf "\n";
          end
          ); *)
       let lst1', lst2' = alpha_rename_Lsts lst1 lst2 in
        (* (if true then
           begin
           Format.printf "\n<=== after rename list ===>\n";
           pr_value Format.std_formatter (Lst lst1');
           Format.printf "\n<<~~~~>>\n";
           pr_value Format.std_formatter (Lst lst2');
           Format.printf "\n";
           end
           ); *)
        let lst1'', lst2'' = prop_Lst prop lst1' lst2' in
        (* (if true then
           begin
           Format.printf "\n<=== res ===>\n";
           pr_value Format.std_formatter (Lst lst1'');
           Format.printf "\n<<~~~~>>\n";
           pr_value Format.std_formatter (Lst lst2'');
           Format.printf "\n";
           end
           ); *)
        let _, lst2'' = alpha_rename_Lsts lst2 lst2'' in
        Lst lst1'', Lst lst2''
    | Ary ary, Bot -> let vars, r = ary in
                     let ary' = init_Ary vars in
                     v1, Ary ary'
    | Lst lst, Bot -> let vars, r = lst in
                     let lst' = init_Lst vars in
                     v1, Lst lst'
    | Tuple u, Bot ->  let u' = List.init (List.length u) (fun _ ->
                                   TEBot) in
                      v1, Tuple u'
    | Tuple u1, Tuple u2 -> if List.length u1 <> List.length u2 then
                             raise (Invalid_argument "Prop tuples should have the same form")
                           else
                             let u1', u2' = List.fold_right2 (fun v1 v2 (u1', u2') -> 
                                                let v1', v2' = prop v1 v2 in
                                                (v1'::u1', v2'::u2')
                                              ) u1 u2 ([],[]) in
                             Tuple u1', Tuple u2'
    | _, _ -> if leq_V v1 v2 then v1, v2 else v1, join_V v1 v2

let prop p = measure_call "prop" (prop p)

        
(* let lc_env env1 env2 = 
    Array.fold_left (fun a id -> if Array.mem id a then a else Array.append a [|id|] ) env2 env1 *)

(* let rec nav (v1: value_t) (v2: value_t): (value_t * value_t) = match v1, v2 with
    | Relation r1, Relation r2 -> 
            let r2' = if leq_R r1 r2 then r1 else r2
            in
            Relation r1, Relation r2'
    | Ary ary1, Ary ary2 -> let ary1', ary2' = alpha_rename_Arys ary1 ary2 in
      let _, ary2'' = alpha_rename_Arys ary2 (join_Ary ary1' ary2') in
      Ary ary1, Ary ary2''
    | Table t1, Table t2 -> 
        let t1', t2' = alpha_rename t1 t2 in
        let (z1, v1i, v1o) = t1' and (z2, v2i, v2o) = t2' in
        let v1ot = 
            if is_Array v1i && is_Array v2i then
                let l1 = get_len_var_V v1i in
                let l2 = get_len_var_V v2i in
                replace_V v1o l1 l2
            else v1o
        in
        let p1, p2 = 
            let v1i', v2i', v1o', v2o' = 
                let v2i', v1i' = nav v2i v1i in
                let v1o', v2o' = nav (arrow_V z1 v1ot v2i) (arrow_V z1 v2o v2i) in
                let v1o', v2o' = match leq_V v1o' v1ot, leq_V v2o' v2o with
                    | false, false -> v1ot, v2o
                    | true, false -> v1o', v2o
                    | false, true -> v1ot, v2o'
                    | true, true -> v1o', v2o'
                in
                let v1o' =
                    if is_Array v1i' && is_Array v2i' then
                        let l1 = get_len_var_V v1i' in
                        let l2 = get_len_var_V v2i' in
                        replace_V v1o' l2 l1
                    else v1o'
                in
                v1i', v2i', v1o', v2o'
            in
            (v1i', v1o'), (v2i', v2o') 
        in
        let t1'' = (z1, fst p1, snd p1) and t2'' = (z2, fst p2, snd p2) in
        Table t1'', Table t2''
    | _, _ -> v1, v2 *)

let get_env_list (env: env_t) (cs: trace_t) (m: exec_map_t) = 
    let find n m = NodeMap.find_opt n m |> Opt.get_or_else TEBot in
    let env_l = VarMap.bindings env in
    let helper lst (x, (n, _)) =
      let n = construct_snode cs n in
      let te = find n m in
      let lst' = match te with 
        | TypeAndEff (t, _) -> if is_List t then 
                                (get_item_var_V t) :: (get_len_var_V t) :: lst
                              else lst
        | _ -> lst
      in
      x :: lst'
    in
    (List.fold_left helper [] env_l) @ (AbstractEv.spec_env ())

let get_env_list e cs = measure_call "get_env_list" (get_env_list e cs)
      
      
let prop_scope (env1: env_t) (env2: env_t) (cs: trace_t) (m: exec_map_t) (ve1: value_te) (ve2: value_te): (value_te * value_te) = 
    let env1 = get_env_list env1 cs m in
    let env2 = get_env_list env2 cs m in
    (* let v1'',_  = prop v1 (proj_V v2 env1)in
    let _, v2'' = prop (proj_V v1 env2) v2 in *)
    let ve1', ve2' = prop ve1 ve2 in
    let ve1'' = proj_VE ve1' env1 in
    let ve2'' = proj_VE ve2' env2 in
    ve1'', ve2''

let prop_scope x1 x2 x3 x4 x5 = measure_call "prop_scope" (prop_scope x1 x2 x3 x4 x5)

      
(** Reset the array nodes **)
let reset (m:exec_map_t): exec_map_t = NodeMap.fold (fun n te m ->
        m |> NodeMap.add n te
    ) m0 m

(* let iterUpdate m v l = NodeMap.map (fun x -> arrow_V l x v) m *)

(* let getVars env = VarMap.fold (fun var n lst -> var :: lst) env [] *)

(* let iterEnv_c env m c = VarMap.fold (fun var n a ->
    let v = NodeMap.find_opt n m |> Opt.get_or_else Top in
    let EN (env', l) = n in
    let lb = name_of_node l in
    c_V a v lb) env (init_V_c c)

let iterEnv_v env m v = VarMap.fold (fun var n a -> 
    let ai = NodeMap.find_opt n m |> Opt.get_or_else Top in
    arrow_V var a ai) env v *)

(* let optmization m n find = (* Not sound for work *)
    if !st <= 6000 then false else
    let t = find n m in
    let pre_t = find n !pre_m in
    opt_eq_V pre_t t *)

let rec list_var_item eis (cs: trace_t) m env nlst left_or_right lst_len = 
    let find n m = NodeMap.find_opt n m |> Opt.get_or_else TEBot in
    let vlst = find nlst m in
    match eis, left_or_right with
    | Var (x, l), true -> 
        let n = construct_vnode env l cs in
        let env1 = env |> VarMap.add x (n, false) in
        let n = construct_snode cs n in
        let te = find n m in
        let tep = cons_temp_lst_VE te vlst in
        (* (if !debug then
        begin
            Format.printf "\n<---Pattern var---> %s\n" l;
            pr_value Format.std_formatter vlst;
            Format.printf "\n<<~~~~>> %s\n" l;
            pr_value Format.std_formatter t;
            pr_value Format.std_formatter tp;
            Format.printf "\n";
        end
        ); *)
        let vlst', tep' = prop vlst tep in
        let te' = extrac_item_VE (get_env_list env1 cs m) tep' in
        (* (if !debug then
        begin
            Format.printf "\nRES for prop:\n";
            pr_value Format.std_formatter vlst';
            Format.printf "\n<<~~~~>>\n";
            pr_value Format.std_formatter t';
            Format.printf "\n";
        end
        ); *)
        let m' = m |> NodeMap.add n te' |> NodeMap.add nlst vlst' in
        m', env1
    | Var(x, l), false ->
        let n = construct_vnode env l cs in
        let env1 = env |> VarMap.add x (n, false) in
        let n = construct_snode cs n in
        let lst = find n m |> get_list_length_item_VE in
        let te_new = reduce_len_VE lst_len lst vlst in
        let _, te' = prop te_new (find n m) in
        let m' = NodeMap.add n te' m in
        m', env1
    | Const (c, l), false ->
        let n = l |> construct_enode env |> construct_snode cs in
        let te_new = pattern_empty_lst_VE vlst in
        let _, te' = prop te_new (find n m) in
        let m' = NodeMap.add n te' m in
        m', env
    | TupleLst (termlst, l), true -> 
        let n = l |> construct_enode env |> construct_snode cs in
        let te = 
            let raw_te = find n m in
            if is_tuple_VE raw_te then raw_te
            else 
              let u' = List.init (List.length termlst) (fun _ ->
                             TEBot) in (init_VE_v (Tuple u')) in
        (* (if !debug then
        begin
            Format.printf "\n<---Pattern tuple---> %s\n" l;
            pr_value Format.std_formatter vlst;
            Format.printf "\n<<~~~~>> %s\n" l;
            pr_value Format.std_formatter t;
            Format.printf "\n";
        end
        ); *)
        let telst = get_tuple_list_VE te in
        let teel = extrac_item_VE (get_env_list env cs m) vlst in
        let tellst = get_tuple_list_VE teel in
        let env', m', telst', tellst' = List.fold_left2 (fun (env, m, li, llst) e (tei, telsti) -> 
            match e with
            | Var (x, l') -> 
                let nx = construct_vnode env l' cs in
                let env1 = env |> VarMap.add x (nx, false) in
                let nx = construct_snode cs nx in
                let tex = find nx m in
                let tei', tex' = prop tei tex in
                let telsti', tei'' = prop telsti tei in
                let m' = m |> NodeMap.add nx tex' in
                env1, m', (join_VE tei' tei'') :: li, telsti' :: llst
            | _ -> raise (Invalid_argument "Tuple only for variables now")
        ) (env, m, [], []) termlst (zip_list telst tellst) in
        let telst', tellst' = List.rev telst', List.rev tellst' in
        let _, tee = destruct_VE te in 
        let _, teele = destruct_VE teel in
        let teele', tee' = prop_eff teele tee in
        let te', vlst' = (TypeAndEff ((Tuple telst'), tee')), 
                         (cons_temp_lst_VE (TypeAndEff ((Tuple tellst'), teele')) vlst) in
        let m'' = m' |> NodeMap. add n te'
            |> NodeMap.add nlst vlst' in
        (* (if !debug then
        begin
            Format.printf "\nRES for tuple:\n";
            pr_value Format.std_formatter vlst';
            Format.printf "\n<<~~~~>>\n";
            pr_value Format.std_formatter t';
            Format.printf "\n";
        end
        ); *)
        m'', env'
    | BinOp (bop, e1, e2, l), _ ->
        let m', env' = list_var_item e1 cs m env nlst true 0 in
        let m'', env'' = list_var_item e2 cs m' env' nlst false (lst_len + 1) in
        m'', env''
    | UnOp (uop, e1, l), true ->
        let m', env' = list_var_item e1 cs m env nlst true 0 in
        m', env'
    | _ -> raise (Invalid_argument "Pattern should only be either constant, variable, and list cons")


let rec prop_predef l ve0 ve =
  match ve0, ve with 
  | TypeAndEff (v0, _), TypeAndEff (v, e) -> TypeAndEff ((prop_predef_v l v0 v), e)
  | _, _ -> ve
and prop_predef_v l v0 v = 
    let l = l |> name_of_node |> create_singleton_trace_loc in
    let rec alpha_rename ve0 ve = 
      match ve0, ve with
      | (TypeAndEff (v0, e0)), (TypeAndEff (v, e)) -> TypeAndEff ((alpha_rename_v v0 v), e)
      | _, _ -> ve
    and alpha_rename_v v0 v = 
        match v0, v with
        | Table t0, Table t -> 
            if table_isempty t || table_isempty t0  then Table t else
            let trace0, (vei0, veo0) = get_full_table_T t0 in
            let trace, (vei, veo) = get_full_table_T t in
            let veo' = alpha_rename veo0 
                         (alpha_rename_VE veo (get_trace_data trace) (get_trace_data trace0)) 
            in
            let t' = construct_table trace0 (vei, veo') in
            Table t'
        | _, _ -> v      
    in
    match v0, v with
    | Table t0, Table t -> 
        let cs0, _ = get_full_table_T t0 in
        let vpdef = Table (construct_table cs0 (get_table_by_cs_T cs0 t)) in
        let pdefvp = ref (construct_table cs0 (get_table_by_cs_T cs0 t)) in
        let t' = table_mapi (fun cs (vei, veo) -> 
            if cs = cs0 || (not (is_subtrace l cs)) then vei, veo else
            let vs = Table (construct_table cs (vei, veo)) in
            let v' = vs |> alpha_rename_v v0 in
            let vt, v'' = prop_v vpdef v' in
            pdefvp := (match join_V vt (Table !pdefvp) with 
                      | Table t -> t 
                      | _ -> raise (Invalid_argument "Should be a table"));
            let vei', veo' = match alpha_rename_v vs v'' with
                | Table t'' -> let _, (vei, veo) = get_full_table_T t'' in (vei, veo)
                | _ -> raise (Invalid_argument "Expect predefined functions as table")
            in vei', veo') t
        in Table (
            let _, veio = get_full_table_T !pdefvp in
            t' |> update_table cs0 veio
        )
    | _, _ -> v

let rec step term (env: env_t) (trace: trace_t) (ec: effect_t) (ae: value_tt) (assertion: bool) (is_rec: bool) (m:exec_map_t) =
  let n = loc term |> construct_enode env |> construct_snode trace in
  (* let continue = match UpdatedNodeMap.find_opt n !updated_nodes with | None -> false | Some v -> v in
  if continue then m else begin updated_nodes := UpdatedNodeMap.add n true !updated_nodes; *)
  begin
  let update widen n v m =
    (*NodeMap.update n (function
        | None -> v
        | Some v' -> if false && widen then wid_V v' v else (*join_V v'*) v) m*)
      (* NodeMap.add n v m *)
    NodeMap.update n (fun old_v -> match old_v with None -> v | Some v' -> join_VE v' v) m
  in
  let find n m = NodeMap.find_opt n m |> Opt.get_or_else TEBot in
  (* let find_ra q e = StateMap.find_opt q e |> Opt.get_or_else (bot_R Plus) in *)
  let init_VE_wec v = TypeAndEff (v, (Effect ec)) in
  let extract_ec = 
    if (!Config.effect_on && (not !Config.ev_trans)) then
        (fun te -> 
          match (extract_eff te) with
          | EffBot | EffTop -> 
              raise (Invalid_argument "An effect should be observable at this stage of the analysis")
          | Effect e -> e)
        else
          (fun te -> StateMap.empty)
  in
  match term with
  | Const (c, l) ->
      (* (if !debug then
      begin
          Format.printf "\n<=== Const ===>\n";
          pr_exp true Format.std_formatter term;
          Format.printf "\n";
      end
      ); *)
      (* if optmization m n find then m else *)
      let te = find n m in (* M[env*l] *)
      let update_t t =  
        if leq_V ae t then t
        else
          let ct = init_V_c c in
          let t' = join_V t ct in
          (stren_V t' ae)
      in
      let update_e eff = join_Eff eff (stren_Eff (Effect ec) ae) in
      let te' = temap (update_t, update_e) te in
            
      (* (if l = "11" then
      begin
          Format.printf "\n<=== Const ===> %s\n" l;
          pr_value Format.std_formatter t;
          Format.printf "\n<<~~ae~~>> %s\n" l;
          pr_value Format.std_formatter ae;
          Format.printf "\n<<~~ RES ~~>>\n";
          pr_value Format.std_formatter t';
          Format.printf "\n";
      end
      ); *)
      m |> update false n te' (* {v = c ^ aE}*)
  | Var (x, l) ->
      (if !debug then
      begin
          Format.printf "\n<=== Var ===>\n";
          pr_exp true Format.std_formatter term;
          Format.printf "\n";
      end
      );
      let (nx, recnb) = VarMap.find x env in
      let envx, lx, lcs = get_vnode nx in
      let nx = construct_snode trace nx in
      
      let tex = find nx m 
                |> temap ((fun tx -> if is_Relation tx then
                                    if sat_equal_V tx x then tx
                                    else equal_V (forget_V x tx) x
                                  else tx),
                          (fun _ -> Effect ec))
      in
      let te = find n m in  (* M[env*l] *)
      (*(if l = "5" || l = "22" then
        begin
        Format.printf "\n<=== Prop Var %s %b ===> %s\n" x recnb lx;
        (* Format.printf "cs %s \n" lcs; *)
        pr_value_and_eff Format.std_formatter tex;
        Format.printf "\n<<~~~~>> %s\n" l;
        pr_value_and_eff Format.std_formatter te;
        Format.printf "\n<<~~ae~~>> %s\n" l;
        pr_value Format.std_formatter ae;
        Format.printf "\n";
        end
        );*)
      let tex', te' = 
        if List.mem lx !pre_def_func then
          let tex0 = find nx m0 in
          let tex = if !trace_len > 0 then prop_predef l tex0 tex else tex in
          prop tex te
        else 
          prop_scope envx env trace m tex te
      in
      (*(if l = "5" || l = "22" then
      begin
          Format.printf "\nRES for prop:\n";
          pr_value_and_eff Format.std_formatter tex';
          Format.printf "\n<<~~~~>>\n";
          pr_value_and_eff Format.std_formatter te';
          Format.printf "\n";
      end
      );*)
      let m' = m |> update false nx tex' |> update false n (stren_VE te' ae) (* t' ^ ae *) in 
      (*(
          if l = "5" || l = "22" then
            begin
              Format.printf "\ntex[post]"; 
              find nx m' |> pr_value_and_eff Format.std_formatter;
              Format.printf "\nte[post]"; 
              find n m' |> pr_value_and_eff Format.std_formatter;
            end
        );*)
      m'
  | App (e1, e2, l) ->
      (if !debug then
      begin
          Format.printf "\n<=== App ===>\n";
          pr_exp true Format.std_formatter term;
          Format.printf "\n";
      end
      );
      let m0 = step e1 env trace ec ae assertion is_rec m in
      let n1 = loc e1 |> construct_enode env |> construct_snode trace in
      let te0 = find n1 m0 in
      let te1, m1 =
        match te0 with
        | TEBot when false ->
            let t =
              fresh_z () |> create_loc_token |> update_trace trace |> init_T
            in
            let te1 = Table t |> init_VE_v in
            te1, update false n1 te1 m0
        | _ -> te0, m0
      in
      if (te1 = TEBot) then m1
      else             
        if not @@ is_table (extract_v te1) then
          (Format.printf "Error at location %s: expected function, but found %s.\n"
            (loc e1) (string_of_value_and_eff te1);
          m1 |> update false n TETop)
        else (* trace0 : [trace0_1, trace0_2], x *)
          let ec' = extract_ec te1 in            
          let m2 = step e2 env trace ec' ae assertion is_rec m1 in
          let n2 = loc e2 |> construct_enode env |> construct_snode trace in
          let te2 = find n2 m2 in (* M[env*l2] *)
          (match te1, te2 with
          | TEBot, _ | _, TEBot -> m2
          | _, TETop -> m2 |> update false n TETop
          | _ ->
              let te = find n m2 in
              let trace =
                if !trace_len > 0 then
                  if is_rec && is_func e1 then trace
                  else loc e1 |> name_of_node |> create_loc_token |> update_trace trace
                else dx_T te1
              in
              let te_temp = Table (construct_table trace (te2, te)) 
                          |> init_VE_v 
              in
              (* let var1, var2 = cs in
                (Format.printf "\nis_rec? %b\n") is_rec;
                (Format.printf "\nAPP cs at %s: %s, %s\n") (loc e1) var1 var2; *)
              (* (if loc e1 = "20" then
                begin
                Format.printf "\n<=== Prop APP ===> %s\n" (loc e1);
                pr_value Format.std_formatter t1;
                Format.printf "\n<<~~~~>> %s\n" l;
                pr_value Format.std_formatter t_temp;
                Format.printf "\n";
                end
                ); *)
              let te1', te0 = 
                (* if optmization m2 n1 find && optmization m2 n2 find && optmization m2 n find then t1, t_temp else *)
                prop te1 te_temp
              in
              (* (if loc e1 = "20" then
                begin
                Format.printf "\nRES for prop:\n";
                pr_value Format.std_formatter t1';
                Format.printf "\n<<~~~~>>\n";
                pr_value Format.std_formatter t0;
                Format.printf "\n";
                end
                ); *)
              let te2', raw_te' = 
                (* if is_array_set e1 then
                  let t2', t' = io_T cs t0 in
                  let elt = proj_V (get_second_table_input_V t') [] in
                  join_for_item_V t2' elt, t'
                  else  *)
                io_T trace te0
              in
              let te' = get_env_list env trace m |> proj_VE raw_te' in
              let res_m = m2 |> update false n1 te1' |> update false n2 te2' |> update false n (stren_VE te' ae) in
              (* if is_array_set e1 && only_shape_V t2' = false then
                let nx = VarMap.find (get_var_name e2) env in
                let envx, lx,_ = get_vnode nx in
                let nx = construct_snode sx nx in
                let tx = find nx m in
                let tx', t2' = prop_scope envx env sx res_m t2' tx in
                res_m |> NodeMap.add n2 t2' |> NodeMap.add nx tx'
                else  *)
              res_m
          )
  | BinOp (bop, e1, e2, l) ->
      (if !debug then
      begin
          Format.printf "\n<=== Binop ===>\n";
          pr_exp true Format.std_formatter term;
          Format.printf "\n";
      end
      );
      let n1 = loc e1 |> construct_enode env |> construct_snode trace in
      let m1 =
        match bop with
        | Cons ->
          let rec cons_list_items ec m term = match term with
            | BinOp (Cons, e1', e2', l') ->
                let l1, te1', m1' = cons_list_items ec m e1' in
                if te1' = TEBot then l1, te1', m1'
                else
                  let ec' = extract_ec te1' in
                  let l2, te2', m2' = cons_list_items ec' m1' e2' in
                  l1 + l2, join_VE te1' te2', m2'
            | _ ->
                let m' = step term env trace ec ae assertion is_rec m in
                let n' = loc term |> construct_enode env |> construct_snode trace in
                let te' = find n' m' in
                1, te', m'
            in
            let len, te1', m1 = cons_list_items ec m e1 in
            let te1 = find n1 m1 in
            let te1', _ = prop te1 te1' in
            m1 |> update false n1 te1'
        | _ -> step e1 env trace ec ae assertion is_rec m
      in
      let te1 = find n1 m1 in
      let ec' = extract_ec te1 in
      let m2 = step e2 env trace ec' ae assertion is_rec m1 in
      let te1 = find n1 m2 in
      let n2 = loc e2 |> construct_enode env |> construct_snode trace in
      let te2 = find n2 m2 in
      if te1 = TEBot || te2 = TEBot then m2 
      else
        begin
          (*if not @@ is_List t2 then
            if not @@ (is_Relation t1) then 
            (Format.printf "Error at location %s: expected value, but found %s.\n"
            (loc e1) (string_of_value t1))
            else (if not @@ (is_Relation t2) then
            Format.printf "Error at location %s: expected value, but found %s.\n"
            (loc e2) (string_of_value t2));*)
          
          let bop =
            match bop, e1, e2 with
            | Mod, Const _, Const _ -> Mod
            | Mod, _, Const _ -> Modc
            | _ -> bop
          in
          let te = find n m2 in
          (* if optmization m2 n1 find && optmization m2 n2 find && optmization m2 n find then m2 else *)
          let raw_te =
            match bop with
            | Cons (* list op *) ->
              (* (pr_value_and_eff Format.std_formatter te1;
              pr_value_and_eff Format.std_formatter te2); *)
              list_cons_VE te1 te2
            | And | Or (* bool op *) ->
              bool_op_VE bop te1 te2
            | Modc ->
              (* {v:int | a(t) ^ v = n1 mod const }[n1 <- t1] *)
              let ted = init_VE_v (Relation (top_R bop)) in
              let node_1 = e1 |> loc |> name_of_node in
              let te' = arrow_VE node_1 ted (extract_v te1) 
                        |> temap (id, fun _ -> extract_eff te1) in
              let te''' = op_VE node_1 (str_of_const e2) bop te' 
                          |> temap (id, fun _ -> extract_eff te2) in
              let te = get_env_list env trace m2 |> proj_VE te''' in
              te
          | Seq ->
              te2
          | _ ->
              (* {v:int | a(t) ^ v = n1 op n2 }[n1 <- t1, n2 <- t2] *)
              let ted = init_VE_v (Relation (top_R bop)) in
              let node_1 = e1 |> loc |> name_of_node in
              let node_2 = e2 |> loc |> name_of_node in
              let te' = arrow_VE node_1 ted (extract_v te1) |> temap (id, fun _ -> extract_eff te1) in
              let te'' = arrow_VE node_2 te' (extract_v te2) |> temap (id, fun _ -> extract_eff te2) in
              (* (if !debug then
              begin
                  Format.printf "\n<=== Op binop ===> %s\n" (loc e1);
                  pr_value Format.std_formatter t';
                  Format.printf "\n<<~~~~>>\n";
                  pr_value Format.std_formatter t'';
                  Format.printf "\n";
              end
              ); *)
              let te''' = op_VE node_1 node_2 bop te'' in
              (* (if !debug then
              begin
                  Format.printf "\n<=== RES Op binop ===> \n";
                  pr_value Format.std_formatter t''';
                  Format.printf "\n";
              end
              ); *)
              let temp_te = get_env_list env trace m2 |> proj_VE te''' in
              (* if !domain = "Box" then
                temp_t |> der_V e1 |> der_V e2  (* Deprecated: Solve remaining constraint only for box*)
                else  *)
              temp_te
        in
          (* (if !debug then 
          begin
              Format.printf "\n<=== Prop binop ===> %s\n" l;
              pr_value Format.std_formatter raw_t;
              Format.printf "\n<<~~~~>> \n";
              pr_value Format.std_formatter t;
              Format.printf "\n";
          end
          ); *)
          let _, re_te =
            if is_Relation (extract_v raw_te) then raw_te,raw_te else 
            (* let t, raw_t = alpha_rename_Vs t raw_t in *)
            prop raw_te te
          in
          (* (if l = "18" then
              begin
                  Format.printf "\nRES binop for prop:\n";
                  pr_value Format.std_formatter re_t;
                  Format.printf "\n<-- ae -->\n";
                  pr_value Format.std_formatter ae;
                  Format.printf "\n";
              end
          ); *)
          let m2, re_te =
            match bop with
            | Cons ->
                let te1l = cons_temp_lst_VE te1 re_te in
                let te1l', re_te' = prop te1l re_te in
                let te1' = extrac_item_VE (get_env_list env trace m2) te1l' in
                let te2', re_te'' = prop te2 re_te' in
                m2 |> update false n1 te1' |> update false n2 te2', re_te'
            | Seq ->
                let te2', re_te' = prop te2 re_te in
                m2 |> update false n2 te2', re_te' 
            | _ -> m2, re_te 
          in
          (* (if l = "73" then
              begin
                  Format.printf "\nRES for op:\n";
                  pr_value Format.std_formatter re_t;
                  Format.printf "\n";
              end
              ); *)
          (* (if string_of_op bop = ">" then
          begin
              Format.printf "\nRES for test:\n";
              pr_value Format.std_formatter re_t;
              Format.printf "\n";
          end
          ); *)
          m2 |> update false n (stren_VE re_te ae)
      end
  | UnOp (uop, e1, l) ->
      (* (if !debug then
      begin
          Format.printf "\n<=== Unop ===>\n";
          pr_exp true Format.std_formatter term;
          Format.printf "\n";
      end
      ); *)
      let n1 = loc e1 |> construct_enode env |> construct_snode trace in
      let m1 = step e1 env trace ec ae assertion is_rec m in
      let te1 = find n1 m1 in
      if te1 = TEBot then m1
      else
        let node_1 = e1 |> loc |> name_of_node in
        let ted = init_VE_v (Relation (utop_R uop)) in
        let te = find n m1 in
        let te' = arrow_VE node_1 ted (extract_v te1) |> temap (id, fun _ -> extract_eff te1) in
        let te'' = uop_VE uop node_1 te' in
        let raw_te = get_env_list env trace m1 |> proj_VE te'' in
        (* if !domain = "Box" then
          temp_t |> der_V e1 |> der_V e2  (* Deprecated: Solve remaining constraint only for box*)
          else  *)
        let _, re_te =
          if is_Relation (extract_v raw_te)
          then raw_te, raw_te
          else prop raw_te te
        in
        m1 |> update false n (stren_VE re_te ae)
  | Ite (e0, e1, e2, l, asst) ->
      (* (if !debug then
      begin
          Format.printf "\n<=== Ite ===>\n";
          pr_exp true Format.std_formatter term;
          Format.printf "\n";
      end
      ); *)
      let n0 = loc e0 |> construct_enode env |> construct_snode trace in
      let m0 = 
          (* if optmization m n0 find then m else  *)
          step e0 env trace ec ae assertion is_rec m in
      let te0 = find n0 m0 in
      if te0 = TEBot then m0 else
      if not @@ is_bool_V (extract_v te0) then m0 |> update false n TETop else
      begin
          let { isast = isast; ps = pos } = asst in
          if assertion && isast && not (is_bool_bot_V (extract_v te0)) && 
              not (is_bool_false_V (extract_v te0)) && not (only_shape_V ae)
          then print_loc pos else
          let t_true = meet_V (extrac_bool_V (extract_v te0) true) ae in (* Meet with ae*)
          let t_false = meet_V (extrac_bool_V (extract_v te0) false) ae in
          (if assertion && isast then 
              let i, j = AssertionPosMap.find_opt pos !sens |> Opt.get_or_else (0,0) in
              sens := AssertionPosMap.add pos ((if is_bool_bot_V (extract_v te0) && 
              (is_asst_false e0 = false && only_shape_V ae = false) 
              then i + 1 else i), j + 1) !sens);
          let te = find n m0 in
          let ec' = extract_ec te0 in
          let m1 = step e1 env trace ec' t_true assertion is_rec m0 in
          let n1 = loc e1 |> construct_enode env |> construct_snode trace in
          let te1 = find n1 m1 in
          (* (if !debug then
          begin
              Format.printf "\n<=== Prop then ===> %s\n" (loc e1);
              pr_value Format.std_formatter t1;
              Format.printf "\n<<~~~~>> %s\n" l;
              pr_value Format.std_formatter (find n m1);
              Format.printf "\n";
          end
            ); *)
          let te1', te' = 
              (* if optmization m1 n1 find && optmization m1 n find then t1, (find n m1) else  *)
              (* let t1, t = alpha_rename_Vs t1 t in *)
              prop te1 te in
          (* (if !debug then
          begin
              Format.printf "\nRES for prop:\n";
              pr_value Format.std_formatter t1';
              Format.printf "\n<<~~~~>>\n";
              pr_value Format.std_formatter t';
              Format.printf "\n";
          end
          );  *)
          let m2 = step e2 env trace ec' t_false assertion is_rec m1 in
          let n2 = loc e2 |> construct_enode env |> construct_snode trace in
          let te2 = find n2 m2 in
          (* (if !debug then 
          begin
              Format.printf "\n<=== Prop else ===> %s\n" (loc e2);
              pr_value Format.std_formatter t2;
              Format.printf "\n<<~~~~>> %s\n" l;
              pr_value Format.std_formatter (find n m2);
              Format.printf "\n";
          end
          ); *)
          let te2', te'' = 
              (* if optmization m2 n2 find && optmization m2 n find then t1, (find n m2) else *)
              (* let t2, t = alpha_rename_Vs t2 t in *)
              prop te2 te in
          (* (if !debug then
          begin
              Format.printf "\nRES for prop:\n";
              pr_value Format.std_formatter t2';
              Format.printf "\n<<~~~~>>\n";
              pr_value Format.std_formatter t'';
              Format.printf "\n";
          end
            );  *)
          (* (if (loc e1) = "63" then 
          begin
              Format.printf "\n<=== join then else ===> %s\n" (loc e1);
              pr_value Format.std_formatter t';
              Format.printf "\n<<~~~~>> %s\n" (loc e2);
              pr_value Format.std_formatter t'';
              Format.printf "\n";
          end
          ); *)
          (* (if loc e0 = "10" then
              begin
              Format.printf "\n<=== ite ae ===> %s %b\n" l (only_shape_V ae);
              pr_value Format.std_formatter ae;
              Format.printf "\n<<~~ then part ~~>>\n";
              pr_value Format.std_formatter t_true;
              Format.printf "\n<----->\n";
              pr_value Format.std_formatter t1';
              Format.printf "\n<<~~ else part ~~>>\n";
              pr_value Format.std_formatter t_false;
              Format.printf "\n<----->\n";
              pr_value Format.std_formatter t2';
              Format.printf "\n";
              end
          ); *)
          (* let t'', t' = alpha_rename_Vs t'' t' in *)
          let te1' = stren_ite_VE te1' t_true in
          let te2' = stren_ite_VE te2' t_false in
          (* (if loc e0 = "10" then
              begin
              Format.printf "\n<=== RES for ae ===> %s\n" l;
              pr_value Format.std_formatter t1';
              Format.printf "\n<<~~~~>>\n";
              pr_value Format.std_formatter t2';
              Format.printf "\n";
              end
          ); *)
          let te_n' = join_VE (stren_VE te' ae) (stren_VE te'' ae) in
          (* (if (loc e1) = "63" then
          begin
              Format.printf "\nRES for join then else:\n";
              pr_value Format.std_formatter t_n';
              Format.printf "\n";
          end
            );  *)
          let res_m = m2 |> update false n1 te1' |> update false n2 te2' |> update false n te_n' in
          res_m
      end
  | Rec (f_opt, (x, lx), e1, l) ->
      (* (if !debug then
      begin
          Format.printf "\n<=== Func ===>\n";
          pr_exp true Format.std_formatter term;
          Format.printf "\n";
      end
      ); *)
      let te0 = find n m in
      let te =
        match te0 with
        | TEBot ->
            let tee = fresh_z () |> create_loc_token |> update_trace trace |> init_T in
            Table tee |> init_VE_wec
        | _ -> te0
      in
      let trace' = trace in
      let is_rec' = Opt.exist f_opt || is_rec in
      step_func (fun trace (tel, ter) m' -> 
          if tel = TEBot then m' |> update false n te
          else if ter = TETop then top_M m' else
          begin
            let z = get_trace_data trace in
            let f_nf_opt =
              Opt.map (fun (f, lf) -> f, (construct_vnode env lf trace, true)) f_opt
            in
            let nx = construct_vnode env lx trace in
            let env' = env |> VarMap.add x (nx, false) in
            let nx = construct_snode trace nx in
            let env1 =
              env' |>
              (Opt.map (uncurry VarMap.add) f_nf_opt |>
              Opt.get_or_else (fun env -> env))
            in
            let n1 = loc e1 |> construct_enode env1 |> construct_snode trace in
            let tex = find nx m in
            let ae' = if (x <> "_" && is_Relation (extract_v tex)) || is_List (extract_v tex) then 
              (* if only_shape_V tx then ae else  *)
              (arrow_V x ae (extract_v tex)) else ae in
            let te1 = if x = "_" then find n1 m else replace_VE (find n1 m) x z in
            let prop_t = Table (construct_table trace (tex, te1)) in
            let prop_te = TypeAndEff (prop_t, (extract_eff te)) in
            (* (if l = "20" then
              begin
              Format.printf "\n<=== Prop lamb ===> %s %s\n" lx (loc e1);
              pr_value Format.std_formatter prop_t;
              Format.printf "\n<<~~~~>> %s\n" l;
              pr_value Format.std_formatter t;
              end
              ); *)
            let px_te, te1 = prop_scope env1 env' trace m prop_te te in
            (* (if l = "20" then
              begin
              Format.printf "\nRES for prop:\n";
              pr_value Format.std_formatter px_t;
              Format.printf "\n<<~~~~>>\n";
              pr_value Format.std_formatter t1;
              Format.printf "\n";
              end
              ); *)
            let nf_t2_tf'_opt =
              Opt.map (fun (_, (nf, bf)) ->
                let envf, lf, fcs = get_vnode nf in
                let nf = construct_snode trace nf in
                let tef = find nf m in
                (* (if lf = "4" then
                      begin
                          Format.printf "\n<=== Prop um ===> %s\n" l;
                          pr_value Format.std_formatter t;
                          Format.printf "\n<<~~~~>> %s\n" lf;
                          pr_value Format.std_formatter tf;
                          Format.printf "\n";
                      end
                ); *)
                let te2, tef' = prop_scope env' envf trace m te tef in
                (* let t2, tf' = prop t tf in *)
                (* (if lf = "4" then
                  begin
                  Format.printf "\nRES for prop:\n";
                  pr_value Format.std_formatter t2;
                  Format.printf "\n<<~~~~>>\n";
                  pr_value Format.std_formatter tf';
                  Format.printf "\n";
                  end
                  ); *)
                nf, te2, tef') f_nf_opt
            in
            let tex', te1' = io_T trace px_te in
            let m1 = m |> update is_rec' nx tex' |> update false n1 (if x = "_" then te1' else replace_VE te1' z x) |>
            (Opt.map (fun (nf, te2, tef') -> 
                fun m' -> m' |> update true nf tef' |> update false n (join_VE te1 te2))
              nf_t2_tf'_opt |> Opt.get_or_else (update false n te1)) 
            in
            let trace = if is_rec' && x = "_" then trace' else trace in
            let ec' = extract_ec tex' in
            let m1' = step e1 env1 trace ec' ae' assertion is_rec' m1 in
            (* let t1 = if x = "_" then find n1 m1' else replace_V (find n1 m1') x var in
            let prop_t = Table (construct_table cs (tx, t1)) in
            let px_t, t1 = prop_scope env1 env' x m1' prop_t t in
            let nf_t2_tf'_opt =
              Opt.map (fun (_, (nf, bf)) ->
                let envf, lf, fcs = get_vnode nf in
                let nf = construct_snode x nf in
                let tf = find nf m1' in
                let t2, tf' = prop_scope env' envf x m1' t tf in
                nf, t2, tf') f_nf_opt
            in
            let tx', t1' = io_T cs px_t in
            let m1' = m1' |> update nx tx' |> update n1 (if x = "_" then t1' else replace_V t1' z x) |>
            (Opt.map (fun (nf, t2, tf') -> fun m' -> m' |> update nf tf' |> update n (join_V t1 t2))
              nf_t2_tf'_opt |> Opt.get_or_else (update n t1)) in *)
            join_M m1' m'
          end
      ) te (m |> update false n te |> Hashtbl.copy)
  | TupleLst (tlst, l) ->
      (* (if !debug then
      begin
          Format.printf "\n<=== Tuple ===>\n";
          pr_exp true Format.std_formatter term;
          Format.printf "\n";
      end
      ); *)
    let te = find n m in 
    let te = match te with 
        | TEBot -> init_VE_wec (Bot) 
        | _ -> te 
    in
    if List.length tlst = 0 then
          let te' = 
            let cte = init_VE_v (init_V_c UnitLit) in
            join_VE te cte in
          m |> update false n te'
      else
          let tp, m', _ = List.fold_right (fun e (te, m, ec) -> 
              let m' = step e env trace ec ae assertion is_rec m in
              let ne = loc e |> construct_enode env |> construct_snode trace in
              let tee = find ne m' in
              let te' = add_tuple_item_V te tee in
              let ec' = extract_ec tee in
              te',  m', ec'
          ) tlst (Tuple [], m, ec) in
          let tep = TypeAndEff (tp, extract_eff te) in
          let _, te' = prop tep te in
          m' |> update false n te'
  | PatMat (e, patlst, l) ->
      (* (if !debug then
      begin
          Format.printf "\n<=== Pattern Match ===>\n";
          pr_exp true Format.std_formatter term;
          Format.printf "\n";
      end
      ); *)
      let ne = loc e |> construct_enode env |> construct_snode trace in
      (* let ex = get_var_name e in *)
      let m' = step e env trace ec ae assertion is_rec m in
      let tee = find ne m' in
      let ec' = extract_ec tee in
      if tee = TEBot || only_shape_V (extract_v tee) then m' 
      else
        let m'' = 
          List.fold_left 
            (fun m (Case (e1, e2)) -> 
              (* (if !debug then
                begin
                Format.printf "\n<=== Pattern ===>\n";
                pr_exp true Format.std_formatter e1;
                Format.printf "\n";
                pr_exp true Format.std_formatter e2;
                Format.printf "\n";
                end
              ); *)
              match e1 with
              | Const (c, l') ->
                let m1 = step e1 env trace ec' ae assertion is_rec m in
                let n1 = loc e1 |> construct_enode env |> construct_snode trace in
                let tee, te1 = find ne m1, find n1 m1 in
                let tee, te1 = alpha_rename_VEs tee te1 in
                let te1 = temap (id, fun _ -> extract_eff tee) te1 in
                if leq_VE tee te1 then m' else
                  let te1 = if is_List (extract_v tee) then
                              item_shape_VE tee te1
                            else te1 in
                  (* (if true then
                      begin
                      Format.printf "\n Pattern %s\n" (loc e1);
                      pr_exp true Format.std_formatter e1;
                      Format.printf "\n";
                      pr_value Format.std_formatter t1;
                      Format.printf "\n<<~~~~>> %s\n" (loc e);
                      pr_value Format.std_formatter te;
                      Format.printf "\n";
                      pr_value Format.std_formatter (join_V t1 te);
                      Format.printf "\n";
                      end
                      ); *)
                  let m1 = m1 |> update false n1 te1 in
                  let b =
                    sat_leq_VE te1 tee
                  in
                  let n1 = loc e1 |> construct_enode env |> construct_snode trace in
                  let n2 = loc e2 |> construct_enode env |> construct_snode trace in
                  (* (if true then
                      begin
                      Format.printf "\npattern ae: %b\n" b;
                      pr_value Format.std_formatter ae;
                      Format.printf "\n";
                      end
                      ); *)
                  let ae' = if not b then bot_relation_V Int else 
                              arrow_V (loc e) ae (extract_v (find n1 m1)) in
                  (* (if true then
                      begin
                      Format.printf "\nRES for ae:\n";
                      pr_value Format.std_formatter ae';
                      Format.printf "\n";
                      end
                      );  *)
                  let ec'' = extract_ec te1 in
                  let m2 = step e2 env trace ec'' ae' assertion is_rec m1 in
                  if not b then 
                    let te, te2 = find n m2, find n2 m2 in
                    let te2', te' = prop te2 te in
                    m2 |> update false n1 te1 |> update false n2 te2' |> update false n te'
                  else
                    let tee, te, te1, te2 = find ne m2, find n m2, find n1 m2, find n2 m2 in
                    let te1', tee' = let tee, te1 = alpha_rename_VEs tee te1 in 
                                      te1, join_VE te1 tee 
                    in
                    let te2', te' = prop te2 te in
                    m2 |> update false ne tee' |> update false n1 te1' 
                    |> update false n2 te2' |> update false n te'
              | Var (x, l') ->
                let n1 = trace |> construct_vnode env l' in
                let env1 = env |> VarMap.add x (n1, false) in
                let n1 = construct_snode trace n1 in
                let te1 = find n1 m in 
                let tee = find ne m in
                let _, te1' = prop tee te1 in
                let m1 = m |> update false n1 te1' in
                let ec' = extract_ec te1' in
                let m2 = step e2 env1 trace ec' ae assertion is_rec m1 in
                let n2 = loc e2 |> construct_enode env1 |> construct_snode trace in
                let te = find n m2 in 
                let te2 = find n2 m2 in
                let te2', te' = prop te2 te in
                m2 |> update false n2 te2' |> update false n te'
              | BinOp (Cons, el, er, l') ->
                (* (if true then
                    begin
                    Format.printf "\n<=== Prop then ===> %s\n" (loc e1);
                    pr_value Format.std_formatter t1;
                    Format.printf "\n<<~~~~>> %s\n" l;
                    pr_value Format.std_formatter (find n m1);
                    Format.printf "\n";
                    end
                    ); *)
                let ml, envl = list_var_item el trace m env ne true 0 in
                (* (if !debug then
                    begin
                    Format.printf "\n<=== Pattern binop ===>\n";
                    pr_exp true Format.std_formatter er;
                    Format.printf "\n";
                    end
                    ); *)
                let mr, envr = list_var_item er trace ml envl ne false 1 in
                let nr = loc er |> construct_enode envr |> construct_snode trace in
                let n2 = loc e2 |> construct_enode envr |> construct_snode trace in
                let n1 = l' |> construct_enode envr |> construct_snode trace in
                let m1 = step e1 envr trace ec ae assertion is_rec mr in
                let tee, te1 = find ne m1, find n1 m1 in
                let tee, te1 = alpha_rename_VEs tee te1 in
                let ae' =
                  let ae = arrow_V (loc e) ae (extract_v te1) in 
                  arrow_V (loc er) ae (extract_v (find nr m1))
                in
                let ec' = extract_ec te1 in
                let m2 = step e2 envr trace ec' ae' assertion is_rec m1 in
                let tee, te, te1, te2 = find ne m2, find n m2, find n1 m2, find n2 m2 in
                let te1', tee' =
                  let tee, te1 = alpha_rename_VEs tee te1 in 
                  prop te1 tee
                in
                let te2', te' = prop te2 te in
                m2 |> update false ne tee' |> update false n1 te1'
                |> update false n2 te2' |> update false n te'
              | TupleLst (termlst, l') ->
                let n1 = l' |> construct_enode env |> construct_snode trace in
                let te1 = 
                  let raw_te1 = find n1 m in
                  if is_tuple_VE raw_te1 then raw_te1
                  else let u' = List.init (List.length termlst) (fun _ -> TEBot) in 
                        init_VE_wec (Tuple u') 
                in
                let tee = find ne m in
                let tee, te1 = alpha_rename_VEs tee te1 in
                let tlst = get_tuple_list_VE te1 in
                let tllst = tee |> get_tuple_list_VE in
                let env', m', tlst', tllst' = 
                  List.fold_left2 (fun (env, m, li, llst) e (tei, telsti) -> 
                      match e with
                      | Var (x, l') -> 
                          let nx = construct_vnode env l' trace in
                          let env1 = env |> VarMap.add x (nx, false) in
                          let nx = construct_snode trace nx in
                          let tex = find nx m in
                          let tei', tex' = prop tei tex in
                          let telsti', tei'' = prop telsti tei in
                          let m' = m |> update false nx tex' in
                          env1, m', (join_VE tei' tei'') :: li, telsti' :: llst
                      | _ -> raise (Invalid_argument "Tuple only for variables now")
                    ) (env, m, [], []) termlst (zip_list tlst tllst) in
                let tlst', tllst' = List.rev tlst', List.rev tllst' in
                let te1', tee' = TypeAndEff (Tuple tlst', (extract_eff te1)), 
                                  TypeAndEff (Tuple tllst', (extract_eff tee)) 
                in
                let _, te1' = prop te1' te1 in
                let tee', _ = prop tee tee' in
                let m1 = m |> update false n1 te1' |> update false ne tee' in
                let ec' = extract_ec te1' in
                let m2 = step e2 env' trace ec' ae assertion is_rec m1 in
                let n2 = loc e2 |> construct_enode env' |> construct_snode trace in
                let te = find n m2 in 
                let te2 = find n2 m2 in
                let te2', te' = prop te2 te in
                m2 |> update false n2 te2' |> update false n te'
              | _ -> raise (Invalid_argument "Pattern should only be either constant, variable, or list cons")
            ) (update false ne tee m' |> Hashtbl.copy) patlst in
        m''
  | Event (e1, l) ->
    (if !debug then
      begin
          Format.printf "\n<=== EV ===>\n";
          pr_exp true Format.std_formatter term;
          Format.printf "\n";
      end);
      let n1 = loc e1 |> construct_enode env |> construct_snode trace in
      let m1 = step e1 env trace ec ae assertion is_rec m in
      let te1 = find n1 m1 in
      let penv = get_env_list env trace m1 in
      if te1 = TEBot then m1
      else
        let te' = begin match te1 with
                  | TypeAndEff ((Relation v), (Effect e)) -> 
                    TypeAndEff (Relation (Unit ()), Effect (AbstractEv.ev penv e v))
                  | _ -> te1
                  end
        in 
        m1 |> update false n (stren_VE te' ae)

    end

let step x1 x2 x3 x4 x5 x6 x7 = measure_call "step" (step x1 x2 x3 x4 x5 x6 x7)
          
(** Widening **)
let widening k (m1:exec_map_t) (m2:exec_map_t): exec_map_t =
  if k > !delay_wid then wid_M m1 m2 else join_M m1 m2

let widening k m = measure_call "widening" (widening k m)

    
(** Narrowing **)
let narrowing (m1:exec_map_t) (m2:exec_map_t): exec_map_t =
  meet_M m1 m2 

(** Fixpoint loop *)
let rec fix stage env e (k: int) (m:exec_map_t) (assertion:bool): string * exec_map_t =
  (if !out_put_level = 0 then
    begin
      let process = match stage with
      | Widening -> "Wid"
      | Narrowing -> "Nar"
      in
      Format.printf "\n%s step %d\n" process k;
      print_exec_map m;
    end);
  (* if k > 40 then exit 0 else *)
  let ae = VarMap.fold (fun var (n, b) ae ->
               let n = construct_snode (create_singleton_trace_loc "") n in
               let find n m = NodeMap.find_opt n m |> Opt.get_or_else TEBot in
               let te = find n m in
               if is_Relation (extract_v te) then
                 arrow_V var ae (extract_v te) else ae
             ) env (Relation (top_R Plus)) in
  let m_t = Hashtbl.copy m in
  let eff_i = AbstractEv.eff0 () in
  let pp_eff e = 
    let ppf = Format.std_formatter in
    if StateMap.is_empty e then Format.fprintf ppf "Empty\n" 
    else StateMap.bindings e 
         |> Format.pp_print_list ~pp_sep: (fun ppf () -> Format.printf ";@ ") pr_eff_binding ppf in
  (if !debug then (Format.printf "\nEff0: "; pp_eff eff_i));
  (* updated_nodes := UpdatedNodeMap.empty; *)
  let m' = step e env [] eff_i ae assertion false m_t in

  if k < 0 then if k = -1 then "", m' else fix stage env e (k+1) m' assertion else
  (* if k > 2 then Hashtbl.reset !pre_m;
  pre_m := m; *)
  (* Format.printf "\nFinish step %d\n" k;
  flush stdout; *)
  let m'' = if stage = Widening then widening k m m' else narrowing m m' in
  let comp = if stage = Widening then leq_M m'' m else leq_M m m'' in
  if comp then
      begin
      if assertion || !narrow then 
        let s = AssertionPosMap.fold (fun pos (i, j) s ->
            if i = j then try print_loc pos with 
            Input_Assert_failure s -> s else s) !sens "The input program is safe\n" in
        s, m 
      else 
        begin
        try fix stage env e k m true (* Final step to check assertions *)
        with Input_Assert_failure s -> s, m 
        end
      end
  else (fix stage env e (k+1) m'' assertion) (*Hashtbl.reset m; *)

      
(** Semantic function *)
let s e =
    (* (if !debug then
    begin
        Format.printf "%% Pre vals: %%\n";
        pr_pre_def_vars Format.std_formatter;
        Format.printf "\n\n";
    end); *)
    (* exit 0; *)
    (* let rec print_list = function 
    [] -> ()
    | e::l -> print_int e ; print_string " " ; print_list l in
    ThresholdsSetType.elements !thresholdsSet |> print_list; *)
    (* AbstractDomain.AbstractValue.licons_ref := AbstractDomain.AbstractValue.licons_earray [|"cur_v"|]; *)
  let envt, m0' = pref_M env0 (Hashtbl.copy m0) in
  let fv_e = fv e in
  let envt =
    VarMap.filter
      (fun x (n, _) ->
        if StringSet.mem x fv_e then true
        else
          let n = construct_snode (create_singleton_trace_loc "") n in
          (Hashtbl.remove m0' n; false)) envt
  in
  thresholdsSet := !thresholdsSet |> ThresholdsSetType.add 0 |> ThresholdsSetType.add 111 |> ThresholdsSetType.add 101
  |> ThresholdsSetType.add 2 |> ThresholdsSetType.add 4 |> ThresholdsSetType.add (-1) |> ThresholdsSetType.add (-2);
  (* pre_m := m0'; *)
    let check_str, m =
      let s1, m1 = (fix Widening envt e 0 m0' false) in
        if !narrow then
            begin
            narrow := false;
            (*let _, m1 = fix envt e (-10) m1 false in (* step^10(fixw) <= fixw *)*)
            let m1 = m1 |> reset in
            let s2, m2 = fix Narrowing envt e 0 m1 false in
            if eq_PM m0 m2 then s2, m2 
            else exit 0
            end
        else s1, m1
    in
    if !out_put_level = 1 then
        begin
        Format.printf "Final step \n";
        print_exec_map m;
        end;
    Format.printf "%s" check_str;
    m
