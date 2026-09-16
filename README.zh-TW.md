# rvp-verify — sail-riscv 的 RISC-V P 擴展（RVP draft 020）驗證環境

英文版 `README.md` 是對外的主要說明，這份是給實驗室看的中文版，內容相同。

一站式打包：`git clone --recursive` → `./build.sh` → `./run_suite.sh` →
`python3 gen_report.py`，就能對 sail-riscv 的 P 擴展實作跑完整測試套件
（rv32 446 + rv64 318 = 764 顆）並產生報告。這是送 riscv/sail-riscv 的
P 擴展 PR 背後的驗證證據。

規格權威：RVP draft 020 (2026-03-21)，John Hauser，
https://www.jhauser.us/RISCV/ext-P/（`RVP-baseInstrs-020.pdf`、
`RVP-instrEncodings-020.pdf`、`RVP-baseInstrs-Sail-020.txt`）。

## 內容物

| 路徑 | 是什麼 |
|---|---|
| `sail-riscv/` | submodule：被測物（riscv/sail-riscv 的 nthu-pllab fork，branch `pext-020-rebase`） |
| `rvp-test-suite/` | submodule：764 顆 riscv_ctg 產生的 `.S` 測試（446 RV32、318 RV64）與產生它們的 cgf coverpoint 檔 |
| `riscv-binutils/` | submodule：P-aware binutils（ruyisdk `p-dev` + `mulq`/`mulqr` 編碼修正） |
| `env/arch-test/` | riscv-arch-test 的 `arch_test.h`、`encoding.h`，以及加了 register-pair `TEST_PAIR_*` 巨集的 `test_macros.h` |
| `env/sail/` | Sail target 用的 `model_test.h` + `link.ld` |
| `riscv-ctg/` | 有 P 支援的測資產生器（模板 `riscv_ctg/data/p.yaml`，語意 `dsp_function.py`） |
| `coverage/dataset.cgf` | 套件 cgf 引用的共用 YAML anchor |
| `results/baseline/` | 基準結果：`report.html`、`results.tsv`、每顆測試一個記憶體簽章 |
| `build.sh`、`run_suite.sh`、`gen_report.py`、`verify_insn.sh`、`regen_tests.sh`、`setup_ctg_venv.sh` | 腳本，見下 |
| `VENDOR.md` | vendor 進來的檔案各自來自哪裡、改了什麼 |

## 建置

需求：C/C++ toolchain、CMake、Python 3、opam 裝好 Sail 0.20.2
（`opam install sail.0.20.2 && eval $(opam env)`），以及一個只用來做
`-E` 預處理的 `riscv64-unknown-elf-gcc`（任何近代版本；放在 PATH，或設
`RISCV=<prefix>` / `RISCV_GCC=<路徑>`）。

```
./build.sh            # 增量；binutils 已建好就跳過
./build.sh --fresh    # 兩個都從頭重建
```

產物是 `riscv-binutils/build/gas/as-new`、`riscv-binutils/build/ld/ld-new`
和 `sail-riscv/build/c_emulator/sail_riscv_sim`。upstream sail-riscv 在
configure 時會從 sourceforge 抓 asio；如果下載失敗，把
[asio 1.36.0](https://github.com/chriskohlhoff/asio/archive/refs/tags/asio-1-36-0.tar.gz)
解開後跑 `ASIO_SRC=<目錄>/asio ./build.sh`。

## 跑測試

```
LIMIT=2 ./run_suite.sh   # smoke：每套 2 顆
./run_suite.sh           # 完整 → results/current/
python3 gen_report.py    # → results/current/report.html
```

每顆測試：`gcc -E`（必須 `-march=rv32i`/`rv64i`，`TEST_PAIR_*` 巨集靠
`__riscv_xlen` 把關）→ P-aware `as`（`-march=rv{32,64}ip_zicsr_zba_zbb_zbkb`，
測試借用了幾個非 P 指令）→ `ld` → `sail_riscv_sim --enable-experimental-extensions
--test-signature`。結果為 `PASS`、`PP_FAIL`、`AS_FAIL`、`LD_FAIL`、`TIMEOUT`、
`INST_LIMIT`（指令預算內沒走到 HTIF 結束）或 `RUN_FAIL(rc=N)`。工具位置可用 `AS`、`LD`、`SAILDIR`、`SAIL`、
`RISCV_GCC`、`OUT` 覆蓋。

預期結果：764/764 PASS。每顆的簽章在
`results/current/sig_rv{32,64}_<group>_<test>.sig`（同名測試會出現在不同指令
群，所以檔名帶群名），可與基準逐檔比對：

```
diff -rq results/baseline results/current --exclude=report.html --exclude=tmp
```

## 結果的意義

這裡只有 Sail 這一邊，沒有第二個實作可以對照：目前沒有公開的 draft-020
P-enabled Spike 或其他參考實作。PASS 的意思是組譯、連結、執行到 HTIF 結束（模擬器印出
SUCCESS），過程中沒有 illegal instruction。簽章是模型自己產生的，
所以拿來比對只能看出模型版本之間的差異，看不出模型和規格之間的差異。

語意的部分另外用 Hauser 的 `RVP-baseInstrs-Sail-020.txt`（相對舊 P 提案有變動的
指令的 Sail 風格 pseudo-code）逐條對過，編碼則用 binutils 做往返（`verify_insn.sh`）。
報告的 Coverage 段落列出每個 XLEN 模型的 P 助記符有幾個至少有一顆測試、哪些沒有。

## 單顆指令快查

```
./verify_insn.sh aadd "6,4=>5" "-0x80000000,0x7fffffff=>0xffffffff"
XLEN=64 ./verify_insn.sh <mnem> "rs1,rs2=>expected"
```

用 binutils 組 `<mnem> a5,a3,a4`，確認模型把同樣的 bytes 解回同一個助記符
（抓錯位元和 clause 碰撞），再逐個跑 `rs1,rs2=>expected` 比對 `rd`。
`expected` 要自己從規格算。只支援三暫存器形式。

## 重新產生測資（進階）

```
./setup_ctg_venv.sh          # 建 ctg-venv/（可重跑；--fresh 全重建）
./regen_tests.sh rv32 p20    # 重生一個 cgf 群到 ./regen_out/
```

riscv_ctg 是 constraint solver + 模板引擎：cgf coverpoint 說要 cover 什麼，
`p.yaml` 說哪些值可以抽；它自己不知道合法的運算元範圍，組譯器是下游唯一的
範圍檢查。重生的 `.S` 要人工審核後才複製進 `rvp-test-suite/`，不會自動採用。
cgf/`p.yaml` 的群名對應的是舊版（015）編碼 PDF 的頁碼，對外一律用指令名。

## 已知的工具鏈問題

這裡用的 P-aware binutils 是 ruyisdk `p-dev`。對照 draft 020 時發現兩個編碼
錯誤，已回報：`mulq`/`mulqr` 的 funct4 是 1011、規格是 1010（submodule 的 branch
已修）；RV32 `psshl.dhs`/`psshl.dws` 吐 funct3 100、規格是 010（模型照規格，
所以這兩顆無法往返）。020 新增的 `pnclipp.*`/`pnclipup.*` 這版 binutils 還不認識。

## 授權

本 repo 自己寫的腳本與檔案採 BSD-3-Clause；vendor 進來的 riscv-ctg 與
riscv-arch-test 素材的授權見 `LICENSE`。submodule 是各自獨立的專案，授權各自處理。
