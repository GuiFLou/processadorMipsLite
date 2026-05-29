# Plano de Revisão — Processador MIPS-Lite

Documento de referência: `CONTEXTO_PROCESSADOR.md` (especificação autoritativa da ISA e microarquitetura).

> **Status:** A maior parte das correções de datapath, control unit, ALU e I/O já foi aplicada. Este documento agora separa **bugs/riscos que podem fazer o processador não funcionar conforme o propósito** (seção nova abaixo) dos **próximos passos** (testbench e FPGA).

---

## Visão geral

O datapath monociclo está, em sua maior parte, correto para os 5 programas-alvo. Restam, porém, alguns **riscos reais de funcionamento** (alguns bloqueiam a validação, outros violam a ISA em instruções ainda não exercitadas) que precisam ser conferidos antes de confiar no processador. Eles estão listados na seção **"Issues que podem impedir o funcionamento"**. Em seguida vêm os próximos passos já planejados (testbench e integração FPGA).

> Observação: o cleanup do `wire input_value` citado na antiga Fase 1 **já foi feito** — esse wire não existe mais em `Processador_GUI_MIPS.v` (só sobrou a menção neste documento). Os 90 `set_location_assignment` do `.qsf` cobrem `CLOCK_50`, `KEY[0..3]`, `SW[0..17]`, `HEX0..HEX6` e `LEDR[17:0]`.

---

## Issues que podem impedir o funcionamento

Ordenadas por severidade. Referências de arquivo:linha apontam para o estado atual do código.


### 🟡 Bugs latentes (não exercitados pelos 5 testes, mas violam a ISA)

#### I6. `MULTI`/`DIVI` (F2) escrevem no regfile em vez de `$hi`/`$lo`

**Arquivo:** `control_unit.v:43-44`

```verilog
6'b000101: begin aluSrc=1; regWrite=1; aluOp=4'd8; end   // MULTI
6'b000111: begin aluSrc=1; regWrite=1; aluOp=4'd9; end   // DIVI
```

Pela ISA (`CONTEXTO §3.1`), MULTI/DIVI devem fazer `{Hi,Lo} ← RS ×/÷ signext(Imm)` — ou seja, **`isMultDiv=1` e `regWrite=0`**, igual a MULT/DIV. Do jeito atual, eles ligam `regWrite` e gravam `y=lo_out` diretamente num registrador, sem atualizar `$hi`/`$lo`.

- **Impacto:** nenhum nos 5 testes (não usam MULTI/DIVI), mas é uma divergência de ISA que quebraria qualquer programa que os use.
- **Ação:** trocar para `begin aluSrc=1; isMultDiv=1; aluOp=4'd8/9; end`.

#### I7. `ANDI`/`ORI` usam extensão de sinal em vez de extensão com zero

**Arquivos:** `control_unit.v:45-46` (ANDI/ORI) usam o mesmo `immExt`, e `Processador_GUI_MIPS.v:129-133` instancia um único `sign_extend`.

A ISA (`CONTEXTO §3.1`) define `ANDI`/`ORI` com `zeroext(Imm)`. Com sign-extend, um imediato com bit 13 = 1 vira `0xFFFFxxxx`, corrompendo o AND/OR.

- **Impacto:** nenhum nos 5 testes; latente.
- **Ação:** gerar uma versão zero-estendida do imediato e selecioná-la para ANDI/ORI (ou tratar no decode).

### 🔵 Riscos de simulação / robustez

#### I9. Memórias sem reset/inicialização garantida em simulação

`data_ram.v` não tem reset (a RAM nasce `X` em simulação) e o `regfile64` só zera no `rst`. O compilador sempre escreve antes de ler as variáveis, então em execução real funciona, mas um testbench precisa **aplicar reset** e, idealmente, inicializar a RAM para evitar `X` propagando.

#### I10. `$readmemb` depende do arquivo no diretório de trabalho

`single_port_rom.v:12` usa `$readmemb(FILENAME, rom)` com caminho relativo. Em simulação, o `.txt` precisa estar no diretório onde o simulador roda (ou usar caminho absoluto). Conferir ao montar o testbench.

---

## Fase 2 — Testbench e validação (Fase 5 antiga)

Não existe nenhum `tb_*.v` no repositório (`Glob tb_*.v` → 0 arquivos). A criação do testbench foi adiada e ainda precisa ser feita.

> **Pré-requisito (issue I1):** dos binários abaixo, apenas `gcd.txt` existe no repositório. Antes de rodar a sequência completa, é preciso gerar `teste2.txt`, `teste.txt`, `fatorial.txt` e `sort.txt` com o compilador.

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

## Resumo das issues e pendências

| ID | Severidade | Arquivo:linha | Resumo |
|----|-----------|---------------|--------|
| I1 | 🔴 | (repo) | Faltam `teste2/teste/fatorial/sort.txt`; só `gcd.txt` existe |
| I2 | 🔴 | `Processador_GUI_MIPS.v:94` | `FILENAME` da ROM fixo em `"gcd.txt"` |
| I3 | 🟠 | `regfile64.v:19-26` | `$sp`/PC só corretos após reset (sem power-on init) |
| I4 | 🟠 | `Processador_GUI_MIPS.v:62-67` | Reset síncrono ao `clk_cpu` lento + debounce |
| I5 | ✅ | `Processador_GUI_MIPS.v`, `bin32_to_bcd7.v` | Saída decimal nos displays (conversão binário→BCD) |
| I6 | 🟡 | `control_unit.v:43-44` | MULTI/DIVI gravam no regfile em vez de `$hi`/`$lo` |
| I7 | 🟡 | `control_unit.v:45-46` | ANDI/ORI usam sign-extend em vez de zero-extend |
| I8 | 🟡 | `Processador_GUI_MIPS.v:140` | IN lê só `SW[9:0]` (máx. 1023) |
| I9 | 🔵 | `data_ram.v` | RAM sem reset → `X` em simulação |
| I10 | 🔵 | `single_port_rom.v:12` | `$readmemb` com caminho relativo |
| I11 | ✅ | `Processador_GUI_MIPS.qsf` | Arquivos mortos removidos e `.qsf` limpo |
| — | pendência | `tb_processador.v` | **Criar** testbench cobrindo `teste2.txt` → `gcd.txt` → `sort.txt` |

Tudo o que já estava na ISA e datapath (rf_rs1/rs2/writeReg, endereçamento word da RAM, ALU com `shamt`, `hi_out`/`lo_out`, alinhamento CU↔ALU, init de `$sp` no reset, ROM combinacional, IN/OUT, debounce, displays de OUT, `sign_extend` instanciado, `isMultDiv` declarado, wires de 32 bits explícitos) **já foi aplicado**. As issues I1–I11 acima são os pontos que ainda podem fazer o processador não funcionar conforme o propósito.

---

## Ordem de execução sugerida

```
Fase 0 (críticos: $sp + ramstyle)  ──→  Fase 1 (cleanup)  ──→  Fase 2 (testbench)  ──→  Fase 3 (FPGA)
```

A Fase 0 ataca primeiro o que de fato pode impedir o processador de rodar (inicialização do `$sp` no power-on e inferência da ROM/RAM como BRAM). Sem elas, a Fase 2 e a Fase 3 podem dar resultados confusos e a "culpa" será atribuída ao datapath, que já está correto. As demais Fases seguem inalteradas.
