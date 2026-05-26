# Plano de Revisão — Processador MIPS-Lite

Documento de referência: `CONTEXTO_PROCESSADOR.md` (especificação autoritativa da ISA e microarquitetura).

> **Status:** A maior parte das correções de datapath, control unit, ALU e I/O já foi aplicada. Após uma nova varredura completa do RTL, listamos abaixo, em ordem de severidade, os pontos em que o processador **ainda pode falhar** ou divergir da spec.

---

## Visão geral dos problemas restantes

Há **dois pontos críticos** que podem fazer o processador não funcionar como esperado na placa (inicialização de `$sp` e inferência da ROM/RAM como BRAM síncrona pela Quartus), além de pequenas divergências da spec (MULTI/DIVI, ANDI/ORI), inconsistências de documentação (binários do `gcd.txt` divergem dos exemplos do `CONTEXTO_PROCESSADOR.md`) e cleanups.

---

## Fase 0 — Achados da varredura (NOVO)

### 0.1 [CRÍTICO] `$sp` pode ficar em 0 no power-on (regfile depende de reset manual)

**Arquivos:** `regfile64.v` (linhas 19-26), `Processador_GUI_MIPS.v` (linhas 62-67)

O regfile só inicializa `rf[29] = 1023` **dentro do bloco `if (rst)`**:

```19:26:processadorMipsLite/regfile64.v
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < (1<<ADDR_W); i = i + 1) rf[i] <= {DATA_W{1'b0}};
            rf[29] <= 32'd1023;  // $sp inicia no topo da RAM
        end else if (we && rd != 0) begin       // $0 permanece zero
            rf[rd] <= wd;
        end
    end
```

Logo após o power-on do FPGA, os FFs do sincronizador (`rst_sync_0`, `rst_sync_1`) defaultam para 0 (default do Quartus), então `rst` nunca sobe sozinho. Como o `pc` também defaulta a 0, o processador **começa a executar** a primeira instrução com `$sp = 0` (em vez de 1023).

Programas como `gcd.cms`/`sort.cms` que fazem `addi $sp,$sp,-1` + `sw $ra,0($sp)` logo de cara escrevem na palavra 1023/-1 truncada em 10 bits, e do segundo push em diante batem em endereços onde estão variáveis globais do `$gp`, corrompendo dados.

**Mitigações possíveis (escolher uma):**

1. Acrescentar um `initial` block ao regfile (suportado pela Quartus em targets Cyclone IV):
   ```verilog
   initial begin
       integer j;
       for (j = 0; j < (1<<ADDR_W); j = j + 1) rf[j] = {DATA_W{1'b0}};
       rf[29] = 32'd1023;
   end
   ```
2. Implementar um power-on reset (POR): contador no domínio `CLOCK_50` que mantém `rst_db = 1` durante, por exemplo, os primeiros ~10 ms após o release do `nstatus`/configuração; depois liberar normalmente.
3. (Workaround operacional) deixar bem documentado que o usuário **precisa pressionar `KEY[0]` antes de qualquer execução**. Frágil — basta esquecer uma vez e a demonstração falha.

A opção (1) é a mais robusta e tem menor custo de hardware.

### 0.2 [CRÍTICO] ROM e RAM podem ser inferidas como BRAM síncrona pela Quartus

**Arquivos:** `single_port_rom.v` (linhas 10-14), `data_ram.v` (linhas 16-23)

Ambas usam leitura combinacional (`assign data = rom[addr]` / `assign rdata_a = mem[addr_a]`). O design assume essa leitura como **assíncrona** — o PC muda no posedge, e na mesma borda o `instr` já reflete `rom[pc_next]`. Se a Quartus mapear a memória para um M9K (BRAM) — comportamento legítimo para arrays grandes — o read fica **registrado** e o `instr` chega 1 ciclo atrasado, dessincronizando PC↔ROM. Programa não roda.

**Como verificar:** após `Analysis & Synthesis`, no relatório `Compilation Report → Resource Utilization → RAM Summary`, conferir se `ROM`/`DRAM` aparecem como M9K. Se sim, ou:

