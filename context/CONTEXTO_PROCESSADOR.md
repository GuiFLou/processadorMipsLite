# Contexto do Processador MIPS‑Lite — Referência para implementação em Verilog

Este documento define **tudo que o processador precisa implementar** para executar corretamente os binários gerados pelo compilador C‑. Ele é a referência autoritativa para a implementação/revisão do processador em Verilog.

O compilador está completo e validado. Os binários de todos os 5 programas de teste foram decodificados manualmente e estão 100% corretos.

---

## 1. Arquitetura geral

| Aspecto | Especificação |
|---------|---------------|
| Tipo | RISC monociclo |
| Arquitetura de memória | Harvard (instrução e dados separados) |
| Tamanho da instrução | 32 bits fixo |
| Formatos de instrução | 3 (F1, F2, F3/FI) |
| Banco de registradores | 64 registradores × 32 bits |
| Identificador de registrador | 6 bits |
| Memória de instruções | 1024 palavras × 32 bits |
| Memória de dados | 1024 palavras × 32 bits |
| Endereçamento | Por palavra (PC avança de 1 em 1) |
| PC inicial | 0 |

**IMPORTANTE — Endereçamento por palavra:**
O PC avança como `PC ← PC + 1` (não `PC + 4`). Cada posição da memória de instrução contém uma instrução completa de 32 bits. Labels e endereços de salto são índices de linha (word address), não byte address.

---

## 2. Formatos de instrução

### F1 — Register (operações entre registradores)

```
  31    26 25    20 19    14 13     8 7      0
 ┌────────┬────────┬────────┬────────┬────────┐
 │ Opcode │   RS   │   RT   │   RD   │ Shamt  │
 │ 6 bits │ 6 bits │ 6 bits │ 6 bits │ 8 bits │
 └────────┴────────┴────────┴────────┴────────┘
```

- **RS**: primeiro operando fonte (registrador)
- **RT**: segundo operando fonte (registrador)
- **RD**: registrador destino
- **Shamt**: shift amount (usado por Sr/Sl; zero para demais)

**Semântica:** `RD ← RS op RT`

**Exceção MULT/DIV:** RD é 0 (ignorado); resultado vai para $hi e $lo.
**Exceção JR:** RS contém o endereço de salto; RT e RD são 0.

### F2 — Immediate (operações com imediato, memória, branches)

```
  31    26 25    20 19    14 13              0
 ┌────────┬────────┬────────┬────────────────┐
 │ Opcode │   RD   │   RS   │   Imediato     │
 │ 6 bits │ 6 bits │ 6 bits │   14 bits      │
 └────────┴────────┴────────┴────────────────┘
```

- **RD**: registrador destino (ou fonte em sw/beq/bne)
- **RS**: registrador fonte (ou base em lw/sw)
- **Imediato**: valor de 14 bits com extensão de sinal

**Para LW:** `RD ← MEM[RS + signext(Imm)]`
**Para SW:** `MEM[RS + signext(Imm)] ← RD`
**Para BEQ:** se `RD == RS`, então `PC ← PC + 1 + signext(Imm)`
**Para BNE:** se `RD != RS`, então `PC ← PC + 1 + signext(Imm)`
**Para ADDI:** `RD ← RS + signext(Imm)`
**Para MOVE:** `RD ← RS` (Imm ignorado)

### F3 — Jump (saltos incondicionais, controle)

```
  31    26 25                             0
 ┌────────┬──────────────────────────────┐
 │ Opcode │         Endereço             │
 │ 6 bits │         26 bits              │
 └────────┴──────────────────────────────┘
```

- **Endereço**: endereço absoluto de destino (word address)

**Para J:** `PC ← Endereço`
**Para JAL:** `$ra ← PC + 1`, depois `PC ← Endereço`
**Para HLT:** para a execução (PC não avança mais)

### FI — I/O (entrada/saída)

```
  31    26 25    20 19                    0
 ┌────────┬────────┬──────────────────────┐
 │ Opcode │  Reg   │       zeros          │
 │ 6 bits │ 6 bits │      20 bits         │
 └────────┴────────┴──────────────────────┘
```

- **Para IN:** `Reg ← valor dos switches de entrada`
- **Para OUT:** `display ← Reg`

---

## 3. Conjunto completo de instruções (ISA)

### 3.1 Tabela de opcodes

