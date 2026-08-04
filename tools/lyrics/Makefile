# tools/lyrics/Makefile — lyrics-ocr のビルドと自己検証。
#
#   make            … bin/lyrics-ocr をビルド
#   make verify     … 縦書き/横書き/2段組み/ルビのテスト画像を自前生成して読み順を検証
#   make clean
#
# ランニングコストゼロ (ローカルの Vision.framework のみ。クラウド OCR は使わない)。

# xcrun 経由で呼ぶ (SDKROOT を張らずに swiftc を直叩きすると標準ライブラリを見失う)
SWIFTC := xcrun swiftc
SRC    := $(wildcard src/*.swift)
BIN    := bin/lyrics-ocr
GEN    := bin/gen-testimage
TESTDIR := build/testimg

.PHONY: all verify clean help

all: $(BIN)

$(BIN): $(SRC)
	@mkdir -p bin
	$(SWIFTC) -O -parse-as-library $(SRC) -o $(BIN)
	@echo "✓ $(BIN)"

$(GEN): test/GenTestImage.swift
	@mkdir -p bin
	$(SWIFTC) -O test/GenTestImage.swift -o $(GEN)

verify: $(BIN) $(GEN)
	@mkdir -p $(TESTDIR)
	@$(GEN) $(TESTDIR)
	@python3 test/verify.py $(BIN) $(TESTDIR)

clean:
	rm -rf bin build

help:
	@echo "make / make verify / make clean"
	@echo "実行例: ./bin/lyrics-ocr --help"
