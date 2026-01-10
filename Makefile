# SnakeBridge Development Makefile

.PHONY: test python-test help

test:
	@echo "Running tests..."
	mix snakebridge.python_test
	mix test --color

python-test:
	@echo "Running Python tests..."
	mix snakebridge.python_test

help:
	@echo "Available targets:"
	@echo "  test         - Run Python + Elixir tests"
	@echo "  python-test  - Run only Python tests"
