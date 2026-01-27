#!/bin/bash
set -euo pipefail

# =========================
# CONFIG GENERAL
# =========================
REPO_LLAMA="https://github.com/ggml-org/llama.cpp"
BASE_DIR="$(pwd)"
LLAMA_DIR="$BASE_DIR/llama.cpp"
BUILD_DIR="$LLAMA_DIR/build"
MODELS_DIR="$LLAMA_DIR/models_multi"

PROMPT_PRUEBA='Hola, ¿quién eres? Responde en 1 frase.'
HILOS="${HILOS:-6}"
CTX="${CTX:-2048}"
TEMP="${TEMP:-0.8}"

# Token opcional (mejor para rate limits). huggingface-cli usa HF_TOKEN.
if [[ -n "${HUGGING_FACE_TOKEN:-}" ]]; then
  export HF_TOKEN="$HUGGING_FACE_TOKEN"
fi

# =========================
# COLORES + LOG
# =========================
VERDE='\033[0;32m'
ROJO='\033[0;31m'
AMARILLO='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${AMARILLO}[+] $*${NC}"; }
ok()   { echo -e "${VERDE}[*] $*${NC}"; }
fail() { echo -e "${ROJO}[X] $*${NC}"; }

# =========================
# UTILIDADES GGUF
# =========================
is_gguf() {
  local p="$1"
  [[ -f "$p" ]] || return 1
  python3 - <<PY "$p"
import sys
p=sys.argv[1]
with open(p,"rb") as f:
    sys.exit(0 if f.read(4)==b"GGUF" else 1)
PY
}

file_size() { stat -c%s "$1" 2>/dev/null || echo 0; }

validar_modelo() {
  local p="$1"
  local min_bytes="$2"
  is_gguf "$p" || return 1
  local sz
  sz="$(file_size "$p")"
  [[ "$sz" -ge "$min_bytes" ]] || return 1
  return 0
}

# =========================
# DEPENDENCIAS + BUILD
# =========================
instalar_deps() {
  log "Instalando dependencias..."
  sudo apt update
  sudo apt install -y build-essential cmake git curl python3 python3-pip

  # huggingface-cli (descargas robustas)
  python3 -m pip install -U "huggingface_hub[cli]" hf_transfer >/dev/null 2>&1 || true
  export HF_HUB_ENABLE_HF_TRANSFER=1
}

clonar_y_compilar_llama() {
  log "Clonando/actualizando llama.cpp..."
  if [[ ! -d "$LLAMA_DIR" ]]; then
    git clone "$REPO_LLAMA" "$LLAMA_DIR"
  else
    (cd "$LLAMA_DIR" && git pull) || true
  fi

  log "Compilando llama.cpp..."
  mkdir -p "$BUILD_DIR"
  ( cd "$BUILD_DIR"
    cmake ..
    cmake --build . --config Release -j"$(nproc)"
  )
}

detect_binario() {
  local candidates=(
    "$BUILD_DIR/bin/llama-run"
    "$BUILD_DIR/bin/llama-cli"
    "$BUILD_DIR/bin/main"
    "$BUILD_DIR/Release/bin/llama-run"
    "$BUILD_DIR/Release/bin/llama-cli"
    "$BUILD_DIR/Release/bin/main"
  )
  for b in "${candidates[@]}"; do
    if [[ -x "$b" ]]; then
      echo "$b"
      return 0
    fi
  done
  return 1
}

# =========================
# DESCARGA MODELOS (huggingface-cli)
# =========================
descargar_modelo() {
  local repo="$1"
  local filename="$2"
  local outdir="$3"

  mkdir -p "$outdir"
  log "Descargando: $repo :: $filename"

  # Descarga solo el archivo (no todo el repo)
  huggingface-cli download "$repo" "$filename" \
    --local-dir "$outdir" \
    --local-dir-use-symlinks False >/dev/null
}

# =========================
# EJECUCIÓN (según binario)
# =========================
run_once() {
  local bin="$1"
  local model_path="$2"
  local prompt="$3"

  local base
  base="$(basename "$bin")"

  if [[ "$base" == "llama-run" ]]; then
    "$bin" "$model_path" \
      --threads "$HILOS" \
      --temp "$TEMP" \
      --context-size "$CTX" \
      "$prompt"
    return $?
  fi

  # llama-cli o main (legacy) usan flags tipo -m -p
  "$bin" -m "$model_path" \
    -t "$HILOS" \
    -c "$CTX" \
    --temp "$TEMP" \
    -p "$prompt"
}

