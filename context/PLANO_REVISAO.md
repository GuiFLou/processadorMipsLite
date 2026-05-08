# Plano de Revisão — Processador MIPS-Lite

Documento de referência: `CONTEXTO_PROCESSADOR.md` (especificação autoritativa da ISA e microarquitetura).

> **Status:** A maior parte das correções de datapath, control unit, ALU e I/O já foi aplicada. As issues abaixo são as que **ainda estão pendentes** após a revisão do código atual.

---

## Visão geral dos problemas restantes

Sobra apenas um cleanup de código morto (`input_value`), a criação do testbench e a verificação dos pinos no `.qsf` antes de programar a placa.

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

| Arquivo | Alterações restantes |
|---------|---------------------|
| `Processador_GUI_MIPS.v` | Remover `wire input_value` (linha 196) que ficou como código morto |
| `tb_processador.v` | **Criar** testbench cobrindo `teste2.txt` → `gcd.txt` → `sort.txt` |
| `Processador_GUI_MIPS.qsf` | Reconferir pinos de KEY[1], SW, HEX0–HEX6 e LEDR |

Tudo o que já estava na ISA e datapath (rf_rs1/rs2/writeReg, endereçamento word da RAM, ALU com `shamt`, `hi_out`/`lo_out`, alinhamento CU↔ALU, init de `$sp`, ROM combinacional, IN/OUT, debounce, displays de OUT, `sign_extend` instanciado, `isMultDiv` declarado, wires de 32 bits explícitos) **já foi aplicado** e não precisa de novas mudanças.

---

## Ordem de execução sugerida

```
Fase 1 (cleanup)  ──→  Fase 2 (testbench)  ──→  Fase 3 (FPGA)
```

A Fase 2 valida que as correções de datapath/control unit realmente fizeram o processador funcionar antes de queimar tempo na placa.