| # | Instrução | Opcode (bin) | Opcode (dec) | Formato | Operação |
|---|-----------|-------------|-------------|---------|----------|
| 0 | ADD | 000000 | 0 | F1 | RD ← RS + RT |
| 1 | ADDI | 000001 | 1 | F2 | RD ← RS + signext(Imm) |
| 2 | SUB | 000010 | 2 | F1 | RD ← RS - RT |
| 3 | SUBI | 000011 | 3 | F2 | RD ← RS - signext(Imm) |
| 4 | MULT | 000100 | 4 | F1 | {Hi,Lo} ← RS × RT |
| 5 | MULTI | 000101 | 5 | F2 | {Hi,Lo} ← RS × signext(Imm) |
| 6 | DIV | 000110 | 6 | F1 | Lo ← RS / RT ; Hi ← RS % RT |
| 7 | DIVI | 000111 | 7 | F2 | Lo ← RS / signext(Imm) ; Hi ← RS % signext(Imm) |
| 8 | AND | 001000 | 8 | F1 | RD ← RS & RT |
| 9 | ANDI | 001001 | 9 | F2 | RD ← RS & zeroext(Imm) |
| 10 | OR | 001010 | 10 | F1 | RD ← RS \| RT |
| 11 | ORI | 001011 | 11 | F2 | RD ← RS \| zeroext(Imm) |
| 12 | NOT | 001100 | 12 | F2 | RD ← ~RS |
| 13 | SR | 001101 | 13 | F1 | RD ← RS >> Shamt |
| 14 | SL | 001110 | 14 | F1 | RD ← RS << Shamt |
| 15 | LW | 001111 | 15 | F2 | RD ← MEM[RS + signext(Imm)] |
| 16 | SW | 010000 | 16 | F2 | MEM[RS + signext(Imm)] ← RD |
| 17 | J | 010001 | 17 | F3 | PC ← Addr |
| 18 | JR | 010010 | 18 | F1 | PC ← RS |
| 19 | JAL | 010011 | 19 | F3 | $ra ← PC+1 ; PC ← Addr |
| 20 | BEQ | 010100 | 20 | F2 | se RD == RS: PC ← PC+1+signext(Imm) |
| 21 | BNE | 010101 | 21 | F2 | se RD != RS: PC ← PC+1+signext(Imm) |
| 22 | MOVE | 010110 | 22 | F2 | RD ← RS |
| 23 | NOP | 010111 | 23 | F3 | nenhuma operação |
| 24 | HLT | 011000 | 24 | F3 | para execução |
| 25 | SLT | 011001 | 25 | F1 | RD ← (RS < RT) ? 1 : 0 |
| 26 | IN | 011010 | 26 | FI | Reg ← input |
| 27 | OUT | 011011 | 27 | FI | output ← Reg |

### 3.2 Instruções usadas pelos programas de teste

| Instrução | Usada por |
|-----------|-----------|
| ADD | todos |
| ADDI | todos |
| SUB | fatorial, gcd, sort |
| MULT | fatorial, gcd |
| DIV | gcd |
| LW | todos |
| SW | todos |
| J | todos |
| JR | gcd, sort |
| JAL | gcd, sort |
| BEQ | fatorial, gcd, sort |
| MOVE | fatorial, gcd |
| SLT | fatorial, sort |
| HLT | todos |
| IN | teste, gcd, sort |
| OUT | todos |

Instruções **não usadas** pelos testes atuais: SUBI, MULTI, DIVI, AND, ANDI, OR, ORI, NOT, SR, SL, BNE, NOP. Estas devem ser implementadas mas não são críticas para a validação inicial.

---

## 4. Registradores

### 4.1 Banco de registradores

O banco tem **64 registradores** de 32 bits. O compilador utiliza os seguintes:

| Nome | Número | Binário (6 bits) | Uso |
|------|--------|------------------|-----|
| `$zero` | 0 | 000000 | Sempre zero (hardwired) |
| `$v0` | 2 | 000010 | Valor de retorno de funções |
| `$t0` | 8 | 001000 | Temporário |
| `$t1` | 9 | 001001 | Temporário |
| `$t2` | 10 | 001010 | Temporário |
| `$t3` | 11 | 001011 | Temporário |
| `$t4` | 12 | 001100 | Temporário |
| `$t5` | 13 | 001101 | Temporário |
| `$t6` | 14 | 001110 | Temporário |
| `$t7` | 15 | 001111 | Temporário |
| `$t8` | 16 | 010000 | Temporário |
| `$t9` | 17 | 010001 | Temporário |
| `$gp` | 28 | 011100 | Ponteiro global (base da memória de dados) |
| `$sp` | 29 | 011101 | Ponteiro de pilha |
| `$ra` | 31 | 011111 | Endereço de retorno (escrito por JAL) |
| `$lo` | 61 | 111101 | Resultado baixo de MULT/DIV |
| `$hi` | 62 | 111110 | Resultado alto de MULT/DIV |

