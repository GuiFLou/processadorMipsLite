# Contexto do Processador MIPS‑Lite — Referência para implementação em Verilog

Este documento define **tudo que o processador precisa implementar** para executar corretamente os binários gerados pelo compilador C‑. Ele é a referência autoritativa para a implementação/revisão do processador em Verilog.

Os exemplos de codificação vêm de arquivos que existem no repositório: os dez programas do alvo `os-user` gravados em `hd_image.txt` (setores 20–29) e o binário legado `processador/gcd.txt`, anterior ao `$fp` e ao NOP de tamanho. Os binários legados `teste`, `teste2`, `fatorial` e `sort` citados em versões anteriores deste arquivo não estão mais no repositório. O mapa de memória e o MMIO completos estão em `../../so/docs/CONTEXT.md`; a simulação está descrita em `../README.md`.

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
| Memória de instruções | 4096 palavras × 32 bits (`inst_mem_rw`) |
| Memória de dados | 4096 palavras × 32 bits (`data_ram`) |
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
**Para HLT:** sem retorno armado, o PC congela e LEDR[16] acende. Com o retorno armado por `SW` em 4088, volta ao PC salvo, grava a causa 2 em 4089 e desarma. O detalhe está no item 9 da seção 15.

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
| 13 | SR | 001101 | 13 | F1 | RD ← RS >>> Shamt (aritmético, usa Shamt[4:0]) |
| 14 | SL | 001110 | 14 | F1 | RD ← RS << Shamt (usa Shamt[4:0]) |
| 15 | LW | 001111 | 15 | F2 | RD ← MEM[RS + signext(Imm)] |
| 16 | SW | 010000 | 16 | F2 | MEM[RS + signext(Imm)] ← RD |
| 17 | J | 010001 | 17 | F3 | PC ← Addr |
| 18 | JR | 010010 | 18 | F1 | PC ← RS |
| 19 | JAL | 010011 | 19 | F3 | $ra ← PC+1 ; PC ← Addr |
| 20 | BEQ | 010100 | 20 | F2 | se RD == RS: PC ← PC+1+signext(Imm) |
| 21 | BNE | 010101 | 21 | F2 | se RD != RS: PC ← PC+1+signext(Imm) |
| 22 | MOVE | 010110 | 22 | F2 | RD ← RS |
| 23 | NOP | 010111 | 23 | F3 | nenhuma operação |
| 24 | HLT | 011000 | 24 | F3 | congela o PC, ou volta se 4088 armou |
| 25 | SLT | 011001 | 25 | F1 | RD ← (RS < RT) ? 1 : 0 |
| 26 | IN | 011010 | 26 | FI | Reg ← input |
| 27 | OUT | 011011 | 27 | FI | output ← Reg |

Opcodes 28–63 não têm decode e se comportam como NOP.

### 3.2 Instruções usadas pelos dez programas do HD

Contagem feita nos binários `os-user` dos setores 20–29 de `hd_image.txt`.

| Instrução | Usada por |
|-----------|-----------|
| ADD, ADDI, LW, SW, J, NOP, HLT, IN, OUT | todos |
| BEQ | todos, exceto `area_triangulo` |
| SLT | `busca_linear`, `fatorial`, `fibonacci`, `media`, `numero_primo`, `potencia`, `soma_digitos`, `sort` |
| MOVE | `area_triangulo`, `fatorial`, `gcd`, `media`, `numero_primo`, `potencia`, `soma_digitos` |
| SUB | `busca_linear`, `fatorial`, `gcd`, `numero_primo`, `soma_digitos`, `sort` |
| MULT | `area_triangulo`, `fatorial`, `gcd`, `numero_primo`, `potencia`, `soma_digitos` |
| DIV | `area_triangulo`, `gcd`, `media`, `numero_primo`, `soma_digitos` |
| JR, JAL | `gcd`, `sort` |

Nenhum dos dez usa SUBI, MULTI, DIVI, AND, ANDI, OR, ORI, NOT, SR, SL ou
BNE. O kernel usa ANDI, OR, SL, SR e BNE nos intrínsecos do LCD e do HD.
NOP é a primeira palavra de todo binário do compilador e guarda o tamanho.

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
| `$fp` | 30 | 011110 | Ponteiro de frame (parâmetros e locais) |
| `$ra` | 31 | 011111 | Endereço de retorno (escrito por JAL) |
| `$lo` | 61 | 111101 | Resultado baixo de MULT/DIV |
| `$hi` | 62 | 111110 | Resultado alto de MULT/DIV |