- Forçar uso de lógica/MLAB: declarar `(* ramstyle = "logic" *) reg [DATA_W-1:0] rom [...]` nos dois módulos; ou
- Migrar o pipeline para tolerar 1 ciclo de latência na busca (registrar `pc` antes do índice do ROM e ajustar PC+1, branches, jumps e stalls em conformidade — mudança grande).

Para um processador monociclo do tamanho desse projeto, a opção `ramstyle = "logic"` é mais barata.

### 0.3 [IMPORTANTE — spec] `MULTI`/`DIVI` divergem da ISA na control unit

**Arquivo:** `control_unit.v` (linhas 43-44)

```43:44:processadorMipsLite/control_unit.v
            6'b000101: begin aluSrc=1; regWrite=1; aluOp=4'd8; end   // MULTI
            6'b000111: begin aluSrc=1; regWrite=1; aluOp=4'd9; end   // DIVI
```

A spec (`CONTEXTO_PROCESSADOR.md` §3.1) diz que `MULTI`/`DIVI` produzem `{$hi,$lo} ← RS × signext(Imm)` (idêntico a `MULT`/`DIV`, sem RD destino). Aqui eles estão como `regWrite=1` (escrevem em RD do F2) e **não** setam `isMultDiv`, então `$hi`/`$lo` nunca são atualizados.

Nenhum dos testes atuais (`teste2`, `teste`, `fatorial`, `gcd`, `sort`) usa MULTI/DIVI, então isso **não trava** a validação inicial — mas viola a spec.

**Correção sugerida:**

```verilog
6'b000101: begin aluSrc=1; isMultDiv=1; aluOp=4'd8; end // MULTI
6'b000111: begin aluSrc=1; isMultDiv=1; aluOp=4'd9; end // DIVI
```

### 0.4 [IMPORTANTE — spec] `ANDI`/`ORI` usam sign-extend em vez de zero-extend

**Arquivos:** `control_unit.v` (linhas 45-46), `Processador_GUI_MIPS.v` (linhas 129-133)

A spec (`CONTEXTO_PROCESSADOR.md` §3.1) define `ANDI`/`ORI` como `RD ← RS & zeroext(Imm)` / `RD ← RS | zeroext(Imm)`. Mas no top-level só existe **um** `sign_extend` para todos os imediatos de 14 bits, então quando o bit 13 do imediato é 1 (imediato negativo em complemento-2), o resultado fica preenchido com 1s nos 18 bits altos, divergindo da spec.

Os programas de teste atuais não usam `ANDI`/`ORI` com imediato negativo, então não falha agora. Para deixar conforme a spec:

- Criar um segundo sinal `immExtZ = {18'b0, imm14}` e selecionar `imm_final = (is_andi | is_ori) ? immExtZ : immExt`; ou
- Expor `is_andi`/`is_ori` na CU e fazer a seleção no top-level.

### 0.5 [DOC] `CONTEXTO_PROCESSADOR.md` diverge do `gcd.txt` real

**Arquivos:** `context/CONTEXTO_PROCESSADOR.md` (§6.1, §6.2, §7.1, §7.2, §8.1, §8.2, §10.1, §10.2, §11), `gcd.txt`

Os exemplos de binário com a anotação "(gcd.txt, addr N)" no contexto **não batem** com as linhas correspondentes do `gcd.txt` atualmente versionado:

| Exemplo (CONTEXTO §6.1, addr 0) | Esperado pelo doc | Linha 1 do `gcd.txt` |
|---------------------------------|-------------------|----------------------|
| `j main`                        | `01000100000000000000000000100110` (J 38) | `00111101000111001111111111111110` (LW $r17, -2($r51)) |

A primeira linha do arquivo decodifica como `LW` com base `$r51`, registrador que não consta da convenção de uso (§4.1). Várias outras linhas (`gcd.txt:7`, `:16` etc.) também decodificam para opcodes/regs incompatíveis com a descrição que o `CONTEXTO_PROCESSADOR.md` faz daqueles endereços.

