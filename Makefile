.PHONY: help install

help:
	@echo "AI Product Slice Harness"
	@echo "  ./bin/install [target-dir]   Install into a project (default: cwd)"
	@echo "  See README.md for phases and what you're getting into."

install:
	./bin/install "$(or $(TARGET),.)"
