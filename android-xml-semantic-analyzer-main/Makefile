CC      ?= cc
BISON   ?= bison
FLEX    ?= flex
CFLAGS  ?= -O2
CFLAGS  += -std=c11 -D_POSIX_C_SOURCE=200809L -Wall -Wextra

BUILD   := build
TARGET  := analyzer

.PHONY: all test clean

all: $(TARGET)

$(BUILD):
	mkdir -p $@

$(BUILD)/parser.tab.c: parser.y | $(BUILD)
	$(BISON) -d -Wall -o $@ $<

$(BUILD)/parser.tab.h: $(BUILD)/parser.tab.c ;

$(BUILD)/lex.yy.c: lexer.l $(BUILD)/parser.tab.h
	$(FLEX) -o $@ $<

$(TARGET): $(BUILD)/parser.tab.c $(BUILD)/lex.yy.c
	$(CC) $(CFLAGS) -I$(BUILD) -o $@ $^

test: $(TARGET)
	./tests/run.sh ./$(TARGET)

clean:
	rm -rf $(BUILD) $(TARGET)