Provável causa: o `gcd.txt` foi gerado por uma versão atualizada do encoder e o `CONTEXTO_PROCESSADOR.md` ficou desatualizado. **Não é bug do processador**, mas qualquer revisor que tente "validar à mão" usando os exemplos do contexto vai concluir, erroneamente, que o RTL está quebrado.

**Ação:** rodar o encoder atual contra os `.cms` de referência e regerar a seção §6/§7/§8 do `CONTEXTO_PROCESSADOR.md` com binários reais — ou então confirmar que o `gcd.txt` versionado deveria ser regenerado.

### 0.6 [DOC] Faltam os outros arquivos de teste no repositório

Buscando `**/*.txt` no projeto, só existe `gcd.txt`. Os demais (`teste2.txt`, `teste.txt`, `fatorial.txt`, `sort.txt`) referenciados em §14 do `CONTEXTO_PROCESSADOR.md` e na Fase 2.2 deste plano **não estão versionados**.

Além disso, `single_port_rom.v` tem `parameter FILENAME = "gcd.txt"` e o top-level instancia a ROM sem sobrescrever o parâmetro:

```94:98:processadorMipsLite/Processador_GUI_MIPS.v
    single_port_rom #(.ADDR_W(10), .FILENAME("gcd.txt")) ROM (
        .clk  (clk_cpu),
        .addr (pc[9:0]),                // PC em endereço de palavra (CONTEXTO §1)
        .data (instr)
    );
```

Para alternar entre programas, é preciso editar o `.FILENAME(...)` na instanciação **ou** renomear o `.txt` desejado para `gcd.txt`. Trocar isso por uma macro `\`define ROM_FILE "..."` (ou um parâmetro top-level) deixa a alternância mais limpa.

### 0.7 [MENOR] `SDC` esqueceu de `HEX6` na lista de false-paths

**Arquivo:** `Processador_GUI_MIPS.sdc` (linha 44)

```44:44:processadorMipsLite/Processador_GUI_MIPS.sdc
set_false_path -from * -to [get_ports {HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*]}]
```

O top-level usa `HEX0..HEX6`, mas o `set_false_path` só lista até `HEX5`. O TimeQuest vai exigir caminho determinístico para `HEX6`. Como o display sai direto do registrador `out_reg` por uma `hex7seg` combinacional, e `clk_cpu` é ~2 Hz, não há problema prático, mas é inconsistente.

**Fix:** acrescentar `HEX6[*]` à lista.

### 0.8 [MENOR] `single_port_rom.clk` declarado e não usado

**Arquivo:** `single_port_rom.v` (linha 6)

A porta `clk` da ROM está declarada mas a leitura é puramente combinacional (`assign data = rom[addr]`). Não causa bug, mas leva a warnings de "input port unused" na compilação. Remover a porta (e ajustar a instanciação no top-level) elimina o warning e deixa explícito que a ROM é assíncrona — o que conversa com 0.2.

### 0.9 [MENOR] HEX6 mostra apenas bits [27:24] do `out_reg`

**Arquivo:** `Processador_GUI_MIPS.v` (linhas 258-264)

```258:264:processadorMipsLite/Processador_GUI_MIPS.v
    hex7seg h0 (.hex(out_reg[ 3: 0]), .seg(HEX0));
    ...
    hex7seg h6 (.hex(out_reg[27:24]), .seg(HEX6));
```

São 7 displays × 4 bits = 28 bits exibidos. Os bits `out_reg[31:28]` não vão para nenhum lugar. Para os testes atuais, em que o output cabe em <= 24 bits, não é um problema, mas valores > 2²⁸ vão truncar silenciosamente no display. Se isso for relevante, ou se aceita a perda dos 4 bits altos ou se converte o display para mostrar o nibble alto piscando.

### 0.10 [MENOR] `enter_pulse` amostra `SW[9:0]` assíncrono no ciclo do write-back