### 4.2 Requisitos do hardware

1. **$zero** deve sempre ler 0, escritas são ignoradas
2. **$lo e $hi** devem ser escritos por MULT e DIV automaticamente
3. **$lo e $hi** devem ser lidos por MOVE (`move $tN,$lo` → `MOVE RD=$tN, RS=$lo`)
4. **$ra** deve ser escrito por JAL com `PC + 1`
5. **$gp** deve ser inicializado com o endereço base da memória de dados (tipicamente 0)
6. **$sp** deve ser inicializado com o topo da pilha (ex: 1023 para pilha crescendo para baixo)

---

## 5. Memória

### 5.1 Memória de instruções (ROM)

- 1024 palavras × 32 bits
- Endereçada pelo PC (word address, 0 a 1023)
- Carregada com o conteúdo do `.txt` (uma linha = uma instrução)
- Somente leitura durante execução

### 5.2 Memória de dados (RAM)

- 1024 palavras × 32 bits
- Endereçada por `RS + signext(Imm)` nas instruções LW/SW
- A região baixa (a partir do endereço 0, apontada por `$gp`) contém variáveis globais
- A região alta (a partir do endereço apontado por `$sp`) contém a pilha (cresce para baixo)

### 5.3 Layout da memória de dados (exemplo: sort.cms)

```
Endereço 0..9:   vet[10] (vetor global)
Endereço 10..13: variáveis de minloc (i, x, k, etc.)
Endereço 14..17: ...
...
Endereço 25:     variável i de main
```

A pilha começa no topo (ex: $sp = 1023) e cresce para baixo com `addi $sp,$sp,-1`.

---

## 6. Cálculo de endereços de salto e branch

### 6.1 Jump (J) e JAL

Formato F3. O campo Endereço (26 bits) contém o **endereço absoluto** (word address) do destino.

```
PC ← Endereço[25:0]
```

**Exemplo real (gcd.txt, addr 0):**
```
01000100000000000000000000100110
│opcode│        endereço        │
│010001│00000000000000000000100110│ = J para endereço 38 (main)
```

**Exemplo real (gcd.txt, addr 31):**
```
01001100000000000000000000000001
│010011│00000000000000000000000001│ = JAL para endereço 1 (gcd)
```

### 6.2 Branch (BEQ/BNE)

Formato F2. O campo Imediato (14 bits, com sinal) contém o **offset relativo** ao PC+1.

```
se condição verdadeira:
    PC ← PC + 1 + signext(Imm[13:0])
senão:
    PC ← PC + 1
```

**ATENÇÃO:** O offset é calculado como `addr_destino - addr_branch - 1`. O processador soma `signext(Imm)` a `PC + 1` (que é o endereço da próxima instrução sequencial).

**Exemplo real (fatorial.txt, addr 10):**
```
01010000110000000000000000001010
│010100│001100│000000│00000000001010│
│ BEQ  │$t4   │$zero │ Imm = 10    │
```
Destino: `PC + 1 + 10 = 10 + 1 + 10 = 21` (label L1) ✅

**Exemplo real (gcd.txt, addr 6):**
```
01010000101000000000000000000010
│010100│001010│000000│00000000000010│
│ BEQ  │$t2   │$zero │ Imm = 2     │
```
Destino: `6 + 1 + 2 = 9` (label .L_eq_0) ✅

**Exemplo real (sort.txt, addr 52):**
```
01010000110100000000000000100100
│010100│001101│000000│00000000100100│
│ BEQ  │$t5   │$zero │ Imm = 36    │
```
Destino: `52 + 1 + 36 = 89` (label L5) ✅

### 6.3 JR (Jump Register)

Formato F1. O campo RS contém o registrador com o endereço de destino.

```
PC ← Reg[RS]
```

**Exemplo real (gcd.txt, addr 15):**
```
01001001111100000000000000000000
│010010│011111│000000│000000│00000000│
│  JR  │ $ra  │  0   │  0   │   0    │
```

