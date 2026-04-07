# Plano de Revisão — Processador MIPS-Lite

Documento de referência: `CONTEXTO_PROCESSADOR.md` (especificação autoritativa da ISA e microarquitetura).

---

## Visão geral dos problemas

A implementação atual possui **erros de compilação** (wires indefinidos), **erros de datapath** (endereçamento de memória, portas do register file, ALU) e **funcionalidades ausentes** (I/O, MULT/DIV→$hi/$lo, inicialização de $gp/$sp). O plano está organizado em fases com dependências claras.

---

## Fase 0 — Corrigir erros de compilação

> **Objetivo:** o design deve compilar sem erros no Quartus antes de qualquer outra alteração.

### 0.1 Wires indefinidos no top-level

**Arquivo:** `Processador_GUI_MIPS.v`

O módulo usa `fld_hi6`, `fld_lo6` e `f1_rd` que **nunca são declarados**. Estes devem ser mapeados para os campos já extraídos da instrução:

| Wire indefinido | Significado pretendido | Substituir por |
|-----------------|----------------------|----------------|
| `fld_hi6` | bits [25:20] da instrução | `rs` (já declarado) |
| `fld_lo6` | bits [19:14] da instrução | `rt` (já declarado) |
| `f1_rd` | bits [13:8] da instrução | `rd` (já declarado) |

**Nota sobre nomes:** No formato F1, `rs`=bits[25:20], `rt`=bits[19:14], `rd`=bits[13:8]. No formato F2, bits[25:20] é o campo RD e bits[19:14] é o campo RS. Os nomes `rs`/`rt`/`rd` no Verilog seguem o F1, o que gera confusão para F2. Devemos renomear para nomes neutros (`field_25_20`, `field_19_14`, `field_13_8`) ou manter os nomes atuais com comentários claros.

**Ação:** Substituir todas as ocorrências de `fld_hi6`→`rs`, `fld_lo6`→`rt`, `f1_rd`→`rd` e verificar que a lógica resultante está correta (será revisada na Fase 1).

---

## Fase 1 — Corrigir o Datapath Central

### 1.1 Lógica das portas de leitura do Register File

**Arquivo:** `Processador_GUI_MIPS.v` (linhas 64–70)

A lógica de `rf_rs1`, `rf_rs2` e `writeReg` precisa ser refeita para atender todos os formatos:

| Instrução | Formato | rf_rs1 (→ALU A) | rf_rs2 (→ALU B / mem data) | writeReg |
|-----------|---------|-----------------|---------------------------|----------|
| ADD,SUB,AND,OR,SLT,SR,SL | F1 | instr[25:20] (RS) | instr[19:14] (RT) | instr[13:8] (RD) |
| MULT,DIV | F1 | instr[25:20] (RS) | instr[19:14] (RT) | — (escrita em $hi/$lo) |
| ADDI,SUBI,ANDI,ORI,NOT | F2 | instr[19:14] (RS) | — (usa imm) | instr[25:20] (RD) |
| LW | F2 | instr[19:14] (RS=base) | — | instr[25:20] (RD) |
| SW | F2 | instr[19:14] (RS=base) | instr[25:20] (RD=dado) | — |
| BEQ/BNE | F2 | instr[25:20] (RD=reg1) | instr[19:14] (RS=reg2) | — |
| MOVE | F2 | instr[19:14] (RS=fonte) | — | instr[25:20] (RD) |
| JR | F1 | instr[25:20] (RS=addr) | — | — |
| JAL | F3 | — | — | 6'd31 ($ra) |
| IN | FI | — | — | instr[25:20] (Reg) |
| OUT | FI | instr[25:20] (Reg) | — | — |

**Fórmulas propostas:**

