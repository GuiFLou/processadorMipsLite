# Contexto do Compilador C‑ → MIPS‑Lite (para IA)

Este documento descreve o compilador completo e funcionando. Todas as 20 issues foram corrigidas e validadas. Os 5 programas de teste (teste2, teste, fatorial, gcd, sort) passam em todas as 4 etapas (análise, intermediário, assembly, binário).

---

## 1. Pipeline do compilador

```
  .cms (fonte C-)
      │
      ▼
  ┌─────────────────────────────────────────────────────────┐
  │  FRONT-END (análise)                                     │
  │  Scanner.l (Flex) → tokens                               │
  │  Parser.y (Bison) → AST (árvore sintática)               │
  │  analyze.c → tabela de símbolos + verificação de tipos    │
  │  Saída: stdout (árvore, tabela, erros)                   │
  └─────────────────────────────────────────────────────────┘
      │
      ▼
  ┌─────────────────────────────────────────────────────────┐
  │  BACK-END (geração)                                      │
  │  cgen.c → quádruplas (.tm)                               │
  │  asmgen.c → assembly MIPS-Lite (.s)                      │
  │  encoder.c → binário 32 bits (.txt)                      │
  └─────────────────────────────────────────────────────────┘
```

**Comando:** `./compilador --txt exemplos/<nome>.cms`

**Saídas por programa:**

| Arquivo | Conteúdo |
|---------|----------|
| `<nome>.tm` | Quádruplas (código intermediário) |
| `<nome>.s` | Assembly MIPS-Lite |
| `<nome>.txt` | Binário 32 bits (texto, uma instrução/linha) |

---

## 2. Estrutura do projeto

| Arquivo | Papel |
|---------|-------|
| `main.c` | CLI (`--txt` + caminho), orquestra análise e geração |
| `Scanner.l` | Flex: análise léxica |
| `Parser.y` | Bison: análise sintática, construção da AST |
| `globals.h` | Tipos compartilhados (TreeNode, tokens, flags) |
| `util.c/h` | Criação de nós, `printTree`, `aggScope` |
| `symtab.c/h` | Tabela de símbolos (hash), inserção/consulta, built-ins |
| `analyze.c/h` | Análise semântica: tabela + verificação de tipos |
| `cgen.c/h` | Geração de quádruplas a partir da AST |
| `asmgen.c/h` | Tradução de quádruplas → assembly MIPS-Lite |
| `encoder.c/h` | Montador: assembly → binário 32 bits |

---

## 3. Linguagem C‑

- **Tipos:** `int`, `void`. Variáveis escalares e vetores `int id[N]`.
- **Funções:** retorno `int` ou `void`; parâmetros `int id` ou `int id[]`.
- **Built-ins:** `input()` (retorna int) e `output(int)`.
- **Obrigatório:** função `main(void)`.

---

## 4. Geração de código intermediário (cgen.c)

### 4.1 Quádruplas emitidas

Cada quádrupla tem formato `(op, arg1, arg2, result)`. Temporários: `t0`, `t1`, ... Labels: `L0`, `L1`, ...

| Quádrupla | Significado |
|-----------|-------------|
| `GOTO main - -` | Salto inicial para main |
| `FUN tipo nome -` | Início de função |
| `ARG tipo nome funcao` | Parâmetro formal |
| `END nome - -` | Fim de função |
| `ALLOC nome escopo -` | Variável escalar |
| `ALLOC nome escopo tamanho` | Vetor (ex: `ALLOC vet global 10`) |
| `ASSIGN lit - tN` | Carrega literal em temporário |
| `LOAD var - tN` | Carrega variável em temporário |
| `STORE tN - var` | Armazena temporário em variável |
| `LOADV arr idx tN` | Carrega `arr[idx]` em temporário |
| `STOREV val idx arr` | Armazena `val` em `arr[idx]` |
| `ADDR arr - tN` | Endereço base do vetor (para passagem por referência) |
| `ADD a b dst` | Soma |
| `SUB a b dst` | Subtração |
| `MUL a b dst` | Multiplicação |
| `DIV a b dst` | Divisão (quociente) |
| `SLT a b dst` | Menor que (`<`) |
| `EQ a b dst` | Igual (`==`) |
| `NEQ a b dst` | Diferente (`!=`) |
| `IFF cond label -` | Branch se falso |
| `GOTO label - -` | Salto incondicional |
| `LAB label - -` | Definição de label |
| `PARAM arg - -` | Empilha argumento para chamada |
| `CALL nome nargs tN` | Chamada de função (resultado em tN) |
| `CALL_I - - tN` | Chamada de `input()` |
| `CALL_O val - -` | Chamada de `output()` (precedido de PARAM) |
| `RET val - -` | Retorno de função |
| `HALT - - -` | Fim do programa |

### 4.2 Fluxo

1. `codeGen` emite `GOTO main` no início
2. Percorre toda a AST (siblings) gerando quádruplas
3. Emite `HALT` ao final
4. Grava `.tm`, chama `asmGen` (→ `.s`), chama `encodeAsm` (→ `.txt`)

### 4.3 Exemplo: fatorial.tm

