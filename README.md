# Processador MIPS-Lite

Processador monociclo de 32 bits, endereçado por palavra, para a DE2-115
(Cyclone IV E, `EP4CE115F29C7`). Executa os binários do compilador C- e
hospeda o hardware do SO: memória de instrução gravável, HD simulado, LCD e
o retorno da opção 1 por `pc_load`.

A referência do mapa de memória, do MMIO e do estado do projeto é
[`../so/docs/CONTEXT.md`](../so/docs/CONTEXT.md). Os detalhes da ISA estão em
[`context/CONTEXTO_PROCESSADOR.md`](context/CONTEXTO_PROCESSADOR.md) e o
resumo das memórias em [`context/MEMORIAS.md`](context/MEMORIAS.md).

## Estrutura

| Arquivo | Papel |
|---------|-------|
| `Processador_GUI_MIPS.v` | Top-level: PC, datapath, decode do MMIO 4088–4095, `display_ctx`, `pc_load`/`cause`, LEDs e 7-seg. |
| `control_unit.v`, `alu.v`, `sign_extend.v` | Decodificação do opcode, ULA e extensão do imediato de 14 bits. |
| `regfile64.v` | Banco de 64 × 32 bits. Leitura combinacional, escrita síncrona. O reset zera o banco e põe `$sp` em 1023. |
| `inst_mem_rw.v` | IMEM de 4096 × 32. Porta A: fetch pelo PC. Porta B: escrita do HD. Carrega `so.txt`. |
| `data_ram.v` | RAM de 4096 × 32. Porta A: `LW`/`SW` da CPU em 0–4087. Porta B: DMA do HD. |
| `hd_sim.v` | HD de 64 setores × 256 palavras, MMIO em 4092–4095. Carrega `hd_image.txt`. |
| `lcd_controller.v` | LCD 16×2 no domínio de 50 MHz. Desenha as telas fixas escolhidas por `display_ctx`. |
| `divisor_freq.v`, `debounce.v` | Geração do `clk_cpu` e debounce dos KEY. |
| `bin32_to_bcd7.v`, `hex7seg.v` | Último `OUT` em decimal nos HEX0–HEX6. |
| `single_port_rom.v` | ROM antiga de 1024 palavras. Fora do top-level e do `.qsf`. |
| `tb_*.v`, `tb_*.txt` | Testbenches e os programas que eles carregam. |
| `Processador_GUI_MIPS.qpf/.qsf/.sdc` | Projeto do Quartus. |
| `context/` | Documentação do processador. |

## Imagens de memória

- `so.txt`: imagem de reset da IMEM, com 4096 linhas, lida também pelo
  `tb_menu`. As palavras 0–1334 são
  o kernel compilado (iguais a `../so/src/so.txt`), 1335–3070 são NOP, a 3071
  é `J 3071` e 3072–4095 ficam em zero. Nenhum script do repositório monta
  esse arquivo. A receita de shell que gera o arquivo atual, byte a byte, está
  em `../so/docs/CONTEXT.md`, na seção "Construção das imagens iniciais".
- `hd_image.txt`: imagem inicial do HD, com 16.384 linhas (64 setores × 256).
  Setor 0: catálogo (assinatura `20261013`). Setores 1–12: NOP, com `J 3071`
  na última palavra do setor 12. Setores 20–29: os dez programas do alvo
  `os-user`. O resto fica em zero. `../compilador/reset_tests.sh
  --target=os-user` regrava só os setores 20–29.
- `../so/src/so.txt`: o kernel sozinho, 1335 palavras, origem das palavras
  0–1334 de `so.txt`. É gerado pelo compilador e ignorado pelo git do
  repositório `so/`:

  ```bash
  cd ../so/src
  ../../compilador/compilador --txt so.cms
  ```

- `gcd.txt`: binário legado do `gcd` (58 palavras, sem NOP de tamanho), usado
  só como arquivo de inicialização da IMEM no `tb_hd_map`.

O Quartus lê `so.txt` e `hd_image.txt` deste diretório (`MISC_FILE` no
`.qsf`). As duas imagens só entram na configuração da FPGA: KEY[0] zera o PC,
os registradores e os CSRs, mas não recarrega a IMEM, a RAM nem o HD.

## Parâmetros do top-level

| Parâmetro | Síntese | Testbenches | Efeito |
|-----------|---------|-------------|--------|
| `CPU_DIV` | 5000 | 1 | `clk_cpu` = 50 MHz / (2 · `CPU_DIV`), cerca de 5 kHz na placa. |
| `BTN_STABLE` | 1000000 | 3 | Ciclos de 50 MHz estáveis para o debounce dos KEY (cerca de 20 ms). |
| `ROM_FILE` | `so.txt` | arquivo do teste | Imagem da IMEM. |
| `HD_FILE` | `hd_image.txt` | `hd_image.txt` | Imagem do HD. |
| `LCD_T_*` | tempos reais do HD44780 | poucos ciclos | Esperas do controlador do LCD. |

