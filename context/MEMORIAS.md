# Memórias e registradores do processador

Arquitetura Harvard, endereçamento **por palavra**. Identificador de registrador: 6 bits (0–63).

---

## 1. Registradores reservados

Registradores de propósito especial. O compilador e o hardware dependem destes números.

| Nome | Número | Binário | Propósito |
|------|--------|---------|-----------|
| `$zero` | 0 | `000000` | Sempre zero. Leituras retornam 0; escritas são ignoradas. |
| `$v0` | 2 | `000010` | Valor de retorno de funções. |
| `$gp` | 28 | `011100` | Ponteiro global. Base das variáveis em `$gp + offset`. Reset: `0`. |
| `$sp` | 29 | `011101` | Ponteiro de pilha. Cresce para baixo. Reset do hardware atual: `1023`. No mapa de 4096, o kernel usa `$sp = 1023` e o programa usa `$sp = 1791`. |
| `$fp` | 30 | `011110` | Ponteiro de frame. Locais em offsets negativos; parâmetros em offsets positivos. |
| `$ra` | 31 | `011111` | Endereço de retorno. Escrito automaticamente por `JAL` com `PC + 1`. |
| `$lo` | 61 | `111101` | Parte baixa de `MULT` / quociente de `DIV`. |
| `$hi` | 62 | `111110` | Parte alta de `MULT` / resto de `DIV`. |

### Temporários do compilador (não reservados no hardware)

| Nome | Número | Propósito |
|------|--------|-----------|
| `$t0`–`$t9` | 8–17 | Temporários. Mapeamento circular dos `tN` do intermediário. |

Os demais números do banco (1, 3–7, 18–27, 32–60, 63) existem no hardware e ficam livres.

---

## 2. Estruturas de memória

### 2.1 Banco de registradores — `regfile64.v`

| | |
|--|--|
| Tamanho | 64 × 32 bits |
| Endereços | 0–63 |
| Portas | 2 leituras + 1 escrita, sincrônico |
| Reset | zera todos; `$sp` ← 1023 |

`$hi` e `$lo` são endereçáveis neste mapa (61 e 62), mas o datapath atual guarda o valor real em registradores separados (`hi_reg` / `lo_reg`) e faz bypass na leitura.

### 2.2 ROM de instruções — `single_port_rom.v`

Módulo antigo, fora do topo. O fetch do processador é a `inst_mem_rw`, de 4096 palavras.

| | |
|--|--|
| Tamanho | 1024 × 32 bits |
| Endereços | 0–1023 (word address = PC) |
| Acesso | somente leitura; fetch pelo PC |
| Init | `$readmemb` do `.txt` do programa |

Cada posição contém uma instrução completa de 32 bits. O PC avança de 1 em 1.

### 2.3 RAM de dados — `data_ram.v`

| | |
|--|--|
| Tamanho | 4096 × 32 bits |
| Endereços | 0–4095; a porta A da CPU só usa 0–4087 |
| Acesso | `LW` / `SW` com endereço efetivo `RS + signext(Imm)` |
| Portas | A = CPU; B = DMA do HD |
| Init | zeros |

Layout usado pelos programas C‑ (sem SO):

```
0 … N-1     globais / locais alocados em $gp   ($gp = 0)
…           (meio livre)
topo        pilha, cresce para baixo           ($sp inicia no topo)
```

O reset do hardware põe `$sp` em **1023**, topo dos dados do kernel. O MMIO fica em 4088–4095, então `LW`/`SW` da CPU não passam de 4087.

### 2.4 Outros registradores do datapath (fora do banco)

Não fazem parte do banco de 64, mas armazenam estado:

| Nome | Tamanho | Propósito |
|------|---------|-----------|
| `pc` | 32 bits | Program counter. Reset: 0. Endereça a ROM/IMEM. |
| `hi_reg` / `lo_reg` | 32 bits cada | Resultado de `MULT`/`DIV`. Lidos quando RS/RT é 61 ou 62. |
| `out_reg` | 32 bits | Último valor de `OUT`, mantido no display. |

