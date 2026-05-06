#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEPA_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${GEPA_ROOT}/../.." && pwd)"

BENCHMARK="arc1"
PROVIDER_ENV_FILE=""
REFLECTION_ENV_FILE=""
TASK_MAP=""
SOURCE_ROOT="${REPO_ROOT}"
GENERATIONS=10
WORKERS=4
MAX_LLM_CALLS_PER_TASK=1
TEMPERATURE=0.2
MAX_REFLECTION_TASKS=4
SEED=0
RUN_DIR=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [-- extra-python-args]

Options:
  --benchmark <arc1|arc2>
  --provider-env-file <path>
  --reflection-env-file <path>
  --task-map <path>
  --source-root <path>
  --generations <int>
  --workers <int>
  --max-llm-calls-per-task <int>
  --temperature <float>
  --max-reflection-tasks <int>
  --seed <int>
  --run-dir <path>
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --benchmark) BENCHMARK="$2"; shift 2 ;;
    --provider-env-file) PROVIDER_ENV_FILE="$2"; shift 2 ;;
    --reflection-env-file) REFLECTION_ENV_FILE="$2"; shift 2 ;;
    --task-map) TASK_MAP="$2"; shift 2 ;;
    --source-root) SOURCE_ROOT="$2"; shift 2 ;;
    --generations) GENERATIONS="$2"; shift 2 ;;
    --workers) WORKERS="$2"; shift 2 ;;
    --max-llm-calls-per-task) MAX_LLM_CALLS_PER_TASK="$2"; shift 2 ;;
    --temperature) TEMPERATURE="$2"; shift 2 ;;
    --max-reflection-tasks) MAX_REFLECTION_TASKS="$2"; shift 2 ;;
    --seed) SEED="$2"; shift 2 ;;
    --run-dir) RUN_DIR="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    --) shift; break ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -n "${PROVIDER_ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${PROVIDER_ENV_FILE}"
  set +a
fi

if [[ -n "${REFLECTION_ENV_FILE}" ]]; then
  REFLECTION_ENV_INFO="$(
    python3 - <<'PY' "${REFLECTION_ENV_FILE}"
from pathlib import Path
import sys
provider = ""
model = ""
for line in Path(sys.argv[1]).read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    if key == "MODEL_PROVIDER":
        provider = value.strip()
    elif key == "MODEL":
        model = value.strip()
print(f"{provider}|{model}")
PY
  )"
  export REFLECTION_MODEL_PROVIDER="${REFLECTION_ENV_INFO%%|*}"
  export REFLECTION_MODEL="${REFLECTION_ENV_INFO#*|}"
fi

export PYTHONPATH="${GEPA_ROOT}/src:${PYTHONPATH:-}"
PYTHON_BIN="${GEPA_ROOT}/.venv/bin/python"

if [[ ! -x "${PYTHON_BIN}" ]]; then
  echo "Missing GEPA virtualenv interpreter at ${PYTHON_BIN}. Run 'uv sync --extra full' in baselines/gepa first." >&2
  exit 1
fi

CMD=(
  "${PYTHON_BIN}" "${GEPA_ROOT}/examples/swarms_arc/train_arc_policy.py"
  --benchmark "${BENCHMARK}"
  --source-root "${SOURCE_ROOT}"
  --generations "${GENERATIONS}"
  --workers "${WORKERS}"
  --max-llm-calls-per-task "${MAX_LLM_CALLS_PER_TASK}"
  --temperature "${TEMPERATURE}"
  --max-reflection-tasks "${MAX_REFLECTION_TASKS}"
  --seed "${SEED}"
)

if [[ -n "${TASK_MAP}" ]]; then
  CMD+=(--task-map "${TASK_MAP}")
fi

if [[ -n "${RUN_DIR}" ]]; then
  CMD+=(--run-dir "${RUN_DIR}")
fi

if [[ -n "${REFLECTION_MODEL_PROVIDER:-}" || -n "${REFLECTION_MODEL:-}" ]]; then
  CMD+=(--reflection-provider "${REFLECTION_MODEL_PROVIDER:-}" --reflection-model "${REFLECTION_MODEL:-}")
fi

CMD+=("$@")

cd "${REPO_ROOT}"
exec "${CMD[@]}"