**Arquivo:** `Processador_GUI_MIPS.v` (linhas 75-86, 139-141)

`in_data = {22'b0, SW[9:0]}` vai direto do pino para o regfile no ciclo em que `in_writeEn = 1`. `SW[9:0]` não tem CDC. Em laboratório isso quase sempre funciona (chaves não bouncam tanto e o usuário aperta `KEY[1]` só depois de posicionar), mas é uma pequena fonte de não-determinismo. Idealmente, amostrar `SW[9:0]` num registrador no `clk_cpu` antes de gravar no banco.

---

## Fase 1 — Pequenos cleanups no top-level

### 1.1 Dead code: `input_value`

**Arquivo:** `Processador_GUI_MIPS.v` (linha 196)

```verilog
wire [31:0] input_value = {14'b0, SW[17:0]};
```

Esse wire é declarado mas o write-back do IN realmente usa `in_data = {22'b0, SW[9:0]}` (linha 130). Como o `LEDR[9:0]` ecoa apenas `SW[9:0]`, a versão de 18 bits virou código morto.

**Ação:** remover a linha (ou, se a intenção for ler 18 bits, alinhar `in_data`, `LEDR` e o comentário do IN para 18 bits).

---

## Fase 2 — Testbench e validação (Fase 5 antiga)

Não existe nenhum `tb_*.v` no repositório (`Glob tb_*.v` → 0 arquivos). A criação do testbench foi adiada e ainda precisa ser feita.

### 2.1 Criar testbench básico

**Novo arquivo:** `tb_processador.v`

Testbench que:

1. Instancia o top-level `Processador_GUI_MIPS` com clock simulado.
2. Aplica reset.
3. Roda o programa da ROM até `HLT`.
4. Verifica via `$display` o conteúdo do `out_reg` (e/ou de registradores específicos) ao final.

> Para simulação, lembrar que o top-level usa `clk_cpu` derivado de `CLOCK_50` via `divisor_Freq #(.DIV(12_500_000))`. No testbench, ou se reduz `DIV` por meio de override de parâmetro, ou se gera `CLOCK_50` direto a uma frequência conveniente.

### 2.2 Ordem de testes (complexidade crescente)

| # | Programa | Instruções testadas | Resultado esperado |
|---|----------|--------------------|--------------------|
| 1 | `teste2.txt` | ADD, ADDI, LW, SW, OUT, HLT, J | output = 8 |
| 2 | `teste.txt` | + IN | output = soma dos inputs |
| 3 | `fatorial.txt` | + SLT, BEQ, MULT, MOVE, SUB | output = 120 |
| 4 | `gcd.txt` | + JAL, JR, DIV, recursão | output = MDC dos inputs |
| 5 | `sort.txt` | + múltiplas funções, arrays, pilha | valores ordenados |

### 2.3 Checklist de validação por programa

- [ ] PC avança corretamente (de 1 em 1, endereçamento por palavra)
- [ ] Instruções são decodificadas (control unit gera os sinais esperados)
- [ ] Valores corretos são escritos nos registradores (incluindo `$hi`/`$lo` em MULT/DIV)
- [ ] Memória de dados é acessada nos endereços corretos (palavra, não byte)
- [ ] Branches/jumps vão para o endereço correto
- [ ] `out_reg` recebe o valor esperado em cada `OUT`

---

## Fase 3 — Integração FPGA (Fase 6 antiga)

A maioria já está pronta:

- `divisor_Freq #(.DIV(12_500_000))` para gerar `clk_cpu` ~2 Hz: **OK**
- `Debounce` em KEY[0] (reset) e KEY[1] (enter do IN) com sincronizador 2-FF para CDC: **OK**
- HEX0–HEX5 conectados a `out_reg`: **OK** (HEX6 também; verificar se faz sentido para a placa)
- `LEDR[9:0]` ecoa `SW[9:0]`, `LEDR[16] = halt`, `LEDR[17] = stall_in`: **OK**

### 3.1 Pin assignments