---

## 3. Mapa decidido para o SO — 4096 palavras

Decisão de 2026-10-13: IMEM e RAM têm **4096 × 32 bits**. Kernel, folha da vez e supervisor co-residem na IMEM. O código do kernel não é descarregado para um programa executar.

O Verilog do topo usa `ADDR_W = 12`. `display_ctx` está em 4091 e o HD em 4092–4095. `pc_load` (4088) e `cause` (4089) fazem a volta da opção 1. A escrita em 4088 só arma quando o destino está em 3072–3839 e o HD não está congelado: grava PC+1 em `kret` e na RAM 1042 e desvia. Fora da folha a escrita é ignorada, e o sentinela 99 do `tb_lcd` continua. O `HLT` armado volta a esse PC, grava a causa 2 em 4089 e desarma. O `HLT` sem arma congela o PC e acende LEDR[16]. A leitura de 4088 devolve `epc`. `ctrl` (4090) continua sem efeito. Faltam timer, modo privilegiado e o Assembly do supervisor.

### 3.1 Memória de instrução — co-residência

`J` e `JAL` usam endereço absoluto. O kernel permanece em 0, então o reset e os saltos dele não mudam. Um programa carregado na folha da vez precisa receber a base **3072** em cada `J` e `JAL`. Os desvios condicionais são relativos ao PC.

| Endereços | Tamanho | Uso |
|-----------|---------|-----|
| 0–3071 | 3072 palavras, 12 setores | kernel residente |
| 3072–3839 | 768 palavras, 3 setores | folha da vez: um programa |
| 3840–4095 | 256 palavras | supervisor Assembly residente |

O maior binário atual tem 162 palavras (`sort` no alvo os-user) e ocupa um setor, gravado a partir de 3072. O endereço 3071 é o salto de guarda do kernel.

### 3.2 RAM de dados — kernel residente e janela do programa

| Endereços | Uso |
|-----------|-----|
| 0–1023 | dados e pilha do kernel (`$gp = 0`, `$sp = 1023`) |
| 1024–1279 | mailbox e estado protegido do supervisor |
| 1280–1535 | buffer de um setor |
| 1536–1791 | janela de dados do programa (`$gp = 1536`, `$sp = 1791`) |
| 1792–4087 | reservado |
| 4088–4095 | MMIO |

Na troca, a janela 1536–1791 volta ao HD. Os dados do kernel e o código em 0–3071 permanecem.

**Mailbox (1024–1279)**

| Endereços | Conteúdo |
|-----------|----------|
| 1024–1041 | contexto de usuário (18 palavras) |
| 1042–1059 | contexto do kernel (18 palavras) |
| 1060 | `cause` |
| 1061 | PID atual |
| 1062 | próximo PID |
| 1063 | registrador destino de `IN` |
| 1064 | valor fonte de `OUT` |
| 1065 | setor de código do próximo programa |
| 1066 | setor de dados do próximo PID |
| 1067 | reservado |
| 1068 | saldo do quantum |
| 1069–1279 | reservados |

Ordem prevista de cada contexto: PC, `$v0`, `$t0`–`$t9`, `$gp`, `$sp`, `$fp`, `$ra`, `$hi`, `$lo`. A troca dessas 18 palavras não está pronta. Na opção 1 o hardware grava PC+1 em 1042 e `runat` grava `$v0`, `$t0`–`$t9`, `$gp`, `$sp`, `$fp` e `$ra` em 1043–1057. `$hi` e `$lo` ficam de fora.

### 3.3 HD simulado — `hd_sim`

Armazenamento persistente fora da RAM/ROM, já instanciado no top-level. Acesso via MMIO, não via `LW`/`SW` direto no array. Durante as 256 palavras o PC e as escritas da CPU ficam parados; o PC avança uma vez junto com a última palavra. Na síntese, `CPU_DIV` é 5000, cerca de 5 kHz, `BTN_STABLE` é 1000000 e o LCD usa os tempos reais. O `tb_menu` encurta isso só na simulação. O Quartus lê `so.txt` e `hd_image.txt` do diretório do processador (`MISC_FILE` no `.qsf`).