```verilog
wire [5:0] field_25_20 = instr[25:20];
wire [5:0] field_19_14 = instr[19:14];
wire [5:0] field_13_8  = instr[13:8];

// Porta de leitura A (→ ALU input A, ou jump addr para JR, ou dado para OUT)
wire [5:0] rf_rs1 = (regDst | jr | branchEq | branchNe | isOut)
                        ? field_25_20   // F1:RS, BEQ:RD(reg1), JR:RS, OUT:Reg
                        : field_19_14;  // F2:RS (base/fonte)

// Porta de leitura B (→ ALU input B quando aluSrc=0, ou dado para SW)
wire [5:0] rf_rs2 = memWrite ? field_25_20   // SW: RD é o dado a escrever
                             : field_19_14;  // F1:RT, BEQ:RS(reg2)

// Porta de escrita
wire [5:0] writeReg = jal  ? 6'd31          // JAL → $ra
                    : regDst ? field_13_8    // F1 → RD
                    :          field_25_20;  // F2/FI → RD/Reg
```

### 1.2 Endereçamento da Memória de Dados (word addressing)

**Arquivo:** `Processador_GUI_MIPS.v` (linha 93)

**Problema:** A conexão atual usa `alu_y[11:2]`, que é conversão byte→word (dividindo por 4). Mas a ISA usa **endereçamento por palavra** — `LW $t2,1($gp)` deve acessar a palavra no endereço `$gp + 1`, não `($gp + 1) / 4`.

**Correção:**
```verilog
// ANTES (errado):
.addr_a(alu_y[11:2])

// DEPOIS (correto):
.addr_a(alu_y[9:0])
```

### 1.3 Dados de escrita na RAM (SW)

**Arquivo:** `Processador_GUI_MIPS.v` (linha 94)

**Problema:** A porta `.wdata_a(rf_b)` usa `rf_b` (saída rd2 do register file). Precisamos garantir que `rf_rs2` aponte para o registrador correto em SW (campo RD = bits[25:20], que contém o valor a ser escrito). Com a fórmula da Seção 1.1, `rf_rs2 = field_25_20` quando `memWrite=1`, o que é correto.

**Ação:** Verificar que `rf_b` corresponde a `rd2` do register file alimentado por `rf_rs2`. OK — já é o caso.

### 1.4 Correções na ALU

**Arquivo:** `alu.v`

| op | Atual | Problema | Correção |
|----|-------|----------|----------|
| 4'h4 (NOT) | `~a` | Correto se `a` = reg[RS]. Na control_unit, NOT é F2 com aluSrc=1 e aluOp=4'hA. Mas espera, aluOp=4'd10=4'hA é PASS, não NOT. | Mudar aluOp do NOT na CU para 4'h4 e verificar que ALU op 4'h4 faz `~a`. |
| 4'h5 (SLL) | `b << a[4:0]` | Shamt vem do campo de 8 bits da instrução, não de um registrador. Atualmente `a` = reg[RS] e `b` = reg[RT]. Deveria ser `a = reg[RS]` e shift por `shamt`. | A ALU precisa receber `shamt` como entrada, ou codificar shamt no input B. |
| 4'h6 (SRL) | `b >> a[4:0]` | Mesmo problema do SLL. | Mesma solução. |
| 4'h7 (SLT) | `($signed(a) < $signed(b))` | Correto para F1: a=RS, b=RT. | OK |
| 4'h8 (MUL) | `a * b` (low 32) | Não produz resultado de 64 bits para $hi. | Ver Seção 1.5. |
| 4'h9 (DIV) | `a / b` (quociente) | Não produz resto para $hi. | Ver Seção 1.5. |
| 4'hA (PASS) | `y = a` | Correto para MOVE. | OK. Mas a CU usa aluOp=0 para MOVE (ver Seção 3.3). |

**Ações na ALU:**
1. Adicionar porta `shamt` (8 bits) à ALU
2. SLL: `y = a << shamt` (RS << shamt, conforme ISA: `RD ← RS << Shamt`)
3. SRL: `y = a >> shamt`
4. Adicionar saídas `hi` e `lo` para MULT/DIV (ver 1.5)
5. Corrigir mapeamento SLL/SRL nos códigos (atualmente SLL=4'h5 e SRL=4'h6 estão trocados com SR/SL da CU)