```
  0: (GOTO, main, -, -)
  1: (FUN, void, main, -)
  2: (ALLOC, n, main, -)
  3: (ALLOC, result, main, -)
  4: (ASSIGN, 5, -, t0)
  5: (STORE, t0, -, n)
  6: (ASSIGN, 1, -, t1)
  7: (STORE, t1, -, result)
  8: (LAB, L0, -, -)
  9: (LOAD, n, -, t2)
 10: (ASSIGN, 0, -, t3)
 11: (SLT, t3, t2, t4)         ← n > 0 implementado como 0 < n
 12: (IFF, t4, L1, -)
 13: (LOAD, result, -, t5)
 14: (LOAD, n, -, t6)
 15: (MUL, t5, t6, t7)
 16: (STORE, t7, -, result)
 17: (LOAD, n, -, t8)
 18: (ASSIGN, 1, -, t9)
 19: (SUB, t8, t9, t10)
 20: (STORE, t10, -, n)
 21: (GOTO, L0, -, -)
 22: (LAB, L1, -, -)
 23: (LOAD, result, -, t11)
 24: (PARAM, t11, -, -)
 25: (CALL_O, t11, -, -)
 26: (END, main, -, -)
 27: (HALT, -, -, -)
```

---

## 5. Geração de assembly (asmgen.c)

### 5.1 Convenções implementadas

**Registradores utilizados:**
- `$t0`–`$t9`: temporários (mapeados circularmente de `tN` do intermediário)
- `$gp`: base da memória de dados (variáveis globais e locais não-parâmetro)
- `$sp`: ponteiro de pilha (parâmetros, $ra, argumentos de chamada)
- `$ra`: endereço de retorno
- `$v0`: valor de retorno de funções int
- `$zero`: registrador zero
- `$lo`: resultado de mult/div (parte baixa)
- `$hi`: resultado de mult/div (parte alta, não usado atualmente)

**Acesso a memória:**
- Variáveis globais e locais: `offset($gp)` — offset = `memloc` da tabela de símbolos
- Parâmetros de função: `offset($sp)` — offset calculado dinamicamente com `stackDelta`
- Vetores globais: `addi base,$gp,memloc` + `add addr,base,index` + `lw/sw 0(addr)`
- Vetores parâmetro: `lw base,offset($sp)` + `add addr,base,index` + `lw/sw 0(addr)`

**Convenção de chamada:**
1. Prologue da função: `addi $sp,$sp,-1` + `sw $ra,0($sp)`
2. Chamada (caller): push de argumentos com PARAM → `addi $sp,-1` + `sw arg,0($sp)`
3. `jal funcao`
4. Pop de argumentos: `addi $sp,$sp,N`
5. Retorno em `$v0`: `add result,$v0,$zero`
6. Epilogue: `lw $ra,0($sp)` + `addi $sp,$sp,1` + `jr $ra`
7. main termina com `hlt` em vez de `jr $ra`

**Operações especiais:**
- `MUL` → `mult r1,r2` + `move rd,$lo` (2 operandos, resultado em $lo)
- `DIV` → `div r1,r2` + `move rd,$lo` (quociente em $lo)
- `EQ` → `sub` + `beq` + dot-labels (`.L_eq_N`) para resultado 0/1
- `NEQ` → `sub` + `beq` + dot-labels (`.L_ne_N`) para resultado 1/0
- `SLT` → `slt rd,r1,r2` (diretamente)
- `>` → `slt` com operandos invertidos
- `IFF` → `beq cond,$zero,label`
- `GOTO` → `j label`
- `CALL_I` → `in rd`
- `CALL_O` → `out r1` + pop do argumento empilhado por PARAM

**Controle de fluxo redundante:**
- END de funções com todos os caminhos terminando em RET: não emite epilogue duplicado (análise de alcançabilidade via `functionEndIsReachable`)
- END de funções void sem return explícito: emite epilogue implícito
- HALT suprimido se main já emitiu `hlt` via END/RET

### 5.2 Exemplo: fatorial.s

```asm
# Assembly gerado automaticamente
.text
.globl main
    j    main
main:
    addi $sp,$sp,-1
    sw   $ra,0($sp)
    addi $t0,$zero,5
    sw   $t0,1($gp)
    addi $t1,$zero,1
    sw   $t1,2($gp)
L0:
    lw   $t2,1($gp)
    addi $t3,$zero,0
    slt  $t4,$t3,$t2
    beq  $t4,$zero,L1
    lw   $t5,2($gp)
    lw   $t6,1($gp)
    mult $t5,$t6
    move $t7,$lo
    sw   $t7,2($gp)
    lw   $t8,1($gp)
    addi $t9,$zero,1
    sub  $t0,$t8,$t9
    sw   $t0,1($gp)
    j    L0
L1:
    lw   $t1,2($gp)
    addi $sp,$sp,-1
    sw   $t1,0($sp)
    out  $t1
    addi $sp,$sp,1
    # END main
    hlt
```

---

## 6. Encoder / Montador (encoder.c)

### 6.1 Funcionamento

