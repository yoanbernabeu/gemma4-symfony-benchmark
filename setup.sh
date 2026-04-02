#!/usr/bin/env bash
# =============================================================================
# Setup — Prépare le projet Symfony et la baseline pour le benchmark
# =============================================================================
set -euo pipefail

PROJECT_DIR="/tmp/test-gemma4-symfony"
RESULTS_DIR="/tmp/gemma4-benchmark-results"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Gemma4 Benchmark Setup ==="
echo ""

# 1. Vérifier les prérequis
echo "[1/7] Vérification des prérequis..."
command -v ollama >/dev/null 2>&1 || { echo "❌ ollama non trouvé. Installez-le depuis https://ollama.com"; exit 1; }
command -v opencode >/dev/null 2>&1 || { echo "❌ opencode non trouvé. Installez-le : curl -fsSL https://opencode.ai/install | bash"; exit 1; }
command -v symfony >/dev/null 2>&1 || { echo "❌ symfony CLI non trouvé. Installez-le depuis https://symfony.com/download"; exit 1; }
command -v php >/dev/null 2>&1 || { echo "❌ php non trouvé."; exit 1; }
echo "  ollama $(ollama --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -1)"
echo "  opencode $(opencode --version 2>&1)"
echo "  php $(php -r 'echo PHP_VERSION;')"
echo "  symfony $(symfony version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"

# 2. Créer le modèle Ollama avec 64k de contexte
echo ""
echo "[2/7] Création du modèle gemma4-opencode (64k ctx)..."
if ollama list 2>/dev/null | grep -q "gemma4-opencode"; then
    echo "  Modèle déjà existant, skip."
else
    ollama pull gemma4:latest
    ollama create gemma4-opencode -f "$SCRIPT_DIR/Modelfile"
    echo "  Modèle créé."
fi

# 3. Créer le projet Symfony
echo ""
echo "[3/7] Création du projet Symfony..."
if [[ -d "$PROJECT_DIR" ]]; then
    echo "  ⚠️  $PROJECT_DIR existe déjà. Suppression..."
    rm -rf "$PROJECT_DIR"
fi
symfony new "$PROJECT_DIR" --webapp
cd "$PROJECT_DIR"

# 4. Configurer SQLite
echo ""
echo "[4/7] Configuration SQLite..."
cat > .env.local << 'EOF'
DATABASE_URL="sqlite:///%kernel.project_dir%/var/data.db"
APP_SECRET=benchmarksecretkey123456
EOF

cat > .env.test.local << 'EOF'
DATABASE_URL="sqlite:///%kernel.project_dir%/var/test.db"
EOF

# 5. Copier la config OpenCode
echo ""
echo "[5/7] Configuration OpenCode..."
cp "$SCRIPT_DIR/opencode.json" "$PROJECT_DIR/opencode.json"

# 6. Committer la baseline
echo ""
echo "[6/7] Création de la baseline Git..."
git add -f opencode.json .env.local .env.test.local
git commit -m "Add benchmark config (OpenCode + SQLite)"

# 7. Sauvegarder le hash de référence
echo ""
echo "[7/7] Vérification..."
mkdir -p "$RESULTS_DIR"
git rev-parse HEAD > "$RESULTS_DIR/baseline_commit.txt"

php bin/console lint:container --env=dev 2>&1 | tail -1
php bin/console lint:yaml config/ 2>&1 | tail -1
php bin/console lint:twig templates/ 2>&1 | tail -1

echo ""
echo "✅ Setup terminé."
echo "   Projet : $PROJECT_DIR"
echo "   Baseline : $(cat $RESULTS_DIR/baseline_commit.txt)"
echo ""
echo "Lancez le benchmark avec :"
echo "   ./benchmark.sh          # 5 scénarios × 3 runs"
echo "   ./benchmark.sh S1 1     # Un seul test rapide"