**Atenção SR vs SL na CU:**
- ISA: SR = opcode 13 = shift right, SL = opcode 14 = shift left
- CU: SR → aluOp=4'd7, SL → aluOp=4'd6
- ALU: 4'h5 = SLL (shift left), 4'h6 = SRL (shift right)
- **Mismatch!** CU associa SR→7 e SL→6, mas ALU tem SLL=5 e SRL=6. Precisamos alinhar.

### 1.5 MULT/DIV → $hi e $lo

**Arquivos:** `alu.v`, `Processador_GUI_MIPS.v`, `control_unit.v`

**Problema:** MULT/DIV devem escrever em $hi (reg 62) e $lo (reg 61). Atualmente, o register file tem apenas uma porta de escrita e MULT/DIV tentam escrever em RD=0 (que é bloqueado pelo check `rd != 0`).

**Solução proposta:**

1. **ALU** — adicionar saídas `alu_hi` e `alu_lo`:
   ```verilog
   output reg [31:0] hi_out, lo_out
   // MULT: {hi_out, lo_out} = $signed(a) * $signed(b)  (64 bits)
   // DIV:  lo_out = a / b (quociente), hi_out = a % b (resto)
   ```

2. **Top-level** — adicionar registradores `hi_reg` e `lo_reg` fora do register file:
   ```verilog
   reg [31:0] hi_reg, lo_reg;
   always @(posedge clk) begin
       if (rst) begin hi_reg <= 0; lo_reg <= 0; end
       else if (isMult || isDiv) begin
           hi_reg <= alu_hi;
           lo_reg <= alu_lo;
       end
   end
   ```

3. **Leitura de $hi/$lo** — interceptar as saídas do register file:
   ```verilog
   wire [31:0] read_a = (rf_rs1 == 6'd61) ? lo_reg :
                         (rf_rs1 == 6'd62) ? hi_reg : rf_a;
   wire [31:0] read_b = (rf_rs2 == 6'd61) ? lo_reg :
                         (rf_rs2 == 6'd62) ? hi_reg : rf_b;
   ```

4. **Control unit** — para MULT/DIV, desabilitar `regWrite` (não escrever RD=0):
   ```verilog
   // MULT: regDst=1, regWrite=0, aluOp=4'd8, isMultDiv=1
   // DIV:  regDst=1, regWrite=0, aluOp=4'd9, isMultDiv=1
   ```
   Adicionar sinal `isMultDiv` à control unit.

### 1.6 Inicialização de $gp e $sp

**Arquivo:** `regfile64.v`

**Problema:** No reset, todos os registradores são zerados. Mas $gp (reg 28) deve ser 0 (OK, já é) e $sp (reg 29) deve ser 1023.

**Correção:**
```verilog
always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < (1<<ADDR_W); i = i + 1) rf[i] <= 0;
        rf[29] <= 32'd1023;  // $sp = topo da pilha
    end else if (we && rd != 0) begin
        rf[rd] <= wd;
    end
end
```

### 1.7 ROM — latência de 1 ciclo

**Arquivo:** `single_port_rom.v`

**Problema:** A ROM tem saída registrada (`always @(posedge clk) data <= rom[addr]`). Isso significa que a instrução só está disponível **1 ciclo após** o PC ser atualizado. Em um processador monociclo, a instrução deve estar disponível **no mesmo ciclo**.

**Correção — usar leitura combinacional:**
```verilog
// ANTES (registrada):
always @(posedge clk) data <= rom[addr];

// DEPOIS (combinacional):
assign data = rom[addr];
```

**Nota:** Se necessário para timing na FPGA, manter a ROM registrada e ajustar o datapath. Porém, para um monociclo puro, a leitura combinacional é o correto.

---

## Fase 2 — Instruções de I/O (IN e OUT)

### 2.1 Sinal de controle para IN e OUT

**Arquivo:** `control_unit.v`

**Problema:** IN (opcode 26 = 6'b011010) e OUT (opcode 27 = 6'b011011) caem no `default` da control unit — nenhum sinal é ativado. IN precisa de `regWrite=1` para gravar no registrador, e OUT precisa de um sinal `isOut` para capturar o valor.