### 4.2 Requisitos do hardware

1. **$zero** deve sempre ler 0, escritas são ignoradas
2. **$lo e $hi** devem ser escritos por MULT e DIV automaticamente
3. **$lo e $hi** devem ser lidos por MOVE (`move $tN,$lo` → `MOVE RD=$tN, RS=$lo`)
4. **$ra** deve ser escrito por JAL com `PC + 1`
5. **$gp** começa em 0: o reset (síncrono) zera o banco inteiro
6. **$sp** começa em 1023: o reset grava esse valor no registrador 29. O prólogo do alvo padrão troca por 1015 e o do `os-user` por 1791

O banco (`regfile64.v`) tem leitura combinacional e escrita síncrona na borda do `clk_cpu`.

---

## 5. Memória

### 5.1 Memória de instruções (`inst_mem_rw`)

- 4096 palavras × 32 bits
- Endereçada pelo PC (word address, 0 a 4095)
- Carregada com o conteúdo de `so.txt` (uma linha = uma instrução); o restante fica em zero
- Fetch combinacional pelo PC (`assign rdata_a = mem[addr_a]`); a porta B aceita escrita síncrona do HD (comando 2)
- O reset (KEY[0]) não recarrega a IMEM

### 5.2 Memória de dados (RAM)

- 4096 palavras × 32 bits
- Endereçada por `RS + signext(Imm)` nas instruções LW/SW
- A porta A da CPU usa 0–4087. Os endereços 4088–4095 são MMIO; acima de 4095 a escrita é descartada e a leitura devolve 0
- Leitura assíncrona nas duas portas; as duas escritas ficam no mesmo `always`
- O reset não limpa a RAM
- As globais ficam em `$gp + memloc`; a pilha começa no valor do prólogo e cresce para baixo

**Risco de síntese.** Nesse estilo (leitura assíncrona, duas escritas no mesmo `always`), o Quartus não infere M9K para a IMEM nem para a RAM: são cerca de 262 mil bits em flip-flops, contra 114.480 elementos lógicos do EP4CE115. O `hd_sim` usa `(* ramstyle = "M9K" *)` com leitura síncrona. O último fit em `output_files/` é de junho de 2026, anterior ao mapa de 4096 palavras, e a Fase 1 ainda não foi validada na placa.

### 5.3 Layout da memória de dados (exemplo: sort.cms)

```
$gp + 0..9:   vet[10] (vetor global; endereços 1536..1545 no os-user)
frame:        parâmetros em offsets positivos de $fp, locais em offsets negativos
```

No alvo padrão `$gp` é 0 e a pilha começa em 1015; no `os-user`, `$gp` é 1536 e a pilha começa em 1791. A pilha cresce para baixo com `addi $sp,$sp,-1`.

### 5.4 HD simulado e DMA para RAM

O módulo `hd_sim` representa um HD com 64 setores de 256 palavras de 32 bits.
Internamente, as 16.384 palavras são armazenadas de forma linear. O conteúdo
inicial é zerado e pode ser substituído por um arquivo definido no parâmetro
`HD_FILE`. O valor padrão é `hd_image.txt`, com 16.384 linhas: catálogo no
setor 0, NOP nos setores 1–12, os binários recompilados nos setores 20–29 e
zero no restante de cada setor e nos demais. Durante a
compilação do Quartus, o `$readmemb` de `hd_sim.v` usa esse arquivo para
inicializar o armazenamento do HD.

Layout inicial dos programas:

| Setor | Programa |
|-------|----------|
| 20 | `area_triangulo` |
| 21 | `busca_linear` |
| 22 | `fatorial` |
| 23 | `fibonacci` |
| 24 | `gcd` |
| 25 | `media` |
| 26 | `numero_primo` |
| 27 | `potencia` |
| 28 | `soma_digitos` |
| 29 | `sort` |

Na imagem, os programas ocupam os setores 20–29, cada um no início do seu
setor. Esses binários são os do alvo `os-user` e não saem de
`compilador/exemplos/`. Os setores 1–12 guardam NOP e o salto de guarda na
palavra 3071. A IMEM de reset é `processador/so.txt`: 4096 palavras, kernel
compilado em 0–1334, NOP em 1335–3070, `J 3071` na palavra 3071 e zero em
3072–4095. O supervisor ainda não existe. O Quartus lê `so.txt` e
`hd_image.txt` do diretório do processador (`MISC_FILE` no `.qsf`).