---

## 7. Instruções MULT e DIV — Registradores especiais

### 7.1 MULT

Formato F1. Multiplica RS × RT e armazena o resultado de 64 bits em {$hi, $lo}.

```
{$hi, $lo} ← RS × RT
```

O campo RD é **0** (ignorado pelo hardware). O compilador obtém o resultado com `move $tN,$lo` logo após.

**Exemplo real (fatorial.txt, addr 13):**
```
00010000110100111000000000000000
│000100│001101│001110│000000│00000000│
│ MULT │$t5=13│$t6=14│ RD=0 │ sh=0   │
```
Seguido por (addr 14): `move $t7,$lo`
```
01011000111111110100000000000000
│010110│001111│111101│00000000000000│
│ MOVE │$t7=15│$lo=61│    Imm=0    │
```

### 7.2 DIV

Formato F1. Divide RS / RT. Quociente em $lo, resto em $hi.

```
$lo ← RS / RT (quociente)
$hi ← RS % RT (resto)
```

Divisão por zero segue uma convenção definida pelo hardware: se `RT == 0`,
`$lo` recebe `32'hFFFF_FFFF` e `$hi` recebe o valor original de `RS`.

O campo RD é **0** (ignorado pelo hardware). O compilador obtém o quociente com `move $tN,$lo`.

**Exemplo real (gcd.txt, addr 23):**
```
00011000111000111100000000000000
│000110│001110│001111│000000│00000000│
│ DIV  │$t6=14│$t7=15│ RD=0 │ sh=0   │
```
Seguido por: `move $t8,$lo`

### 7.3 Requisitos do hardware para MULT/DIV

1. MULT/DIV devem escrever em $hi e $lo (registradores 62 e 61)
2. MOVE deve ser capaz de ler $hi e $lo como RS (campo RS do F2)
3. O compilador **nunca** usa RD em MULT/DIV (sempre 0)
4. O compilador **sempre** emite MOVE logo após MULT/DIV para copiar $lo para um $tN
5. MULT do compilador usa apenas a parte baixa (32 bits); o compilador não lê $hi para multiplicação

---

## 8. Instruções de memória (LW/SW)

### 8.1 LW (Load Word)

Formato F2. Lê da memória de dados.

```
Endereço efetivo = Reg[RS] + signext(Imm)
RD ← MEM[endereço efetivo]
```

**Exemplo real (teste2.txt, addr 7):**
```
00111100101001110000000000000001
│001111│001010│011100│00000000000001│
│  LW  │$t2=10│$gp=28│   Imm=1     │
```
→ `lw $t2,1($gp)` — carrega variável `x` da posição `$gp + 1`

**Exemplo real (gcd.txt, addr 3):**
```
00111100100001110100000000000001
│001111│001000│011101│00000000000001│
│  LW  │$t0=8 │$sp=29│   Imm=1     │
```
→ `lw $t0,1($sp)` — carrega parâmetro `v` da pilha

### 8.2 SW (Store Word)

Formato F2. Escreve na memória de dados.

```
Endereço efetivo = Reg[RS] + signext(Imm)
MEM[endereço efetivo] ← Reg[RD]
```

**NOTA sobre SW:** No formato F2, o campo chamado "RD" (bits 25-20) contém o registrador **fonte** (cujo valor será escrito na memória). O campo "RS" (bits 19-14) contém o registrador **base** para cálculo do endereço. A nomenclatura "RD" vem do formato, não da semântica — em SW, RD é a fonte e RS é a base.

**Exemplo real (teste2.txt, addr 4):**
```
01000000100001110000000000000001
│010000│001000│011100│00000000000001│
│  SW  │$t0=8 │$gp=28│   Imm=1     │
```
→ `sw $t0,1($gp)` — armazena `$t0` na posição `$gp + 1`

---

## 9. Instrução SLT (Set on Less Than)

Formato F1. Comparação entre registradores.

```
RD ← (RS < RT) ? 1 : 0
```

A comparação é com sinal (signed).

**Exemplo real (sort.txt, addr 16):**
```
01100100111000111101000000000000
│011001│001110│001111│010000│00000000│
│ SLT  │$t6=14│$t7=15│$t8=16│ sh=0   │
```
→ `slt $t8,$t6,$t7` — `$t8 = ($t6 < $t7) ? 1 : 0`

