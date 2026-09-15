# rvp-verify — RISC-V P 擴展 (RVP draft 020) Sail 模型驗證環境

一站式打包:`git clone --recursive` 之後,照下面步驟建置,就能對
sail-riscv 的 P 擴展實作跑完整測試套件(rv32 446 + rv64 318 顆)並產生報告。

規格權威:**RVP draft 020 (2026-03-21)** — https://www.jhauser.us/RISCV/ext-P/

## 內容物

| 路徑 | 是什麼 |
|---|---|
| `sail-riscv/` | submodule → nthu-pllab/sail-riscv,branch `pext-020-rebase`(被測物) |
| `rvp-test-suite/` | submodule → nthu-pllab/rvp-test-suit,branch `align-020-names`(764 顆 riscv_ctg 產生的 `.S` + cgf)。**私有 repo**,需要 nthu-pllab 組織權限 + SSH key |
| `riscv-binutils/` | submodule → gglangg/riscv-binutils,branch `fix-mulq-encoding`(ruyisdk p-dev + mulq/mulqr funct4 修正) |
| `env/arch-test/` | riscv-arch-test 的 `arch_test.h` + P 版 `test_macros.h`(TEST_PAIR_* 巨集) |
| `env/sail/` | `model_test.h` + `link.ld`(Sail 端 target 檔) |
| `riscv-ctg/` | 實驗室改造版測資產生器(P 模板 `riscv_ctg/data/p.yaml`、語意在 `dsp_function.py`,含 Python 3.13 修正) |
| `coverage/dataset.cgf` | ctg 的共用 YAML anchor 資料集 |
| `results/baseline-2026-08-03/` | 764/764 PASS 的基準:report.html、results.tsv、各測試簽章(可拿來 diff) |
| `run_suite.sh` 等 | 驗證腳本,見下 |

## 建置(一次性)

前置需求:`riscv64-unknown-elf-gcc` 在 PATH(任何近代版本都行,只用來做 `-E` 預處理)、
cmake、opam(Sail 0.20.2)、python3。

```bash
git clone --recursive <this-repo-url>
cd rvp-verify

# 1. P-aware binutils(產出 build/gas/as-new、build/ld/ld-new)
cd riscv-binutils && mkdir -p build && cd build
../configure --target=riscv64-unknown-elf --disable-gdb --disable-sim \
             --disable-gprofng --disable-werror --disable-nls --with-system-zlib
make -j8
cd ../..

# 2. Sail 模型模擬器(產出 build/c_emulator/sail_riscv_sim)
opam install sail.0.20.2
cd sail-riscv && ./build_simulator.sh && cd ..
```

## 跑測試

```bash
LIMIT=2 bash run_suite.sh    # smoke:每套 2 顆
bash run_suite.sh            # 完整 764 顆
python3 gen_report.py        # 從 results/current 產生 report.html
```

預期結果:**764/764 PASS**(基準:2026-08-03,sail-riscv `f62b7011` + 套件 `01b188e`)。
新跑的簽章在 `results/current/sig_*.sig`,可與 `results/baseline-2026-08-03/` 逐檔 diff
確認語意沒有漂移。工具位置都可用環境變數覆蓋(`AS`、`LD`、`SAIL`、`RISCV_GCC`、`OUT`)。

單顆指令快查(編碼 + 語意,expected 自己從 020 spec 算):

```bash
./verify_insn.sh aadd "6,4=>5" "-0x80000000,0x7fffffff=>0xffffffff"
XLEN=64 ./verify_insn.sh <mnem> "rs1,rs2=>expected"
```

## 方法論(誠實聲明)

這是 **Sail 單邊的 signature-capture run,不是 DUT-vs-Reference 差分比對**
(P-enabled 的 spike fork 尚未公開可用)。PASS 的定義:乾淨 HTIF 結束、無
illegal instruction、無 trap loop,並擷取記憶體簽章。跨版本的語意回歸靠
「新簽章 vs 基準簽章」diff 把關。

## 重新產生測資(進階)

```bash
./setup_ctg_venv.sh            # 建 ctg-venv/(可重跑;--fresh 全重建)
./regen_tests.sh rv32 p20      # 重生一個 cgf page 到 ./regen_out/
```

產出的 `.S` 要**人工審核後**才複製進 `rvp-test-suite/`,不是自動採用。
兩個坑:① cgf/`p.yaml` 的 page 編號對應 **draft 015** 的 PDF 頁碼(018/020 會位移),
對外溝通一律用指令名;② p.yaml 的 Page-22–24 covergroup 還是 015 命名
(`ppack.*` = 020 的 `ppaire.*`),重生那幾頁會吐出舊檔名,要重套 020 改名。

其他注意:預處理必須 `-march=rv32i`/`rv64i`(gcc 才會定義 `__riscv_xlen`,
`TEST_PAIR_*` 巨集靠它把關,否則靜默消失);組譯要
`-march=rv{32,64}ip_zicsr_zba_zbb_zbkb`(測試借用了非 P 指令);rv32 連結要
`-m elf32lriscv`。這些 `run_suite.sh` 都已內建。