O HD é controlado por quatro endereços MMIO (4092–4095). O LCD usa **4091**
(`display_ctx`, §10.3) e não participa do DMA.

| Endereço | Registrador | Função |
|----------|-------------|--------|
| 4092 | `cmd` | `1`: HD → RAM; `2`: HD → IMEM; `3`: RAM → HD |
| 4093 | `sector` | Setor lógico entre 0 e 63 |
| 4094 | `addr` | Endereço-base na RAM (cmd 1/3) ou na IMEM (cmd 2) |
| 4095 | `status` | `0`: idle; `1`: busy; `2`: done; `3`: error |

O software configura `sector` e `addr` e, por último, escreve o comando em
`cmd`. Cada comando transfere o setor completo. Os parâmetros são congelados
durante a operação, e novas escritas MMIO são ignoradas enquanto `status`
estiver em `busy`.

A memória de instruções (`inst_mem_rw`) mantém o fetch combinacional da ROM
original e aceita escrita pela porta B do HD. O comando `2` copia um setor
do HD para a IMEM a partir de `addr`.

O endereço-base da RAM (comandos 1 e 3) deve estar entre 0 e 3832, para a
última palavra não passar de 4087. O endereço-base da IMEM (comando 2) deve
estar entre 0 e 3840, para a última palavra não passar de 4095. Setor,
endereço ou comando inválido produz `error` sem iniciar a transferência.

Durante a transferência o PC e as escritas da CPU ficam parados. A 256ª
palavra e o avanço do PC acontecem no mesmo ciclo. O comando inválido não
trava o PC. Na síntese, `CPU_DIV` é 5000 (cerca de 5 kHz), `BTN_STABLE` é
1000000 e o LCD usa os tempos reais. No `.sdc`, o `-divide_by` correto do
`clk_cpu` é 10000 (2 · `CPU_DIV`). Os testbenches que instanciam o top-level
usam `CPU_DIV` 1, `BTN_STABLE` 3 e tempos curtos de LCD.
O programa não deve acessar a faixa da RAM que está sendo transferida. Se a
porta A e o DMA escreverem no mesmo endereço na mesma borda, a porta do DMA
tem prioridade.

Nesta etapa, o acesso ao HD é reservado ao SO por convenção.
Ainda não há proteção por modo kernel, trap ou interrupção.

---

## 6. Cálculo de endereços de salto e branch

Os exemplos das seções 6–11 indicam a origem de cada palavra. "Setor N,
addr A" é a palavra A do binário gravado no setor N de `hd_image.txt` (linha
`N·256 + A + 1` do arquivo); esses binários são do alvo `os-user`. "`gcd.txt`
legado" é `processador/gcd.txt`, sem NOP de tamanho, sem `$fp` e com saltos a
partir de 0; ele serve só para ilustrar a codificação.

### 6.1 Jump (J) e JAL

Formato F3. O campo Endereço (26 bits) contém o **endereço absoluto** (word address) do destino.

```
PC ← Endereço[25:0]
```

No alvo `os-user` o encoder soma 3072 a cada `J`/`JAL`, porque o binário roda
na folha da vez. O endereço da palavra A do binário na IMEM é `3072 + A`.

**`gcd`, setor 24, addr 0:**
```
01011100000000000000000001001010
│opcode│        metadado        │
│010111│00000000000000000001001010│ = NOP; tamanho total 74 palavras
```

As palavras 1 e 2 são o prólogo `addi $gp,$zero,1536` e `addi $sp,$zero,1791`.

**Mesmo binário, addr 3:**
```
01000100000000000000110000110010
│010001│00000000000000110000110010│ = J 3122 = 3072 + 50 (main)
```

**Mesmo binário, addr 40 (chamada recursiva) e addr 66 (chamada em main):**
```
01001100000000000000110000000100
│010011│00000000000000110000000100│ = JAL 3076 = 3072 + 4 (gcd)
```

A palavra 73 é o `HLT` final. As palavras 74–255 do setor são zero.

### 6.2 Branch (BEQ/BNE)

Formato F2. O campo Imediato (14 bits, com sinal) contém o **offset relativo** ao PC+1.

```
se condição verdadeira:
    PC ← PC + 1 + signext(Imm[13:0])
senão:
    PC ← PC + 1
```

**ATENÇÃO:** O offset é calculado como `addr_destino - addr_branch - 1`. O processador soma `signext(Imm)` a `PC + 1` (que é o endereço da próxima instrução sequencial).

