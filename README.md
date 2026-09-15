# rvp-verify — RISC-V P 擴展 (RVP draft 020) Sail 模型驗證環境

一站式打包:`git clone --recursive` → `./build.sh` → `./run_suite.sh`,就能對
sail-riscv 的 P 擴展實作跑完整測試套件(rv32 446 + rv64 318 顆)並產生報告。

規格權威:**RVP draft 020 (2026-03-21)** — https://www.jhauser.us/RISCV/ext-P/

## 內容物

| 路徑 | 是什麼 |
|---|---|
| `sail-riscv/` | submodule → nthu-pllab/sail-riscv,branch `pext-020-rebase`(被測物;`upstream` remote = riscv/sail-riscv) |
| `rvp-test-suite/` | submodule → nthu-pllab/**rvp-test-suit**(GitHub 上的名字少一個 e,是同一個東西),branch `align-020-names`:764 顆 riscv_ctg 產生的 `.S` + cgf。**私有 repo**,需要 nthu-pllab 組織權限 + SSH key |
| `riscv-binutils/` | submodule → gglangg/riscv-binutils,branch `fix-mulq-encoding`(ruyisdk p-dev + mulq/mulqr funct4 修正) |
| `env/arch-test/` | riscv-arch-test 的 `arch_test.h` + P 版 `test_macros.h`(TEST_PAIR_* 巨集) |
| `env/sail/` | `model_test.h` + `link.ld`(Sail 端 target 檔) |
| `riscv-ctg/` | 實驗室改造版測資產生器(P 模板 `riscv_ctg/data/p.yaml`、語意在 `dsp_function.py`) |
| `coverage/dataset.cgf` | ctg 的共用 YAML anchor 資料集 |
| `results/baseline/` | 基準結果:report.html、results.tsv、每顆測試的簽章(拿來 diff 用) |
| `VENDOR.md` | 上面 vendor 進來的檔案各自來自哪個 commit、改了什麼 |
| `build.sh` / `run_suite.sh` / … | 建置與驗證腳本,見下 |

## 建置(一次性)

前置需求:C/C++ toolchain、cmake、python3、opam 裝好 **Sail 0.20.2**
(`opam install sail.0.20.2 && eval $(opam env)`),以及一個
`riscv64-unknown-elf-gcc`(任何近代版本;只用來做 `-E` 預處理)——放在 PATH,
或設 `RISCV=<toolchain prefix>`,或 `RISCV_GCC=<完整路徑>`。

```bash
git clone --recursive <this-repo-url>
cd rvp-verify
./build.sh          # 建 riscv-binutils(as-new/ld-new)+ sail-riscv(sail_riscv_sim)
```

`./build.sh --fresh` 兩個都從頭重建;之後改了 Sail 模型只要再跑 `./build.sh`(增量)。

## 跑測試

```bash
LIMIT=2 ./run_suite.sh       # smoke:每套 2 顆
./run_suite.sh               # 完整 764 顆 → results/current/
python3 gen_report.py        # 從 results/current 產生 report.html
```

預期結果:**764/764 PASS**。`results/current/sig_rv{32,64}_<page>_<test>.sig`
是每顆測試的記憶體簽章(同名測試在不同 spec page 各有一顆,所以檔名帶 page),
可與 `results/baseline/` 逐檔 diff 確認語意沒有漂移:

```bash
diff -rq results/baseline results/current --exclude=report.html --exclude=tmp
```

工具位置都可用環境變數覆蓋(`AS`、`LD`、`SAILDIR`、`SAIL`、`RISCV_GCC`、`OUT`)。

單顆指令快查(編碼 + 語意,expected 自己從 020 spec 算):

```bash
./verify_insn.sh aadd "6,4=>5" "-0x80000000,0x7fffffff=>0xffffffff"
XLEN=64 ./verify_insn.sh <mnem> "rs1,rs2=>expected"
```

## 方法論(誠實聲明)

這是 **Sail 單邊的 signature-capture run,不是 DUT-vs-Reference 差分比對**
(P-enabled 的 spike fork 尚未公開可用)。PASS 的定義:乾淨 HTIF 結束、無
illegal instruction、無 trap loop,並擷取記憶體簽章。跨版本的語意回歸靠
「新簽章 vs 基準簽章」diff 把關;測試向量的覆蓋意圖由 `rvp-test-suite/*_cgf/`
的 coverpoint 定義。

## 在這裡改 Sail 模型

`sail-riscv/` 是完整的 git checkout(branch `pext-020-rebase`,origin =
nthu-pllab fork,upstream = riscv/sail-riscv),可以直接在裡面 commit、rebase、push。
改完後:`./build.sh` → `./run_suite.sh` → diff 簽章。要更新這個 repo 釘住的
版本時,在頂層 `git add sail-riscv && git commit`。

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