No `.sdc`, o `clk_cpu` é um clock gerado a partir do `CLOCK_50`. O valor
correto do `-divide_by` é 10000, isto é, 2 · `CPU_DIV`; se `CPU_DIV` mudar,
esse número muda junto.

Na placa: SW[9:0] é a entrada do `IN`; LEDR[9:0] ecoa os switches; LEDR[16]
acende quando a instrução atual é `HLT`; LEDR[17] acende enquanto `IN` ou
`OUT` esperam KEY[1]. KEY[1] confirma, KEY[2] e KEY[3] andam no menu do LCD,
KEY[0] é o reset.

## Simulação

Os testes usam o Icarus Verilog. Rode o `vvp` a partir deste diretório: os
`$readmemb` usam caminhos relativos (`hd_image.txt`, `tb_*.txt`, `gcd.txt` e
`so.txt`). Os executáveis podem ficar em `/tmp`; os `sim_*` antigos
desta pasta são ignorados pelo git.

O `tb_hd_map` instancia só o HD e as memórias:

```bash
cd processador
iverilog -o /tmp/tb_hd_map tb_hd_map.v hd_sim.v data_ram.v inst_mem_rw.v
vvp -n /tmp/tb_hd_map
```

Os outros quatro instanciam o top-level inteiro e precisam das mesmas fontes:

```bash
cd processador
for tb in tb_lcd tb_hd_stall tb_retorno tb_menu; do
  iverilog -o /tmp/$tb $tb.v Processador_GUI_MIPS.v alu.v bin32_to_bcd7.v \
    control_unit.v data_ram.v debounce.v divisor_freq.v hd_sim.v hex7seg.v \
    inst_mem_rw.v lcd_controller.v regfile64.v sign_extend.v && vvp -n /tmp/$tb
done
```

Cada teste imprime uma linha `PASS` ou `FAIL` por verificação e termina com
`PASS <nome>` quando tudo passa.

| Teste | Programa | O que confere |
|-------|----------|---------------|
| `tb_hd_map` | `gcd.txt` na IMEM | Assinatura do catálogo e `J 3071` no `hd_image.txt`; base 3833 recusada para RAM; setor 20 copiado para a IMEM em 3072. |
| `tb_hd_stall` | `tb_hd_stall.txt` | O `SW` em `hd_cmd` segura o PC durante a transferência, o PC avança uma vez e o setor 20 chega à folha. |
| `tb_lcd` | `tb_lcd_mmio.txt` | `display_ctx` em 4091: escrita e leitura, KEY[2]/KEY[3], ack do KEY[1], o Enter de um `IN` sem ack, telas do catálogo; `SW` de um sentinela em 4088 fora da folha não desvia e lê 0; 8187 não é alias de 4091. |
| `tb_retorno` | `tb_retorno.txt` | `SW` em 4088 com destino 3072 executa a folha; o `HLT` armado volta para PC+1; `kret` e RAM[1042] guardam PC+1; `cause` = 2, `epc` = 3072 e a arma desligada; o `HLT` seguinte, sem arma, congela o PC. |
| `tb_menu` | `so.txt` | Imagem de reset real: boas-vindas, menu, opção 1 com a área (dois `IN` e `OUT` 12), volta ao menu com `$gp` 0, opção 2 com ERR e um segundo programa na folha. Um Enter no ciclo do `SW` que redesenha a lista, ou entre o último `LW` do ack e esse `SW`, vale; um Enter no `SW` que troca ERR por MENU não confirma o MENU. |

## Estado e riscos

- A Fase 1 (executar um programa e voltar ao menu) passa em simulação. Ainda
  não foi validada na placa.
- O último fit e o `.sof` em `output_files/` são de 2–3 de junho de 2026,
  anteriores ao mapa de 4096 palavras. Esse fit usou 0 bits de memória
  embarcada.
- Risco de síntese pendente: `inst_mem_rw` e `data_ram` leem de forma
  assíncrona (`assign rdata = mem[addr]`), e a RAM tem as duas portas de
  escrita no mesmo `always`. Nesse estilo o Quartus não infere M9K. São cerca
  de 262 mil bits (2 × 4096 × 32) que iriam para flip-flops, contra 114.480
  elementos lógicos do EP4CE115. O `hd_sim` já usa `(* ramstyle = "M9K" *)`
  com leitura síncrona. Antes de gravar a placa é preciso sintetizar de novo
  e conferir o relatório de memória.
- Timer de quantum, modo privilegiado, supervisor em 3840–4095 e `ctrl`
  (4090) ainda não existem (Fases 2 e 3).