Como o offset é relativo, o mesmo `BEQ` vale em 0 ou em 3072; o `os-user` não o altera.

**`fatorial`, setor 22, addr 17:**
```
01010000110000000000000000001010
│010100│001100│000000│00000000001010│
│ BEQ  │$t4   │$zero │ Imm = 10    │
```
Destino: `17 + 1 + 10 = 28` (label L1, saída do `while`) ✅

**`gcd.txt` legado, addr 6:**
```
01010000101000000000000000000010
│010100│001010│000000│00000000000010│
│ BEQ  │$t2   │$zero │ Imm = 2     │
```
Destino: `6 + 1 + 2 = 9` (label .L_eq_0) ✅

### 6.3 JR (Jump Register)

Formato F1. O campo RS contém o registrador com o endereço de destino.

```
PC ← Reg[RS]
```

**`gcd.txt` legado, addr 15 (a mesma palavra está no setor 24, addr 24 e 49):**
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

**`fatorial`, setor 22, addr 20:**
```
00010000110100111000000000000000
│000100│001101│001110│000000│00000000│
│ MULT │$t5=13│$t6=14│ RD=0 │ sh=0   │
```
Seguido por (addr 21): `move $t7,$lo`
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

**`gcd.txt` legado, addr 23 (a mesma palavra está no setor 24, addr 32):**
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

**`fatorial`, setor 22, addr 14:**
```
00111100101001111011111111111111
│001111│001010│011110│11111111111111│
│  LW  │$t2=10│$fp=30│   Imm=-1    │
```
→ `lw $t2,-1($fp)` — carrega o local `n` do frame de `main`

**`gcd.txt` legado, addr 3:**
```
00111100100001110100000000000001
│001111│001000│011101│00000000000001│
│  LW  │$t0=8 │$sp=29│   Imm=1     │
```
→ `lw $t0,1($sp)` — o compilador legado lia o parâmetro `v` pela pilha. O atual usa `lw $t0,2($fp)` (setor 24, addr 9)

### 8.2 SW (Store Word)

Formato F2. Escreve na memória de dados.

```
Endereço efetivo = Reg[RS] + signext(Imm)
MEM[endereço efetivo] ← Reg[RD]
```

**NOTA sobre SW:** No formato F2, o campo chamado "RD" (bits 25-20) contém o registrador **fonte** (cujo valor será escrito na memória). O campo "RS" (bits 19-14) contém o registrador **base** para cálculo do endereço. A nomenclatura "RD" vem do formato, não da semântica — em SW, RD é a fonte e RS é a base.

**`fatorial`, setor 22, addr 11:**
```
01000000100001111011111111111111
│010000│001000│011110│11111111111111│
│  SW  │$t0=8 │$fp=30│   Imm=-1    │
```
→ `sw $t0,-1($fp)` — guarda em `n` o valor lido pelo `IN`

---

## 9. Instrução SLT (Set on Less Than)

Formato F1. Comparação entre registradores.

```
RD ← (RS < RT) ? 1 : 0
```

A comparação é com sinal (signed).

**`fatorial`, setor 22, addr 16:**
```
01100100101100101000110000000000
│011001│001011│001010│001100│00000000│
│ SLT  │$t3=11│$t2=10│$t4=12│ sh=0   │
```
→ `slt $t4,$t3,$t2` — `$t4 = ($t3 < $t2) ? 1 : 0`

O compilador usa SLT seguido de BEQ com $zero para implementar condições de loop. `n > 0` vira `0 < n`:
```
slt  $t4,$t3,$t2      # $t4 = (0 < n) ? 1 : 0
beq  $t4,$zero,L1     # se $t4 == 0, sai do loop
```

---

## 10. Instruções de I/O

### 10.1 IN (Input)

Formato FI. Lê valor de entrada (switches da FPGA) e grava no registrador.

```
Reg ← {22'b0, SW[9:0]}
```

O PC fica parado no `IN` (LEDR[17] aceso) até um pulso de KEY[1]. O registrador só é escrito no ciclo desse pulso.

**`fatorial`, setor 22, addr 10:**
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

O valor vai para `out_reg` e aparece em decimal nos HEX0–HEX6. O PC fica parado no `OUT` (LEDR[17] aceso) até um pulso de KEY[1]; o último valor continua no display.

**`fatorial`, setor 22, addr 31:**
```
01101100100100000000000000000000
│011011│001001│00000000000000000000│
│ OUT  │$t1=9 │      zeros         │
```