O compilador usa SLT seguido de BEQ com $zero para implementar condições de loop:
```
slt  $t8,$t6,$t7      # $t8 = (i < high) ? 1 : 0
beq  $t8,$zero,L1     # se $t8 == 0, sai do loop
```

---

## 10. Instruções de I/O

### 10.1 IN (Input)

Formato FI. Lê valor de entrada (switches da FPGA) e grava no registrador.

```
Reg ← valor_de_entrada
```

**Exemplo real (teste.txt, addr 3):**
```
01101000100000000000000000000000
│011010│001000│00000000000000000000│
│  IN  │$t0=8 │      zeros         │
```

### 10.2 OUT (Output)

Formato FI. Envia valor do registrador para a saída (display).

```
saída ← Reg
```

**Exemplo real (teste2.txt, addr 12):**
```
01101100110000000000000000000000
│011011│001100│00000000000000000000│
│ OUT  │$t4=12│      zeros         │
```

---

## 11. Instrução HLT

Formato F3. Todos os 26 bits de endereço são zero.

```
01100000000000000000000000000000
│011000│00000000000000000000000000│
│ HLT  │         zeros            │
```

O processador deve parar de avançar o PC. Tipicamente implementado como um flag que desabilita a escrita no PC.

---

## 12. Fluxo de execução típico

### 12.1 Programa simples (teste2.cms: 5+3=8)

```
Addr 0:  j main          → PC = 1 (main)
Addr 1:  addi $sp,$sp,-1 → $sp = $sp - 1
Addr 2:  sw $ra,0($sp)   → MEM[$sp] = $ra
Addr 3:  addi $t0,$zero,5 → $t0 = 5
Addr 4:  sw $t0,1($gp)   → MEM[$gp+1] = 5 (x)
Addr 5:  addi $t1,$zero,3 → $t1 = 3
Addr 6:  sw $t1,2($gp)   → MEM[$gp+2] = 3 (y)
Addr 7:  lw $t2,1($gp)   → $t2 = MEM[$gp+1] = 5
Addr 8:  lw $t3,2($gp)   → $t3 = MEM[$gp+2] = 3
Addr 9:  add $t4,$t2,$t3  → $t4 = 5 + 3 = 8
Addr 10: addi $sp,$sp,-1
Addr 11: sw $t4,0($sp)
Addr 12: out $t4          → output = 8
Addr 13: addi $sp,$sp,1
Addr 14: hlt              → FIM
```

### 12.2 Programa com chamada de função (gcd.cms)

```
Addr 0:  j main           → salta para main (addr 38)
Addr 1:  gcd:             → início de gcd
         ...               (corpo de gcd, incluindo chamada recursiva)
Addr 38: main:            → início de main
         in $t3            → lê x
         in $t4            → lê y
         push x, push y
         jal gcd           → chama gcd, $ra = PC+1
         ...
         out $t7           → imprime resultado
         hlt               → FIM
```

### 12.3 Convenção de chamada de função

**Caller (chamador):**
1. Empilha argumentos: `addi $sp,$sp,-1` + `sw arg,0($sp)` para cada argumento
2. `jal funcao` — salva `PC+1` em `$ra`, salta para o endereço da função
3. Após retorno: `addi $sp,$sp,N` para limpar N argumentos da pilha
4. Resultado em `$v0`: `add $tN,$v0,$zero`

**Callee (chamado):**
1. Prologue: `addi $sp,$sp,-1` + `sw $ra,0($sp)` (salva $ra)
2. Acessa parâmetros via offsets em `$sp`
3. Para retornar: `add $v0,resultado,$zero` + `lw $ra,0($sp)` + `addi $sp,$sp,1` + `jr $ra`
4. Se é `main`: termina com `hlt` em vez de `jr $ra`

---

## 13. Checklist de implementação do processador

### 13.1 Decodificação de instrução (obrigatório)

- [ ] Extrair opcode (bits 31-26)
- [ ] Para F1: extrair RS (25-20), RT (19-14), RD (13-8), Shamt (7-0)
- [ ] Para F2: extrair RD (25-20), RS (19-14), Imm (13-0) com extensão de sinal
- [ ] Para F3: extrair Endereço (25-0)
- [ ] Para FI: extrair Reg (25-20)

### 13.2 ULA (obrigatório)