**Arquivo:** `Processador_GUI_MIPS.qsf`

O `.qsf` já tem 90 `set_location_assignment`. Antes de programar a placa, **reconferir** que cobrem:

- `CLOCK_50`
- `KEY[0]` (reset) e `KEY[1]` (enter do IN)
- `SW[17:0]` (mesmo que só `SW[9:0]` seja efetivamente usado)
- `HEX0`–`HEX6`
- `LEDR[17:0]`

Se algum desses estiver faltando ou apontar para o pino errado da DE2-115, ajustar antes de gerar o `.sof`.

### 3.2 Frequência do `clk_cpu`

`DIV=12_500_000` dá ~2 Hz (período de ~1 s). Bom para debug visual no laboratório, mas lento demais para rodar `sort.txt` por inteiro durante a apresentação. Se necessário, expor `DIV` por uma chave (`SW`) ou criar dois domínios selecionáveis (lento para debug, rápido para demo).

---

## Resumo das alterações ainda pendentes

| Arquivo | Alterações restantes | Origem |
|---------|---------------------|--------|
| `regfile64.v` | Adicionar `initial` block que zera `rf[*]` e seta `rf[29]=1023` (ou implementar POR no top-level) | Fase 0.1 (CRÍTICO) |
| `single_port_rom.v` + `data_ram.v` | Adicionar `(* ramstyle = "logic" *)` à declaração do array para impedir a Quartus de inferir BRAM síncrona | Fase 0.2 (CRÍTICO) |
| `control_unit.v` | `MULTI`/`DIVI`: trocar `regWrite=1` por `isMultDiv=1` (alinhar com `MULT`/`DIV`) | Fase 0.3 |
| `control_unit.v` + top-level | `ANDI`/`ORI`: usar zero-extend em vez de sign-extend para o imediato | Fase 0.4 |
| `CONTEXTO_PROCESSADOR.md` | Regenerar os exemplos binários (§6–§11) com o encoder atual, ou regerar `gcd.txt` para casar com os exemplos | Fase 0.5 |
| Diretório do projeto | Versionar `teste2.txt`, `teste.txt`, `fatorial.txt`, `sort.txt`; trocar `FILENAME` da ROM por define/parâmetro top-level | Fase 0.6 |
| `Processador_GUI_MIPS.sdc` | Acrescentar `HEX6[*]` ao `set_false_path` de saída | Fase 0.7 |
| `single_port_rom.v` | Remover porta `clk` não usada (e ajustar instanciação) | Fase 0.8 |
| `Processador_GUI_MIPS.v` | Remover `wire input_value` (linha 196) que ficou como código morto | Fase 1.1 |
| `tb_processador.v` | **Criar** testbench cobrindo `teste2.txt` → `gcd.txt` → `sort.txt` | Fase 2.1 |
| `Processador_GUI_MIPS.qsf` | Reconferir pinos de KEY[1], SW, HEX0–HEX6 e LEDR | Fase 3.1 |

Tudo o que já estava na ISA e datapath (rf_rs1/rs2/writeReg, endereçamento word da RAM, ALU com `shamt`, `hi_out`/`lo_out`, alinhamento CU↔ALU, init de `$sp` via reset, ROM combinacional, IN/OUT, debounce, displays de OUT, `sign_extend` instanciado, `isMultDiv` declarado, wires de 32 bits explícitos) **continua correto** e não precisa de novas mudanças. As pendências da Fase 0 são complementares.

---

## Ordem de execução sugerida

```
Fase 0 (críticos: $sp + ramstyle)  ──→  Fase 1 (cleanup)  ──→  Fase 2 (testbench)  ──→  Fase 3 (FPGA)
```

A Fase 0 ataca primeiro o que de fato pode impedir o processador de rodar (inicialização do `$sp` no power-on e inferência da ROM/RAM como BRAM). Sem elas, a Fase 2 e a Fase 3 podem dar resultados confusos e a "culpa" será atribuída ao datapath, que já está correto. As demais Fases seguem inalteradas.