# Si falla por corrupción -> borra, re-descarga, reintenta 1 vez
run_model_con_autoreparacion() {
  local bin="$1"
  local model_path="$2"
  local min_bytes="$3"
  local repo="$4"
  local filename="$5"
  local outdir="$6"

  # 0) Validación previa: si está malo, re-descarga
  if ! validar_modelo "$model_path" "$min_bytes"; then
    log "Modelo inválido (GGUF/tamaño). Re-descargando..."
    rm -f "$model_path"
    descargar_modelo "$repo" "$filename" "$outdir"
  fi

  # 1) Primer intento
  set +e
  local output
  output="$(run_once "$bin" "$model_path" "$PROMPT_PRUEBA" 2>&1)"
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    echo "$output"
    return 0
  fi

  echo "$output" >&2

  # 2) Heurística de corrupción / truncado
  if echo "$output" | grep -qiE "model is corrupted|not within the file bounds|failed to load model|unable to load model|error loading model"; then
    log "Detectado fallo típico de archivo corrupto/incompleto. Borrando + re-descargando + reintentando (1 vez)..."
    rm -f "$model_path"
    descargar_modelo "$repo" "$filename" "$outdir"

    set +e
    output="$(run_once "$bin" "$model_path" "$PROMPT_PRUEBA" 2>&1)"
    rc=$?
    set -e

    if [[ $rc -eq 0 ]]; then
      echo "$output"
      return 0
    fi

    echo "$output" >&2
  fi

  return 1
}

# =========================
# LISTA DE MODELOS (5)
# Formato: ID|REPO|FILENAME|MIN_BYTES
# (MIN_BYTES es defensivo para evitar truncados)
# =========================
MODELS=(
  "gpt-oss-20b-q4_k_m|unsloth/gpt-oss-20b-GGUF|gpt-oss-20b-Q4_K_M.gguf|12000000000"
  "llama-3.1-8b-q4_k_m|bartowski/Meta-Llama-3.1-8B-Instruct-GGUF|Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf|3500000000"
  "mistral-7b-v0.3-q4_k_m|bartowski/Mistral-7B-Instruct-v0.3-GGUF|Mistral-7B-Instruct-v0.3-Q4_K_M.gguf|3500000000"
  "qwen2.5-7b-q4_k_m|bartowski/Qwen2.5-7B-Instruct-GGUF|Qwen2.5-7B-Instruct-Q4_K_M.gguf|3500000000"
  "phi-3.5-mini-q4_k_m|bartowski/Phi-3.5-mini-instruct-GGUF|Phi-3.5-mini-instruct-Q4_K_M.gguf|1500000000"
)

# =========================
# MAIN
# =========================
main() {
  instalar_deps
  clonar_y_compilar_llama

  # Binario real (autodetect)
  local BINARIO
  BINARIO="$(detect_binario || true)"
  if [[ -z "${BINARIO:-}" ]]; then
    fail "No encontré binarios ejecutables (llama-run/llama-cli/main)."
    log "Revisa: ls -lah '$BUILD_DIR/bin' || true"
    exit 1
  fi
  ok "Usando binario: $BINARIO"

  mkdir -p "$MODELS_DIR"

  log "Iniciando auto-setup de ${#MODELS[@]} modelos (GGUF)..."
  echo

  local -a RESUMEN=()

  for entry in "${MODELS[@]}"; do
    IFS="|" read -r ID REPO FILENAME MIN_BYTES <<<"$entry"
    local_dir="$MODELS_DIR/$ID"
    model_path="$local_dir/$FILENAME"

    echo -e "${AMARILLO}==============================${NC}"
    log "Modelo:  $ID"
    log "Repo:    $REPO"
    log "Archivo: $FILENAME"
    log "Ruta:    $model_path"
    echo

    # Descarga inicial si no existe
    if [[ ! -f "$model_path" ]]; then
      descargar_modelo "$REPO" "$FILENAME" "$local_dir"
    fi

    log "Probando inferencia..."
    if out="$(run_model_con_autoreparacion "$BINARIO" "$model_path" "$MIN_BYTES" "$REPO" "$FILENAME" "$local_dir")"; then
      ok "OK: $ID"
      echo "$out" | tail -n 20
      RESUMEN+=("$ID|OK")
    else
      fail "FAIL: $ID"
      RESUMEN+=("$ID|FAIL")
    fi
    echo
  done

  echo -e "${VERDE}========== RESUMEN ==========${NC}"
  for r in "${RESUMEN[@]}"; do
    IFS="|" read -r ID ST <<<"$r"
    printf "%-28s %s\n" "$ID" "$ST"
  done
  echo
  ok "Auto-setup terminado."
}

main "$@"