- [ ] ADD: soma signed
- [ ] SUB: subtração signed
- [ ] MULT: multiplicação signed, resultado 64-bit em {$hi,$lo}
- [ ] DIV: divisão signed, quociente em $lo, resto em $hi
- [ ] AND, OR, NOT: operações lógicas
- [ ] SLT: comparação signed, resultado 0 ou 1
- [ ] SR, SL: shifts por Shamt

### 13.3 Controle de fluxo (obrigatório)

- [ ] PC ← PC + 1 (avanço normal)
- [ ] J: PC ← Addr (26 bits)
- [ ] JAL: $ra ← PC + 1, PC ← Addr
- [ ] JR: PC ← Reg[RS]
- [ ] BEQ: se Reg[RD] == Reg[RS], PC ← PC + 1 + signext(Imm)
- [ ] BNE: se Reg[RD] != Reg[RS], PC ← PC + 1 + signext(Imm)
- [ ] HLT: PC congela

### 13.4 Registradores especiais (obrigatório)

- [ ] $zero (reg 0): sempre lê 0
- [ ] $hi (reg 62): escrito por MULT/DIV
- [ ] $lo (reg 61): escrito por MULT/DIV
- [ ] $ra (reg 31): escrito por JAL com PC + 1
- [ ] MOVE (opcode 010110): copia RS para RD (inclui $lo → $tN)

### 13.5 Memória (obrigatório)

- [ ] LW: RD ← MEM[RS + signext(Imm)]
- [ ] SW: MEM[RS + signext(Imm)] ← RD

### 13.6 I/O (obrigatório)

- [ ] IN: Reg ← input externo
- [ ] OUT: output externo ← Reg

### 13.7 Inicialização

- [ ] PC = 0
- [ ] $zero = 0 (hardwired)
- [ ] $gp = 0 (ou endereço base da memória de dados)
- [ ] $sp = 1023 (ou topo da memória de dados)
- [ ] Memória de instruções carregada com o .txt

---

## 14. Binários de referência para teste

Os seguintes binários foram validados manualmente e podem ser usados para testar o processador:

| Arquivo | Instruções | Comportamento esperado |
|---------|-----------|----------------------|
| `teste2.txt` | 15 | Calcula 5+3=8, output 8 |
| `teste.txt` | 15 | Lê 2 valores (in), soma, output resultado |
| `fatorial.txt` | 27 | Calcula 5!=120, output 120 |
| `gcd.txt` | 58 | Lê 2 valores, calcula MDC (Euclides recursivo), output |
| `sort.txt` | 141 | Lê 10 valores, ordena (selection sort), output 10 valores |

**Ordem de teste recomendada:** teste2 → teste → fatorial → gcd → sort (complexidade crescente).

- **teste2** valida: ADD, ADDI, LW, SW, OUT, HLT, J
- **teste** adiciona: IN
- **fatorial** adiciona: SLT, BEQ, MULT, MOVE, SUB, loops
- **gcd** adiciona: JAL, JR, DIV, chamadas recursivas, $v0, $ra
- **sort** adiciona: múltiplas funções, arrays, pilha intensiva

---

## 15. Pontos críticos de atenção

1. **PC avança de 1 em 1**, não de 4 em 4. O `.txt` é word-addressed.
2. **Branch offset** é relativo a `PC + 1`, não a `PC`. Fórmula: `novo_PC = PC + 1 + signext(Imm)`.
3. **SW no F2:** bits 25-20 contêm o registrador fonte (valor a escrever), não o destino. A nomenclatura "RD" no formato é enganosa para SW.
4. **MULT/DIV:** resultado vai para $hi/$lo, RD no F1 é 0. O processador deve detectar MULT/DIV e escrever em $hi/$lo em vez de RD.
5. **MOVE lê $lo/$hi:** quando RS=61 ou RS=62, MOVE deve ler os registradores especiais.
6. **JAL salva PC+1** em $ra (registrador 31), não PC+4.
7. **$zero** (reg 0) deve ser hardwired a 0. Muitas instruções dependem de ler 0 deste registrador.
8. **Extensão de sinal** do imediato de 14 bits é essencial — offsets negativos (ex: `addi $sp,$sp,-1`) usam complemento de 2.
9. **HLT** deve parar o PC. O programa termina com esta instrução.
10. **Endereçamento de memória** de dados é em palavras (não bytes). `lw $t0,1($gp)` lê a palavra no endereço `$gp + 1`, não `$gp + 4`.