**Correção:**
```verilog
6'b011010: begin regWrite=1; isIn=1; end               // IN
6'b011011: begin isOut=1; end                            // OUT
```

Adicionar sinais `isIn` e `isOut` à interface da control unit.

### 2.2 Lógica de IN no top-level

**Arquivo:** `Processador_GUI_MIPS.v`

IN lê um valor externo (switches da FPGA) e grava no registrador `Reg` (bits [25:20]).

```verilog
wire [31:0] input_value = {14'b0, SW[17:0]};  // 18 bits dos switches, zero-extended

// No write-back mux:
wire [31:0] rf_wd = jal  ? pc_plus1 :
                    isIn  ? input_value :
                    memToReg ? data_rd :
                    alu_y;
```

**Sincronização:** A instrução IN no compilador é usada para leitura de valores do usuário. Na FPGA, o valor dos switches deve ser capturado quando IN executa. Opcionalmente, pode-se usar um botão `enter` (KEY[1]) com debounce para confirmar a entrada, pausando o processador até que o botão seja pressionado.

### 2.3 Lógica de OUT no top-level

**Arquivo:** `Processador_GUI_MIPS.v`

OUT envia o valor do registrador `Reg` (bits [25:20]) para o display.

```verilog
reg [31:0] out_reg;
always @(posedge clk) begin
    if (rst) out_reg <= 32'd0;
    else if (isOut) out_reg <= rf_a;  // rf_a lê reg[field_25_20] quando isOut
end
```

### 2.4 Display de 7 segmentos

**Arquivo:** `Processador_GUI_MIPS.v`

**Problema:** Atualmente os HEX0–HEX5 mostram apenas o PC. Devem mostrar o valor de `out_reg` (resultado de OUT).

**Correção:** Conectar os displays ao `out_reg`:
```verilog
hex7seg h0 (.hex(out_reg[ 3: 0]), .seg(HEX0));
hex7seg h1 (.hex(out_reg[ 7: 4]), .seg(HEX1));
hex7seg h2 (.hex(out_reg[11: 8]), .seg(HEX2));
hex7seg h3 (.hex(out_reg[15:12]), .seg(HEX3));
hex7seg h4 (.hex(out_reg[19:16]), .seg(HEX4));
hex7seg h5 (.hex(out_reg[23:20]), .seg(HEX5));
```

Opcionalmente, usar KEY[2] ou SW[17] para alternar entre exibir o `out_reg` e o `PC` (para debug).

### 2.5 Debounce e clock

**Arquivos:** `debounce.v`, `divisor_freq.v`

Estes módulos existem mas não são usados. Devem ser instanciados no top-level:
- **debounce** para KEY[0] (reset) e KEY[1] (enter/step)
- **divisor_freq** se quisermos execução em velocidade visível (step mode) para debug

---

## Fase 3 — Ajustes na Unidade de Controle

### 3.1 Novos sinais de controle

**Arquivo:** `control_unit.v`

Adicionar à interface:

| Sinal | Tipo | Uso |
|-------|------|-----|
| `isIn` | output | IN: seleciona valor dos switches no write-back mux |
| `isOut` | output | OUT: habilita captura do valor no registrador de saída |
| `isMultDiv` | output | MULT/DIV: habilita escrita em $hi/$lo |

### 3.2 MULT/DIV — desabilitar regWrite

**Problema atual:** MULT/DIV têm `regWrite=1` e `regDst=1`, mas RD=0 no binário. O check `rd != 0` no register file evita que $zero seja sobrescrito, mas `regWrite` deveria ser 0 para clareza e o sinal `isMultDiv` deveria controlar a escrita em $hi/$lo.

**Correção:**
```verilog
6'b000100: begin regDst=1; aluOp=4'd8; isMultDiv=1; end  // MULT (sem regWrite)
6'b000110: begin regDst=1; aluOp=4'd9; isMultDiv=1; end  // DIV  (sem regWrite)
```

