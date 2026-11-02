# Contexto do Compilador C‑ → MIPS‑Lite (para IA)

> **Aviso.** Versões anteriores deste arquivo descreviam o compilador legado:
> sem `$fp`, com locais em `$gp`, parâmetros lidos por offsets de `$sp`, um
> `GOTO main` no código intermediário e cinco testes (`teste2`, `teste`,
> `fatorial`, `gcd`, `sort`). Nada disso vale mais. As seções abaixo foram
> conferidas no código atual de `compilador/`. A referência do projeto (mapa
> de memória, MMIO, estado do SO) é [`../../so/docs/CONTEXT.md`](../../so/docs/CONTEXT.md);
> o uso do compilador está em [`../../compilador/README.md`](../../compilador/README.md).

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
  │  encoder.c → binário 32 bits (.mem, ou .txt com --txt)   │
  └─────────────────────────────────────────────────────────┘
```

**Comando do alvo padrão:** `./compilador --txt exemplos/<nome>.cms`

Esse comando regenera a ROM solta. `exemplos/` não é a imagem que o SO executa. Os binários da folha estão nos setores 20–29 de `processador/hd_image.txt`. `reset_tests.sh` sem flag regenera `exemplos/`. Com `--target=os-user` grava só esses setores e não mexe na pasta.

**Alvos.** A linha de comando aceita só o alvo padrão e `--target=os-user`; qualquer outro `--target=` é recusado. Não existe `os-kernel`.

- Padrão: o `.s` começa com `addi $sp,$zero,1015` e `j main`; `$gp` não é inicializado (fica no 0 do reset) e os saltos saem a partir de 0. O kernel `so.cms` é compilado neste alvo.
- `os-user`: o `.s` começa com `addi $gp,$zero,1536`, `addi $sp,$zero,1791` e `j main`. O encoder soma 3072 a cada `J` e `JAL`; `BEQ` e `BNE` continuam relativos. Binário acima de 256 palavras é recusado. Chamadas a `loadHD`, `loadROM`, `storeHD`, `lcdshow`, `lcdack`, `lcdsel` e `runat` são erro de semântica.

Nos dois alvos o encoder põe na palavra 0 um NOP cujo campo de 26 bits é o tamanho total do binário e garante um `HLT` na última palavra. O kernel em `so/src/so.txt` também tem esse cabeçalho (`NOP 1335`) e termina em `HLT`.

`loadHD`, `storeHD` e `loadROM` usam 4092–4095 e devolvem 0 quando `hd_status` é done e 1 quando é erro. `void runat(int)` não é `jal`: grava `$v0`, `$t0`–`$t9`, `$gp`, `$sp`, `$fp` e `$ra` em 1043–1057, faz `SW` do endereço em 4088 e restaura com `LW` a partir de `lw $v0,1043`. `$hi` e `$lo` ficam de fora.

**Saídas por programa:**

| Arquivo | Conteúdo |
|---------|----------|
| `<nome>.tm` | Quádruplas (código intermediário) |
| `<nome>.s` | Assembly MIPS-Lite |
| `<nome>.txt` | Binário 32 bits (texto, uma instrução/linha). Sem `--txt` o nome é `<nome>.mem` |

---

## 2. Estrutura do projeto

| Arquivo | Papel |
|---------|-------|
| `main.c` | CLI (`--txt`, `--target=os-user` e o caminho), orquestra análise e geração |
| `Scanner.l` | Flex: análise léxica |
| `Parser.y` | Bison: análise sintática, construção da AST |
| `globals.h` | Tipos compartilhados (TreeNode, tokens, flags) |
| `util.c/h` | Criação de nós, `printTree`, `aggScope` |
| `symtab.c/h` | Tabela de símbolos (hash), inserção/consulta, built-ins (`insertBuiltIns`) |
| `analyze.c/h` | Análise semântica: tabela, verificação de tipos, restrições do `os-user` |
| `cgen.c/h` | Geração de quádruplas a partir da AST |
| `asmgen.c/h` | Tradução de quádruplas → assembly MIPS-Lite |
| `encoder.c/h` | Montador: assembly → binário 32 bits |

---

## 3. Linguagem C‑

- **Tipos:** `int`, `void`. Variáveis escalares e vetores `int id[N]`.
- **Funções:** retorno `int` ou `void`; parâmetros `int id` ou `int id[]`.
- **Built-ins:** `input()` (retorna int), `output(int)`, `lcdshow(modo,id,pid)`, `lcdack()`, `lcdsel()`, `loadHD`, `storeHD`, `loadROM` (setor, endereço) e `void runat(int)`. Ficam na tabela global desde o início (`insertBuiltIns`, em `symtab.c`); declarar uma função com um desses nomes dá `Error 4: Invalid Declaration. Already declared.` O alvo `os-user` aceita `input` e `output` e recusa os demais.
- **Obrigatório:** função `main(void)`.

---

## 4. Geração de código intermediário (cgen.c)

### 4.1 Quádruplas emitidas

Cada quádrupla tem formato `(op, arg1, arg2, result)`. Temporários: `t0`, `t1`, ... Labels: `L0`, `L1`, ...

| Quádrupla | Significado |
|-----------|-------------|
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
| `HDLOAD`, `HDROM`, `HDSTORE setor addr tN` | `loadHD`, `loadROM`, `storeHD` |
| `LCD_MODE`, `LCD_ID`, `LCD_PID` | Os três argumentos de `lcdshow` |
| `LCDACK - - tN`, `LCDSEL - - tN` | `lcdack()`, `lcdsel()` |
| `RUNAT addr - -` | `runat(addr)` |
| `RET val - -` | Retorno de função |
| `HALT - - -` | Fim do programa |

### 4.2 Fluxo

1. `codeGen` percorre toda a AST (siblings) gerando quádruplas
2. Emite `HALT` ao final
3. Grava `.tm`, chama `asmGen` (→ `.s`) e `encodeAsm` (→ `.mem`)
4. Com `--txt`, `main.c` renomeia `.mem` para `.txt`

O salto inicial para `main` não é uma quádrupla: o `asmgen` o emite no prólogo do `.s`.

### 4.3 Exemplo: fatorial.tm

O `fatorial.cms` atual lê `n` com `input()`.

```
  0: (FUN, void, main, -)
  1: (ALLOC, n, main, -)
  2: (ALLOC, result, main, -)
  3: (CALL_I, -, -, t0)
  4: (STORE, t0, -, n)
  5: (ASSIGN, 1, -, t1)
  6: (STORE, t1, -, result)
  7: (LAB, L0, -, -)
  8: (LOAD, n, -, t2)
  9: (ASSIGN, 0, -, t3)
 10: (SLT, t3, t2, t4)         ← n > 0 implementado como 0 < n
 11: (IFF, t4, L1, -)
 12: (LOAD, result, -, t5)
 13: (LOAD, n, -, t6)
 14: (MUL, t5, t6, t7)
 15: (STORE, t7, -, result)
 16: (LOAD, n, -, t8)
 17: (ASSIGN, 1, -, t9)
 18: (SUB, t8, t9, t10)
 19: (STORE, t10, -, n)
 20: (GOTO, L0, -, -)
 21: (LAB, L1, -, -)
 22: (LOAD, result, -, t11)
 23: (PARAM, t11, -, -)
 24: (CALL_O, t11, -, -)
 25: (END, main, -, -)
 26: (HALT, -, -, -)