A imagem em `hd_image.txt` segue o layout abaixo. Os dez programas estão nos setores 20–29 e não vêm de `compilador/exemplos/`. Os setores 1–12 estão em NOP, com o salto de guarda na palavra 3071. A IMEM de reset é `so.txt`, com 4096 palavras: o kernel compilado nas palavras 0–1334, NOP em 1335–3070, `J 3071` na palavra 3071 e zero em 3072–4095. O supervisor ainda não existe. `so.txt` não repete os setores 1–12.

| | |
|--|--|
| Geometria | 8 trilhas × 8 setores × 256 palavras |
| Capacidade | 64 setores = 16.384 palavras |

| Setores | Conteúdo |
|---------|----------|
| 0 | diretório |
| 1–12 | código do kernel (3072 palavras) |
| 13–16 | dados do kernel (1024 palavras) |
| 17–19 | reservados |
| 20–35 | até 16 executáveis, um setor cada |
| 36–45 | janela de RAM dos PIDs 0–9 |
| 46–63 | reservados |

### 3.4 MMIO — endereços 4088–4095 da RAM

`LW`/`SW` nesses endereços não acessam a RAM de dados. `display_ctx` está em **4091**. `pc_load` e `cause` estão em 4088 e 4089. `ctrl` (4090) ainda não tem efeito.

**CSRs (4088–4091)**

| Endereço | Nome | Propósito |
|----------|------|-----------|
| 4088 | `pc_load` | Escrita com destino 3072–3839 e HD descongelado carrega o PC, grava PC+1 em `kret` e na RAM 1042 e desvia. Fora da folha a escrita é ignorada. Leitura devolve `epc`. |
| 4089 | `cause` | HLT armado grava 2. Escrita ignorada. Leitura devolve a causa. |
| 4090 | `ctrl` | modo, timer, DISPATCH; quantum em bits deste registrador. Ainda sem efeito. |
| 4091 | `display_ctx` | Modo do LCD, ID, PID. Leitura inclui índice e ack. O catálogo já existe no Verilog. |

Campos de `display_ctx`: escrita `[7:0]` modo, `[17:8]` ID, `[21:18]` PID. Toda escrita zera o ack. Leitura: `[27]` ack, `[26:22]` índice, e os mesmos campos da escrita. KEY[1] liga o ack quando a CPU não está em IN/OUT. KEY[2]/KEY[3] andam o índice só em modo com mais de um item. Modos: 1 MENU (3), 2 BEM-VINDO, 3 RUN, 4 OK, 5 ERR, 6 PROG (10), 7 QUANTOS (10), 8 ARQUIVOS.

**HD (4092–4095)**

| Endereço | Nome | Propósito |
|----------|------|-----------|
| 4092 | `hd_cmd` | Comando: 0 nop, 1 setor→RAM, 2 setor→IMEM, 3 RAM→setor. |
| 4093 | `hd_sector` | Setor lógico (LBA 0–63). |
| 4094 | `hd_addr` | Endereço-base de origem/destino. |
| 4095 | `hd_status` | 0 idle, 1 busy, 2 done, 3 erro. |

Não há comando IMEM→HD. O código da folha da vez é descartado; a cópia persistente permanece no HD.

---

## 4. Resumo rápido

```
Banco de regs   64 × 32       0–63
IMEM          4096 × 32       0–3071 kernel | 3072–3839 folha | 3840–4095 supervisor
RAM           4096 × 32       0–1023 kernel | 1024–1279 mailbox | 1280–1535 buffer
                              1536–1791 janela do programa | 4088–4095 MMIO
HD sim         16384 × 32     setores 0–63; programas nos setores 20–29
IMEM de reset   so.txt         4096 palavras; kernel em 0–1334; NOP até 3070; J 3071; resto zero
Verilog       4096 × 32       MMIO em 4088–4095; display_ctx em 4091; CPU_DIV 5000
PC / hi / lo / out            fora do banco
```
