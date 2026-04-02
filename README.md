# Benchmark : Gemma 4 E4B × OpenCode × Symfony 8

Protocole de benchmark pour tester les capacités de **Gemma 4 E4B** (modèle local via Ollama) comme assistant de code Symfony, piloté par **OpenCode**.

📖 **Article complet** : [yoandev.co/gemma4-opencode-benchmark](https://yoandev.co/gemma4-opencode-benchmark)

## Prérequis

- [Ollama](https://ollama.com) >= 0.20.0
- [OpenCode](https://opencode.ai) >= 1.2.0
- [Symfony CLI](https://symfony.com/download)
- PHP >= 8.4
- Python 3 (pour l'agrégation des résultats)

## Lancement rapide

```bash
# 1. Setup (crée le projet Symfony + modèle Ollama)
chmod +x setup.sh benchmark.sh
./setup.sh

# 2. Benchmark complet (5 scénarios × 3 runs, ~45 min)
./benchmark.sh

# 3. Ou un test rapide sur le scénario S1
./benchmark.sh S1 1
```

## Fichiers

| Fichier | Description |
|---------|-------------|
| `setup.sh` | Prépare le projet Symfony, le modèle Ollama et la baseline Git |
| `benchmark.sh` | Exécute les scénarios, valide le code et agrège les résultats |
| `opencode.json` | Configuration OpenCode pour Ollama + Gemma 4 |
| `Modelfile` | Modelfile Ollama avec `num_ctx 65536` |

## Les 5 scénarios

| ID | Description | Complexité |
|----|-------------|:----------:|
| S1 | Entity Doctrine + Repository | Basse |
| S2 | Controller + Routes + Templates Twig | Moyenne |
| S3 | Service + DI + Test unitaire PHPUnit | Moyenne |
| S4 | Form + Validation DTO + Controller | Haute |
| S5 | CRUD complet (Entity → Tests) | Très haute |

## Validation automatisée

Chaque run est validé par :
- `php -l` (syntaxe PHP)
- `php bin/console lint:container` (conteneur DI)
- `php bin/console lint:twig` (templates)
- `php bin/console doctrine:mapping:info` (entités)
- `php bin/console debug:router` (routes)
- `php bin/phpunit` (tests)

## Résultats

Les résultats sont sauvegardés dans `/tmp/gemma4-benchmark-results/<timestamp>/` :

```
summary.json          # Agrégation par scénario
all_results.json      # Détail des 15 runs
S1/run_1/
  result.json         # Score + métriques
  validation.json     # Détail de chaque check
  opencode_output.jsonl  # Sortie brute OpenCode
  response_text.md    # Réponse texte du modèle
```

## Machine de test

| | |
|-|-|
| MacBook Pro | M4 Pro, 14 cœurs, 24 GB RAM |
| macOS | 15.7.3 |
| Ollama | 0.20.0-rc1 |
| OpenCode | 1.2.15 |
| PHP | 8.5.3 |
| Symfony | 8.0.8 |

## Licence

MIT