```

---

## 5. Geração de assembly (asmgen.c)

### 5.1 Convenções implementadas

**Registradores utilizados:**
- `$t0`–`$t9`: temporários (`tN` vira `$t(N % 10)`)
- `$gp`: base das variáveis globais
- `$sp`: ponteiro de pilha (argumentos de chamada, `$ra`, `$fp` salvos e locais)
- `$fp`: base do frame da função atual (parâmetros e locais)
- `$ra`: endereço de retorno
- `$v0`: valor de retorno de funções int
- `$zero`: registrador zero
- `$lo`: resultado de mult/div (parte baixa)
- `$hi`: resultado de mult/div (parte alta, não usado atualmente)

**Acesso a memória:**
- Variáveis globais: `memloc($gp)` — `memloc` vem da tabela de símbolos
- Parâmetros: `(1 + N - i)($fp)` para o parâmetro de índice `i` entre `N`; o último fica em `2($fp)`
- Locais: offsets negativos de `$fp`, na ordem das `ALLOC` da função
- Vetores globais: `addi base,$gp,memloc` + `add addr,base,index` + `lw/sw 0(addr)`
- Vetores locais: `addi base,$fp,off`; vetores parâmetro: `lw base,off($fp)`

**Convenção de chamada:**
1. Prólogo: `addi $sp,$sp,-1` + `sw $ra,0($sp)`, `addi $sp,$sp,-1` + `sw $fp,0($sp)`, `add $fp,$sp,$zero` e `addi $sp,$sp,-L` se houver `L` palavras de locais
2. Chamada (caller): push de argumentos com PARAM → `addi $sp,$sp,-1` + `sw arg,0($sp)`
3. `jal funcao`
4. Pop de argumentos: `addi $sp,$sp,N`
5. Retorno em `$v0`: `add result,$v0,$zero`
6. Epílogo: `add $sp,$fp,$zero`, `lw $fp,0($sp)`, `addi $sp,$sp,1`, `lw $ra,0($sp)`, `addi $sp,$sp,1`, `jr $ra`
7. `main` tem prólogo, mas termina com `hlt` em vez do epílogo

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
- `HDLOAD`/`HDROM`/`HDSTORE` → `sw` do setor em 4093, do endereço em 4094 e do comando (1, 2 ou 3) em 4092; laço enquanto `hd_status` (4095) == 1 (busy); resultado 0 se done, 1 se erro ou idle (bit 1 de `status + 3`)
- `LCD_*` → monta `{pid[3:0], id[9:0], modo[7:0]}` com `andi`/`sl`/`or` e grava em 4091
- `LCDACK`/`LCDSEL` → `lw` de 4091, `sr` de 27 ou 22 e `andi` com 1 ou 31
- `RUNAT` → 15 `sw` em 1043–1057, `sw` do endereço em 4088 e 15 `lw` de volta

**Controle de fluxo redundante:**
- END de funções com todos os caminhos terminando em RET: não emite epílogo duplicado (análise de alcançabilidade via `functionEndIsReachable`)
- END de funções void sem return explícito: emite epílogo implícito
- HALT suprimido se main já emitiu `hlt` via END/RET

### 5.2 Exemplo: fatorial.s (alvo padrão)

```asm
# Assembly gerado automaticamente
.text
.globl main
    addi $sp,$zero,1015
    j    main
