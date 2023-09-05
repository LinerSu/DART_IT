%{
(* header *)
open Syntax
open EffectAutomataSyntax
open Lexing


let convert_var_name_apron_not_support s = 
  if String.contains s '\'' then
    let lst = String.split_on_char '\'' s in
    let lst' = List.fold_right (fun s rlst -> 
      if String.length s = 0 then List.append rlst ["_pm"]
      else List.append rlst [s; "_pm_"]) lst [] in
    let restr = 
      let tempstr = String.concat "" (List.rev lst') in
      String.sub tempstr 4 (String.length tempstr - 4)
    in
    restr
  else s

%}

(* declarations *)
%token <string> IDENT
%token <int> INTCONST
%token <bool> BOOLCONST
%token LPAREN RPAREN LBRACE RBRACE
%token SEMI COMMA LSQBR RSQBR  
%token IF THEN ELSE FUN
%token PLUS MINUS TIMES DIV MOD 
%token EQ NE LE LT GE GT
%token AND OR
%token ARROW CONS
%token BEGIN END
%token EMPTYLIST
%token QSET                                  (* QSet *)
%token DELTA                                 (* delta *)
%token ASSERT                                (* assert *)
%token INICFG                                (* IniCfg *)
%token EOF

%nonassoc THEN
%nonassoc ELSE
%right CONS
%left PLUS MINUS
%left TIMES DIV MOD

%start <EffectAutomataSyntax.aut_spec> top
%%

/* production rules */
top:
  | LBRACE fields=aut_fields RBRACE EOF { effect_aut_spec fields }
  
aut_fields: 
  | qs=qset SEMI df=delta_fn SEMI a=asst SEMI c0=config0 { (qs, df, a, c0) }

qset:
  | QSET EQ LSQBR qs=separated_nonempty_list(SEMI, q=INTCONST { q }) RSQBR 
      { List.map (fun q -> Q q) qs }

delta_fn:
  | DELTA EQ FUN x=var LPAREN q=var COMMA acc=var RPAREN ARROW e=exp 
      { delta_fn x (q, acc) e }

asst:
  | ASSERT EQ FUN LPAREN q=var COMMA acc=var RPAREN ARROW e=bool_exp { effect_assert (q, acc) e }

config0:
  | INICFG EQ e=tuple_exp { initial_cfg e }

exp:
  | c=const_exp { c }
  | x=var { x }
  | EMPTYLIST { Const (IntList [], "") }
  | e=if_exp { e } 
  | e=tuple_exp { e }
  | e=binary_exp { e }
  | BEGIN e=exp END { e } 

var:
  | x=IDENT
      { let res_str = convert_var_name_apron_not_support x in 
        Var (res_str, "") }

const_exp:
  | i=INTCONST { Const (Integer i, "") }
  | b=BOOLCONST { Const (Boolean b, "") }

tuple_exp:
  | LPAREN es=separated_nonempty_list(COMMA, e=exp { e }) RPAREN { TupleLst (es, "") }

%inline if_exp:
  | IF LPAREN be=bool_exp RPAREN THEN e1=exp ELSE e2=exp 
      { let loc = None |> construct_asst in
        Ite (be, e1, e2, "", loc) }
  | IF LPAREN be=bool_exp RPAREN THEN e1=exp 
      { let loc = None |> construct_asst in
        let else_term = Const (UnitLit, "") in
        Ite (be, e1, else_term, "", loc) }

bool_exp:
  | e=comp_exp { e }
  | e1=comp_exp bop=bool_op e2=bool_exp { BinOp (bop, e1, e2, "") }

bool_op:
  | AND { And }
  | OR { Or }

comp_exp:
  | e1=exp op=comp_op e2=exp { BinOp (op, e1, e2, "") } 

%inline comp_op:
  | EQ { Eq }
  | NE { Ne }
  | LE { Le }
  | LT { Lt }
  | GE { Ge }
  | GT { Gt }

binary_exp:
  | e1=exp op=bop e2=exp { BinOp (op, e1, e2, "") }

%inline bop:
  | PLUS { Plus }
  | MINUS { Minus }
  | TIMES { Mult }
  | MOD { Mod }
  | DIV { Div }
  | CONS { Cons }