### 10.3 LCD (MMIO, sem opcode)

O painel 16×2 da DE2-115 **não** tem instrução na ISA. O kernel escreve o
registrador `display_ctx` no endereço **4091**. O hardware desenha uma
mensagem fixa: 1 MENU, 2 BEM-VINDO, 3 RUN, 4 OK, 5 ERR, 6 PROG, 7 QUANTOS,
8 ARQUIVOS. MENU tem 3 itens; PROG e QUANTOS têm 10; as outras telas têm 1.
KEY[2]/KEY[3] andam o índice quando há mais de um item. KEY[1] liga o ack
(bit 27) sem mudar o índice, desde que a CPU não esteja parada em IN ou OUT.
O Enter que solta um IN/OUT não confirma o menu. Um `SW` que muda o modo
zera o índice e o ack. No mesmo modo, o `SW` preserva a seleção e só zera o
ack que um `LW` de 4091 já leu em 1 (`disp_seen`); um Enter ainda não lido,
ou que chega no ciclo do `SW`, continua valendo. Leitura devolve `{4'b0, ack, sel[4:0], pid[3:0], id[9:0], mode[7:0]}`.

---

## 11. Instrução HLT

Formato F3. Todos os 26 bits de endereço são zero.

```
01100000000000000000000000000000
│011000│00000000000000000000000000│
│ HLT  │         zeros            │
```

O processador, sem retorno armado, para de avançar o PC e acende LEDR[16]. Se um `SW` em 4088 armou o retorno, o `HLT` volta ao PC salvo, grava a causa 2 em 4089 e desarma. A codificação acima é a da instrução; o endereço de 26 bits continua zero.

---

## 12. Fluxo de execução dos binários atuais

### 12.1 Programa com chamada de função (`gcd`, setor 24)

Endereços relativos ao início do binário; na folha, some 3072.

```
Addr 0:  nop 74            → tamanho total (o processador executa como NOP)
Addr 1:  addi $gp,$zero,1536
Addr 2:  addi $sp,$zero,1791
Addr 3:  j 3122            → main (addr 50)
Addr 4:  gcd:              → prólogo com $ra e $fp
         ...                (corpo, com jr $ra em addr 24 e 49)
Addr 40: jal 3076          → chamada recursiva gcd(v, u-u/v*v)
         ...
Addr 50: main:             → prólogo e dois locais (x em -1($fp), y em -2($fp))
Addr 56: in $t3            → lê x
Addr 58: in $t4            → lê y
         push x, push y
Addr 66: jal 3076          → gcd(x, y), $ra = PC+1
         ...
Addr 71: out $t7           → imprime o resultado
Addr 73: hlt               → fim
```

No alvo padrão o prólogo tem uma palavra só (`addi $sp,$zero,1015`), `$gp`
fica no 0 do reset e os saltos não recebem 3072. Quando o kernel chama a
folha por `runat(3072)`, o `HLT` final é o `HLT` armado e o PC volta ao
kernel; sem arma, o PC congela nele.

### 12.2 Convenção de chamada de função (`asmgen.c`)

**Caller (chamador):**
1. Empilha argumentos: `addi $sp,$sp,-1` + `sw arg,0($sp)` para cada argumento
2. `jal funcao` — salva `PC+1` em `$ra`, salta para o endereço da função
3. Após retorno: `addi $sp,$sp,N` para limpar N argumentos da pilha
4. Resultado em `$v0`: `add $tN,$v0,$zero`

**Callee (chamado):**
1. Prólogo: `addi $sp,$sp,-1` + `sw $ra,0($sp)`, `addi $sp,$sp,-1` + `sw $fp,0($sp)`, `add $fp,$sp,$zero` e, se houver locais, `addi $sp,$sp,-L`
2. Frame: `0($fp)` é o `$fp` antigo, `1($fp)` é o `$ra`, `2($fp)` é o último parâmetro e `(1+N)($fp)` o primeiro; os locais ficam em `-1($fp)` até `-L($fp)`
3. Para retornar: `add $v0,resultado,$zero` + `add $sp,$fp,$zero` + `lw $fp,0($sp)` + `addi $sp,$sp,1` + `lw $ra,0($sp)` + `addi $sp,$sp,1` + `jr $ra`
4. `main` também tem prólogo, mas termina com `hlt` em vez do epílogo