Duas passagens sobre o `.s`:
1. **1ª passagem:** coleta labels (incluindo dot-labels `.L_eq_*`, `.L_ne_*`) e seus endereços
2. **2ª passagem:** monta cada instrução em 32 bits segundo o formato do ISA

### 6.2 Formatos implementados

**F1** (Register): `[opcode:6][RS:6][RT:6][RD:6][Shamt:8]` = 32 bits
- Usado por: ADD, SUB, MULT, DIV, AND, OR, SLT, SR, SL, JR

**F2** (Immediate): `[opcode:6][RD:6][RS:6][Imm:14]` = 32 bits
- Usado por: ADDI, SUBI, LW, SW, BEQ, BNE, MOVE, NOT

**F3** (Jump): `[opcode:6][Endereço:26]` = 32 bits
- Usado por: J, JAL, NOP, HLT

**FI** (I/O): `[opcode:6][Reg:6][zeros:20]` = 32 bits
- Usado por: IN, OUT

### 6.3 Tratamentos especiais

- **MULT/DIV** com 2 operandos: monta F1 com RS=op1, RT=op2, RD=0 (resultado em $hi/$lo)
- **JR** com 1 operando: monta F1 com RS=op1, RT=0, RD=0
- **BEQ/BNE** com label: offset relativo = `addr(label) - PC - 1`
- **J/JAL** com label: endereço absoluto do label (26 bits)
- **LW/SW** com sintaxe `offset(base)`: parser separa imediato e registrador base
- **Dot-labels** (`.L_eq_*`, `.L_ne_*`): reconhecidos e resolvidos normalmente
- **Diretivas** (`.text`, `.globl`): ignoradas (não contam como instrução)
- **Comentários** (`#`): ignorados

### 6.4 Mapeamento de registradores

| Registrador | Número (6 bits) |
|-------------|-----------------|
| `$zero` | 0 (000000) |
| `$v0` | 2 (000010) |
| `$t0`–`$t9` | 8–17 (001000–010001) |
| `$gp` | 28 (011100) |
| `$sp` | 29 (011101) |
| `$ra` | 31 (011111) |
| `$lo` | 61 (111101) |
| `$hi` | 62 (111110) |

### 6.5 Tabela de opcodes

| Instrução | Opcode | Formato | Instrução | Opcode | Formato |
|-----------|--------|---------|-----------|--------|---------|
| ADD | 000000 | F1 | Or | 001010 | F1 |
| AddI | 000001 | F2 | OrI | 001011 | F2 |
| Sub | 000010 | F1 | Not | 001100 | F2 |
| SubI | 000011 | F2 | Sr | 001101 | F1 |
| Mult | 000100 | F1 | Sl | 001110 | F1 |
| Multi | 000101 | F2 | Load/lw | 001111 | F2 |
| Div | 000110 | F1 | Store/sw | 010000 | F2 |
| Divi | 000111 | F2 | Jump/j | 010001 | F3 |
| And | 001000 | F1 | JumpR/jr | 010010 | F1 |
| AndI | 001001 | F2 | Jal | 010011 | F3 |
| beq | 010100 | F2 | move | 010110 | F2 |
| bne | 010101 | F2 | nop | 010111 | F3 |
| hlt | 011000 | F3 | slt | 011001 | F1 |
| In | 011010 | FI | Out | 011011 | FI |

---

## 7. Tamanho dos programas gerados

| Programa | Quádruplas | Instruções assembly | Instruções binárias |
|----------|-----------|--------------------|--------------------|
| teste2.cms | 15 | 17 | 15 |
| teste.cms | 15 | 17 | 15 |
| fatorial.cms | 28 | 31 | 27 |
| gcd.cms | 42 | 66 | 58 |
| sort.cms | 130 | 157 | 141 |

---

## 8. Memória de dados — layout via $gp

O `$gp` aponta para o início da memória de dados. Cada variável global ou local (exceto parâmetros) recebe um offset fixo (`memloc`) da tabela de símbolos.

**Exemplo — sort.cms:**
```
$gp + 0..9  → vet[10] (vetor global, 10 palavras)
$gp + 10    → (início das variáveis de minloc, mas acessadas durante execução de minloc)
...
$gp + 25    → i de main
```

Parâmetros de função ficam na pilha (`$sp`), não em `$gp`.

---

## 9. Pilha ($sp) — layout durante chamada

```
Antes da chamada:
    [...conteúdo anterior...]
    $ra do chamador ← 0($sp)

Após push de N argumentos:
    argN                    ← 0($sp)
    argN-1                  ← 1($sp)
    ...
    arg1                    ← (N-1)($sp)
    $ra do chamador         ← N($sp)

Dentro do callee (após prologue salvar $ra):
    $ra do callee           ← 0($sp)
    argN (último param)     ← 1($sp)
    argN-1                  ← 2($sp)
    ...
    arg1 (primeiro param)   ← N($sp)
    $ra do chamador         ← (N+1)($sp)
```

O `stackDelta` em `asmgen.c` rastreia quantas palavras o callee empilhou desde a entrada, ajustando automaticamente os offsets de parâmetros quando argumentos de subchamadas são empilhados.