main:
    addi $sp,$sp,-1
    sw   $ra,0($sp)
    addi $sp,$sp,-1
    sw   $fp,0($sp)
    add  $fp,$sp,$zero
    addi $sp,$sp,-2
    in   $t0
    sw   $t0,-1($fp)
    addi $t1,$zero,1
    sw   $t1,-2($fp)
L0:
    lw   $t2,-1($fp)
    addi $t3,$zero,0
    slt  $t4,$t3,$t2
    beq  $t4,$zero,L1
    lw   $t5,-2($fp)
    lw   $t6,-1($fp)
    mult $t5,$t6
    move $t7,$lo
    sw   $t7,-2($fp)
    lw   $t8,-1($fp)
    addi $t9,$zero,1
    sub  $t0,$t8,$t9
    sw   $t0,-1($fp)
    j    L0
L1:
    lw   $t1,-2($fp)
    addi $sp,$sp,-1
    sw   $t1,0($sp)
    out  $t1
    addi $sp,$sp,1
    # END main
    hlt
```

No alvo `os-user`, a primeira instrução vira `addi $gp,$zero,1536` seguida de `addi $sp,$zero,1791`, e o encoder soma 3072 a cada `J` e `JAL`. `BEQ` e `BNE` não recebem essa base.

---

## 6. Encoder / Montador (encoder.c)

### 6.1 Funcionamento

1. **Leitura:** cada linha do `.s` é interpretada uma vez. Labels (inclusive dot-labels `.L_eq_*`, `.L_ne_*`, `.L_hd_poll_*`) recebem o endereço da próxima instrução **mais 1**, porque a palavra 0 é reservada para o cabeçalho
2. **Montagem:** cada instrução vira uma palavra de 32 bits segundo o formato do ISA
3. **Cabeçalho e fim:** a palavra 0 é `NOP` com o tamanho total `N` no campo de 26 bits; se a última instrução do `.s` não for `hlt`, o encoder acrescenta um `HLT` na palavra `N-1`. `N` inclui o NOP e o HLT
4. **Alvo `os-user`:** soma 3072 a cada `J`/`JAL` e recusa `N` > 256
5. O binário é gravado num `.tmp` e renomeado no fim; se alguma instrução falhar, o binário não é escrito

### 6.2 Formatos implementados

**F1** (Register): `[opcode:6][RS:6][RT:6][RD:6][Shamt:8]` = 32 bits
- Usado por: ADD, SUB, MULT, DIV, AND, OR, SLT, SR, SL, JR

**F2** (Immediate): `[opcode:6][RD:6][RS:6][Imm:14]` = 32 bits
- Usado por: ADDI, SUBI, MULTI, DIVI, ANDI, ORI, LW, SW, BEQ, BNE, MOVE, NOT
- O imediato aceita −8192 a 8191 (`makeF2` aplica a máscara `0x3FFF`)

**F3** (Jump): `[opcode:6][Endereço:26]` = 32 bits
- Usado por: J, JAL, NOP, HLT

**FI** (I/O): `[opcode:6][Reg:6][zeros:20]` = 32 bits
- Usado por: IN, OUT

### 6.3 Tratamentos especiais

- **MULT/DIV** com 2 operandos: monta F1 com RS=op1, RT=op2, RD=0 (resultado em $hi/$lo)
- **JR** com 1 operando: monta F1 com RS=op1, RT=0, RD=0
- **SR/SL**: o terceiro operando é o shamt (0–31), não um registrador
- **BEQ/BNE** com label: offset relativo = `addr(label) - PC - 1`
- **J/JAL** com label: endereço absoluto do label (26 bits), já com o +1 do cabeçalho e, no `os-user`, +3072
- **J/JAL** com número: tratado como endereço do corpo sem cabeçalho e somado de 1 (compatibilidade com `.s` antigos)
- **LW/SW** com sintaxe `offset(base)`: parser separa imediato e registrador base
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
| `$fp` | 30 (011110) |
| `$ra` | 31 (011111) |
| `$lo` | 61 (111101) |
| `$hi` | 62 (111110) |

O encoder também aceita `$0`–`$63` e `$s0`–`$s7` (16–23), que o `asmgen` não emite.

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

Alvo padrão, arquivos de `compilador/exemplos/`. As instruções assembly não contam labels, diretivas nem comentários. O binário soma o NOP de tamanho; o `HLT` já vem do `.s`. No `os-user` cada binário tem uma palavra a mais (`addi $gp`), que é o tamanho gravado no HD.

| Programa | Quádruplas | Instruções assembly | Palavras do binário |
|----------|-----------|--------------------|--------------------|
| area_triangulo | 19 | 26 | 27 |
| busca_linear | 55 | 61 | 62 |
| fatorial | 27 | 32 | 33 |
| fibonacci | 38 | 39 | 40 |
| gcd | 41 | 72 | 73 |
| media | 37 | 44 | 45 |
| numero_primo | 48 | 55 | 56 |
| potencia | 33 | 36 | 37 |
| soma_digitos | 36 | 42 | 43 |
| sort | 129 | 160 | 161 |

---

## 8. Memória de dados — layout via $gp

O `$gp` é a base das globais. No alvo padrão ele permanece 0, o valor do reset. No alvo `os-user` o prólogo o coloca em 1536, início da janela 1536–1791. Cada variável global recebe um offset fixo (`memloc`) da tabela de símbolos, somado a essa base.

**Exemplo — sort.cms:**
```
$gp + 0..9  → vet[10] (vetor global, 10 palavras)
```

Locais e parâmetros ficam no frame da função (seção 9), não em `$gp`. A análise semântica ainda atribui um `memloc` a locais e funções; no `os-user` ela recusa programas que ocupem mais de 256 posições (`dataUsed > 256`, em `analyze.c`), mas essa conta não inclui a pilha.

---

## 9. Pilha ($sp) e frame ($fp) — layout durante chamada

```
Caller, após push de N argumentos:
    argN                    ← 0($sp)
    ...
    arg1                    ← (N-1)($sp)

Callee, após o prólogo (L palavras de locais):
    local L                 ← -L($fp) = 0($sp)
    ...
    local 1                 ← -1($fp)
    $fp do chamador         ← 0($fp)
    $ra                     ← 1($fp)
    argN (último param)     ← 2($fp)
    ...
    arg1 (primeiro param)   ← (1+N)($fp)
```

Como os parâmetros e locais são lidos por `$fp`, pushes de argumentos de subchamadas não mudam os offsets. Cada ativação recursiva tem frame próprio.

---

## 10. Limitações conhecidas

- **Temporários:** `tN` vira `$t(N % 10)` e nada salva `$t0`–`$t9` antes de um `jal`. Uma expressão que usa um temporário depois de uma chamada, como `n * fat(n-1)`, lê o valor sobrescrito pela chamada interna. O `so.cms` e os dez programas de `exemplos/` não são afetados.
- **Pilha no `os-user`:** globais e pilha dividem a janela 1536–1791 e o limite `dataUsed > 256` não considera a pilha. Um programa com muitos dados e chamadas profundas pode ter a pilha sobre as globais sem aviso.