Nada salva `$t0`–`$t9` antes de um `jal`. Uma expressão que usa um temporário
depois de uma chamada recursiva, como `n * fat(n-1)`, lê o valor sobrescrito
pela chamada interna.

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
- [ ] HLT: sem arma, PC congela e LEDR[16] acende; com arma, volta ao PC salvo, grava a causa 2 e desarma

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

## 14. Binários armazenados no HD

Os dez programas foram recompilados com `--target=os-user` e incluídos em
`hd_image.txt`. O prólogo é `addi $gp,$zero,1536` e `addi $sp,$zero,1791`,
depois `j main`. Cada `J`/`JAL` soma 3072. `BEQ` e `BNE` continuam relativos.
Imagem acima de 256 palavras é recusada, e o alvo recusa HD, LCD e `runat`.
A análise semântica também recusa mais de 256 posições de símbolos
(`analyze.c`), mas essa conta não inclui a pilha, que divide a janela
1536–1791 com as globais.
A primeira palavra de cada programa é um NOP de metadados:
o opcode é `010111` e os 26 bits restantes contêm o tamanho total, incluindo
o próprio cabeçalho e o HLT final.

| Programa | Setor | Palavras | ID |
|----------|-------|----------|----|
| `area_triangulo` | 20 | 28 | 1 |
| `busca_linear` | 21 | 63 | 2 |
| `fatorial` | 22 | 34 | 3 |
| `fibonacci` | 23 | 41 | 4 |
| `gcd` | 24 | 74 | 5 |
| `media` | 25 | 46 | 6 |
| `numero_primo` | 26 | 57 | 7 |
| `potencia` | 27 | 38 | 8 |
| `soma_digitos` | 28 | 44 | 9 |
| `sort` | 29 | 162 | 10 |

Na montagem de `hd_image.txt`, cada `.txt` desse alvo é copiado para o início
do setor correspondente. O restante do setor é preenchido com palavras zero.
O alvo padrão de `exemplos/` continua com `addi $sp,$zero,1015` e saltos a partir de 0. Essa pasta não é a imagem que o SO executa. `reset_tests.sh` sem flag regenera a ROM solta. Com `--target=os-user` grava só os setores 20–29 de `hd_image.txt` e não mexe em `exemplos/`.

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
9. **HLT** sem retorno armado congela o PC e acende LEDR[16]. `SW` em 4088 só arma quando o destino está entre 3072 e 3839 e o HD não está congelado: grava PC+1 em `kret` e na RAM 1042 e desvia. Fora da folha a escrita é ignorada. O `HLT` seguinte volta para esse PC, grava `epc` com o PC do próprio `HLT`, grava a causa 2 em 4089 e desarma. A leitura de 4088 devolve `epc`. Nada escreve em 4089 depois disso: a causa fica em 2 até o reset. `ctrl` (4090) não tem decode: a leitura devolve 0 e a escrita é descartada.
10. **Endereçamento de memória** de dados é em palavras (não bytes). `lw $t0,1($gp)` lê a palavra no endereço `$gp + 1`, não `$gp + 4`.
11. **Reset (KEY[0])** zera o PC, o banco (com `$sp` = 1023), `hi`/`lo`, `out_reg`, `display_ctx`, `kret`, `epc`, `cause` e os registradores do HD. Não recarrega a IMEM, a RAM nem o armazenamento do HD.

---

## 16. Testbenches

Todos passam no Icarus Verilog. Os comandos estão em `../README.md`.

| Teste | O que confere |
|-------|---------------|
| `tb_hd_map` | Assinatura do catálogo e `J 3071` em `hd_image.txt`; base 3833 recusada para RAM; setor 20 copiado para a IMEM em 3072. |
| `tb_hd_stall` | `SW` em `hd_cmd` segura o PC durante a transferência; o PC avança uma vez e a instrução seguinte executa. |
| `tb_lcd` | `display_ctx` (4091), KEY[1]–KEY[3], o Enter de `IN` sem ack, as telas; sentinela 99 em 4088 fora da folha não desvia e a leitura dá 0; 8187 não é alias. |
| `tb_retorno` | Folha em 3072 executa; o `HLT` armado volta para PC+1; `kret` e RAM[1042] guardam PC+1; `cause` = 2, `epc` = 3072, arma desligada; o `HLT` seguinte, sem arma, congela o PC. |
| `tb_menu` | Imagem de reset real (`so.txt`, 4096 palavras, a mesma do Quartus): menu, área na opção 1, volta com `$gp` 0, segundo programa na folha; Enter durante o redesenho da lista vale e Enter no `SW` que troca ERR por MENU não confirma. |
