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
| `$sp` | 29 | `011101` | Ponteiro de pilha. Cresce para baixo. Reset do hardware: `1023`. O compilador reajusta para `1015` no boot (abaixo do MMIO). |
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
| Tamanho | 1024 × 32 bits |
| Endereços | 0–1023 |
| Acesso | `LW` / `SW` com endereço efetivo `RS + signext(Imm)` |
| Portas | A = CPU; B reservada (hoje amarrada em 0) |
| Init | zeros |

Layout usado pelos programas C‑ (sem SO):

```
0 … N-1     globais / locais alocados em $gp   ($gp = 0)
…           (meio livre)
topo        pilha, cresce para baixo           ($sp inicia no topo)
```

O topo efetivo da pilha no software é **1015**, para não colidir com MMIO (1016–1023).

### 2.4 Outros registradores do datapath (fora do banco)

Não fazem parte do banco de 64, mas armazenam estado:

| Nome | Tamanho | Propósito |
|------|---------|-----------|
| `pc` | 32 bits | Program counter. Reset: 0. Endereça a ROM/IMEM. |
| `hi_reg` / `lo_reg` | 32 bits cada | Resultado de `MULT`/`DIV`. Lidos quando RS/RT é 61 ou 62. |
| `out_reg` | 32 bits | Último valor de `OUT`, mantido no display. |

---

## 3. Estruturas em criação / planejadas

Ainda não estão no núcleo Verilog atual do processador. Incluir aqui quando forem integradas.

### 3.1 Memória de instrução gravável — `inst_mem_rw`

Substitui a ROM somente-leitura. Dual-port: fetch pelo PC + escrita (DMA do HD).

Mapa previsto (1024 palavras):

Uma imagem por vez, sempre a partir do endereço 0. No reset, a imagem é o
kernel. Na troca de contexto, a ROM inteira do ocupante atual vai para o HD
e a imagem do próximo ocupante entra no lugar.

| Endereços | Uso |
|-----------|-----|
| 0–767 | folha da vez: kernel ou programa (substituível) |
| 768–1023 | supervisor Assembly residente (não vai ao HD) |

### 3.2 HD simulado — `hd_sim`

Armazenamento persistente fora da RAM/ROM. Acesso via MMIO, não via `LW`/`SW` direto no array.

| | |
|--|--|
| Geometria | 8 trilhas × 8 setores × 256 palavras |
| Capacidade | 64 setores = 16.384 palavras |

### 3.3 MMIO — endereços 1016–1023 da RAM

`LW`/`SW` nesses endereços não acessam `data_ram`; o datapath desvia para periféricos.

**CSRs (1016–1019)**

| Endereço | Nome | Propósito |
|----------|------|-----------|
| 1016 | `pc_load` | Escrita carrega o PC; leitura devolve `epc`. |
| 1017 | `cause` | Causa da última trap (somente leitura). |
| 1018 | `ctrl` | modo, timer, DISPATCH; quantum em bits deste registrador. |
| 1019 | `display_ctx` | Modo do LCD, ID, PID; leitura inclui o índice da opção. **Implementado.** |

**HD (1020–1023)**

| Endereço | Nome | Propósito |
|----------|------|-----------|
| 1020 | `hd_cmd` | Comando: 0 nop, 1 setor→RAM, 2 setor→IMEM, 3 RAM→setor. |
| 1021 | `hd_sector` | Setor lógico (LBA 0–63). |
| 1022 | `hd_addr` | Endereço-base de origem/destino. |
| 1023 | `hd_status` | 0 idle, 1 busy, 2 done, 3 erro. |

---

## 4. Resumo rápido

```
Banco de regs   64 × 32     0–63          (reservados: 0, 2, 28–31, 61, 62)
ROM / IMEM    1024 × 32     0–767 / 768–1023  folha da vez / supervisor
RAM           1024 × 32     0–1015        dados + pilha
MMIO              8 × 32    1016–1023     CSRs + HD; 1019 = display_ctx (LCD)
HD sim          16384 × 32  setores 0–63  persistência (em criação)
PC / hi / lo / out          fora do banco
```
