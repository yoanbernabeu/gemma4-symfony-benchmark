# Benchmark: Gemma 4 E4B × OpenCode × Symfony 8

Benchmark protocol to test **Gemma 4 E4B** (local model via Ollama) as a Symfony coding assistant, powered by **OpenCode**.

📖 **Full article (FR)**: [yoandev.co/gemma4-opencode-benchmark](https://yoandev.co/gemma4-opencode-benchmark)

## Prerequisites

- [Ollama](https://ollama.com) >= 0.20.0
- [OpenCode](https://opencode.ai) >= 1.2.0
- [Symfony CLI](https://symfony.com/download)
- PHP >= 8.4
- Python 3 (for results aggregation)

## Quick Start

```bash
# 1. Setup (creates Symfony project + Ollama model)
chmod +x setup.sh benchmark.sh
./setup.sh

# 2. Full benchmark (5 scenarios × 3 runs, ~45 min)
./benchmark.sh

# 3. Or a quick single test
./benchmark.sh S1 1
```

## Files

| File | Description |
|------|-------------|
| `setup.sh` | Creates Symfony project, Ollama model with 64k context, Git baseline |
| `benchmark.sh` | Runs all scenarios, validates generated code, aggregates results |
| `opencode.json` | OpenCode configuration for Ollama + Gemma 4 |
| `Modelfile` | Ollama Modelfile with `num_ctx 65536` |

## The 5 Scenarios

| ID | Description | Complexity |
|----|-------------|:----------:|
| S1 | Doctrine Entity + Repository | Low |
| S2 | Controller + Routes + Twig Templates | Medium |
| S3 | Service + DI + PHPUnit Test | Medium |
| S4 | Form + Validation DTO + Controller | High |
| S5 | Full CRUD (Entity → Tests) | Very High |

## Automated Validation

Each run is validated by:
- `php -l` (PHP syntax check)
- `php bin/console lint:container` (DI container compilation)
- `php bin/console lint:twig` (Twig template syntax)
- `php bin/console doctrine:mapping:info` (entity mapping)
- `php bin/console debug:router` (route registration)
- `php bin/phpunit` (unit/functional tests)

## Results

Raw results from our benchmark run are available in the [`results/`](./results) directory.

When you run the benchmark yourself, results are saved in `/tmp/gemma4-benchmark-results/<timestamp>/`:

```
summary.json             # Per-scenario aggregation
all_results.json         # All 15 runs detailed
S1/run_1/
  result.json            # Score + metrics
  validation.json        # Each check detailed
  opencode_output.jsonl  # Raw OpenCode output
  response_text.md       # Model's text response
```

## Test Machine

| | |
|-|-|
| MacBook Pro | M4 Pro, 14 cores, 24 GB RAM |
| macOS | 15.7.3 |
| Ollama | 0.20.0-rc1 |
| OpenCode | 1.2.15 |
| PHP | 8.5.3 |
| Symfony | 8.0.8 |

## License

MIT - Yoan Bernabeu 2026