### 3.3 MOVE — aluOp incorreto

**Problema:** MOVE usa `aluOp=4'd0` (ADD), mas deveria usar `aluOp=4'hA` (PASS: y = a). Com ADD e `aluSrc=0`, a ALU calcula `reg[RS] + reg[RT]` em vez de apenas `reg[RS]`.

**Correção:**
```verilog
6'b010110: begin regWrite=1; aluOp=4'hA; end  // MOVE (PASS: y = a = reg[RS])
```

### 3.4 NOT — aluOp incorreto

**Problema:** NOT usa `aluOp=4'd10` (= 4'hA = PASS), mas deveria usar `aluOp=4'h4` (NOT: y = ~a).

**Correção:**
```verilog
6'b001100: begin aluSrc=1; regWrite=1; aluOp=4'h4; end  // NOT (y = ~RS)
```

**Nota:** `aluSrc=1` faz a ALU receber imediato no input B, mas como NOT só usa `a` (y = ~a), isso não importa. O importante é que `rf_rs1` aponte para RS (bits[19:14]), o que é o caso quando `regDst=0`.

### 3.5 SR/SL — mapeamento de aluOp

**Problema:** A CU mapeia SR→aluOp=7 e SL→aluOp=6, mas a ALU tem SLL=5 e SRL=6. Além disso, SLT usa aluOp=5 na CU mas o slot 7 na ALU. Há um conflito.

**Alinhar CU ↔ ALU:**

| Instrução | Opcode CU | aluOp (proposto) | ALU op | Operação |
|-----------|-----------|-------------------|--------|----------|
| ADD | 0 | 4'h0 | 4'h0 | a + b |
| SUB | 2 | 4'h1 | 4'h1 | a - b |
| AND | 8 | 4'h2 | 4'h2 | a & b |
| OR | 10 | 4'h3 | 4'h3 | a \| b |
| NOT | 12 | 4'h4 | 4'h4 | ~a |
| SLT | 25 | 4'h5 | 4'h5 | (a < b) ? 1 : 0 |
| SL | 14 | 4'h6 | 4'h6 | a << shamt |
| SR | 13 | 4'h7 | 4'h7 | a >> shamt |
| MULT | 4 | 4'h8 | 4'h8 | {hi,lo} = a * b |
| DIV | 6 | 4'h9 | 4'h9 | lo=a/b, hi=a%b |
| PASS | (MOVE) | 4'hA | 4'hA | y = a |

**Ação:** Verificar e alinhar os valores de aluOp na CU com as operações na ALU conforme a tabela acima.

---

## Fase 4 — Revisão do módulo `DataOutput.v`

**Arquivo:** `DataOutput.v`

### 4.1 Incompatibilidade de nomes de portas

O módulo instancia `Hex7Seg` com porta `.nibble(...)`, mas o módulo `hex7seg.v` define a porta como `.hex(...)`. Isso causará erro de compilação.

**Correção:** Renomear `.nibble(...)` para `.hex(...)` em todas as instâncias, ou vice-versa.

### 4.2 Decisão de uso

Se optarmos por usar o módulo `DataOutput` no top-level para exibir o valor de OUT, ele precisa:
- Receber um `enable` (sinal `isOut`) para capturar o valor apenas quando OUT executa
- Ter os nomes de portas alinhados com `hex7seg`

**Alternativa:** Implementar a lógica de saída diretamente no top-level (como descrito na Fase 2.3/2.4) e não usar `DataOutput.v`.

---

## Fase 5 — Testbench e Validação

### 5.1 Criar testbench completo

**Novo arquivo:** `tb_processador.v`

Testbench que:
1. Instancia o top-level com clock de 50 MHz simulado
2. Aplica reset
3. Roda o programa da ROM até HLT
4. Verifica o valor de saída (OUT) contra o esperado

### 5.2 Ordem de testes (complexidade crescente)

| # | Programa | Instruções testadas | Resultado esperado |
|---|----------|--------------------|--------------------|
| 1 | `teste2.txt` | ADD, ADDI, LW, SW, OUT, HLT, J | output = 8 |
| 2 | `teste.txt` | + IN | output = soma dos inputs |
| 3 | `fatorial.txt` | + SLT, BEQ, MULT, MOVE, SUB | output = 120 |
| 4 | `gcd.txt` | + JAL, JR, DIV, recursão | output = MDC dos inputs |
| 5 | `sort.txt` | + múltiplas funções, arrays, pilha | output = valores ordenados |

### 5.3 Checklist de validação por teste

Para cada programa, verificar:
- [ ] PC avança corretamente (de 1 em 1)
- [ ] Instruções são decodificadas corretamente
- [ ] Valores corretos são escritos nos registradores
- [ ] Memória de dados é acessada nos endereços corretos
- [ ] Branches/jumps vão para o endereço correto
- [ ] Valor de OUT é o esperado

---

## Fase 6 — Integração FPGA

### 6.1 Clock e step mode

- Usar `divisor_freq` para gerar clock lento (1 Hz) para debug visual
- Usar KEY[3] como seletor: clock real (50 MHz) vs clock lento
- Ou: usar KEY[1] como botão de step (avanço manual, 1 instrução por pressão)

### 6.2 Debounce

- Instanciar `debounce` para todos os botões usados (KEY[0] reset, KEY[1] enter/step)

### 6.3 Display

- HEX0–HEX5: valor de `out_reg` (resultado de OUT)
- LEDR[17:0]: SW[17:0] em modo normal, ou PC/instrução em modo debug
- Opcionalmente: usar KEY[2] para alternar exibição entre PC e output

### 6.4 Pin assignments

- Verificar que o `.qsf` tem os pinos corretos para a placa alvo (DE2-115 ou similar)
- Confirmar que SW[17:0], KEY[3:0], HEX0–HEX5 e LEDR estão mapeados

---

## Resumo das alterações por arquivo

| Arquivo | Alterações |
|---------|-----------|
| `Processador_GUI_MIPS.v` | Corrigir wires indefinidos; refazer lógica de rf_rs1/rs2/writeReg; corrigir endereço da RAM (word addr); adicionar $hi/$lo; adicionar IN/OUT; conectar displays; instanciar debounce; adicionar lógica de clock |
| `control_unit.v` | Adicionar sinais isIn, isOut, isMultDiv; corrigir MULT/DIV (regWrite=0); corrigir MOVE (aluOp=4'hA); corrigir NOT (aluOp=4'h4); alinhar SR/SL; adicionar cases IN/OUT |
| `alu.v` | Adicionar porta shamt; corrigir SLL/SRL para usar shamt; adicionar saídas hi_out/lo_out para MULT/DIV; alinhar op codes com CU |
| `regfile64.v` | Adicionar inicialização $sp=1023 no reset |
| `single_port_rom.v` | Mudar leitura para combinacional (sem registro) |
| `data_ram.v` | Sem alteração estrutural (verificar apenas conexão no top-level) |
| `sign_extend.v` | OK — sem alteração |
| `mux2.v` | OK — sem alteração (pode ser usado em refatorações) |
| `hex7seg.v` | OK — sem alteração |
| `DataOutput.v` | Corrigir nomes de portas ou descontinuar uso |
| `debounce.v` | OK — sem alteração (instanciar no top-level) |
| `divisor_freq.v` | OK — sem alteração (instanciar no top-level) |
| `tb_processador.v` | **NOVO** — testbench completo |

---

## Ordem de execução

```
Fase 0  ──→  Fase 1  ──→  Fase 3  ──→  Fase 2  ──→  Fase 4  ──→  Fase 5  ──→  Fase 6
(compilar)   (datapath)   (controle)   (I/O)        (display)    (teste)      (FPGA)
```

As Fases 1 e 3 são interdependentes (mudanças na CU afetam o datapath e vice-versa) e devem ser feitas juntas. A Fase 5 (testes) deve começar logo após a Fase 2, usando `teste2.txt` como primeiro programa de validação.
