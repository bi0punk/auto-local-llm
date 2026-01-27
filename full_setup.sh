#!/bin/bash
set -euo pipefail

# ============================================================================
# llama.cpp Multi-Model Auto-Setup Script
# ============================================================================
# Automatiza la descarga, validación y prueba de múltiples modelos GGUF
# usando llama.cpp con manejo robusto de errores y recuperación automática.
# ============================================================================

# ============================================================================
# CONFIGURACIÓN GLOBAL
# ============================================================================
readonly SCRIPT_VERSION="2.0.1"
readonly REPO_LLAMA="https://github.com/ggml-org/llama.cpp"
readonly BASE_DIR="$(pwd)"
readonly LLAMA_DIR="$BASE_DIR/llama.cpp"
readonly BUILD_DIR="$LLAMA_DIR/build"
readonly MODELS_DIR="$LLAMA_DIR/models_multi"
readonly LOG_DIR="$BASE_DIR/logs"
readonly LOG_FILE="$LOG_DIR/setup_$(date +%Y%m%d_%H%M%S).log"

# Configuración de inferencia
readonly DEFAULT_PROMPT='Hola, ¿quién eres? Responde en 1 frase.'
readonly DEFAULT_THREADS="${HILOS:-$(nproc)}"
readonly DEFAULT_CTX="${CTX:-2048}"
readonly DEFAULT_TEMP="${TEMP:-0.8}"
readonly DEFAULT_MAX_TOKENS="${MAX_TOKENS:-100}"

# Control de comportamiento
readonly FORCE_REBUILD="${FORCE_REBUILD:-0}"
readonly SKIP_GIT_PULL="${SKIP_GIT_PULL:-0}"
readonly SKIP_TESTS="${SKIP_TESTS:-0}"
readonly PARALLEL_DOWNLOADS="${PARALLEL_DOWNLOADS:-1}"
readonly VERBOSE="${VERBOSE:-0}"
readonly DRY_RUN="${DRY_RUN:-0}"

# Configuración de Hugging Face
export PATH="$HOME/.local/bin:$PATH"
export HF_HUB_ENABLE_HF_TRANSFER=1
if [[ -n "${HUGGING_FACE_TOKEN:-}" ]]; then
  export HF_TOKEN="$HUGGING_FACE_TOKEN"
fi

# ============================================================================
# COLORES Y FORMATO
# ============================================================================
if [[ -t 1 ]]; then
  readonly COLOR_RESET='\033[0m'
  readonly COLOR_GREEN='\033[0;32m'
  readonly COLOR_RED='\033[0;31m'
  readonly COLOR_YELLOW='\033[1;33m'
  readonly COLOR_BLUE='\033[0;34m'
  readonly COLOR_MAGENTA='\033[0;35m'
  readonly COLOR_CYAN='\033[0;36m'
  readonly BOLD='\033[1m'
else
  readonly COLOR_RESET=''
  readonly COLOR_GREEN=''
  readonly COLOR_RED=''
  readonly COLOR_YELLOW=''
  readonly COLOR_BLUE=''
  readonly COLOR_MAGENTA=''
  readonly COLOR_CYAN=''
  readonly BOLD=''
fi

# ============================================================================
# FUNCIONES DE LOGGING
# ============================================================================
_log_base() {
  local level="$1"
  local color="$2"
  shift 2
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  local message="$*"
  
  echo -e "${color}[${level}]${COLOR_RESET} ${message}" >&2
  echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE"
}

log_info()    { _log_base "INFO" "${COLOR_BLUE}" "$@"; }
log_success() { _log_base "OK" "${COLOR_GREEN}" "$@"; }
log_warn()    { _log_base "WARN" "${COLOR_YELLOW}" "$@"; }
log_error()   { _log_base "ERROR" "${COLOR_RED}" "$@"; }
log_debug()   { [[ "$VERBOSE" == "1" ]] && _log_base "DEBUG" "${COLOR_CYAN}" "$@" || true; }

log_header() {
  echo -e "\n${BOLD}${COLOR_MAGENTA}==== $* ====${COLOR_RESET}\n"
  echo -e "\n==== $* ====\n" >> "$LOG_FILE"
}

# ============================================================================
# FUNCIONES DE VALIDACIÓN
# ============================================================================
check_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "Comando requerido no encontrado: $cmd"
    return 1
  fi
  return 0
}

is_gguf() {
  local filepath="$1"
  
  [[ -f "$filepath" ]] || return 1
  
  # Verificar magic number GGUF
  local magic
  magic="$(dd if="$filepath" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
  
  [[ "$magic" == "47475546" ]] || return 1
  return 0
}

get_file_size() {
  local filepath="$1"
  stat -c%s "$filepath" 2>/dev/null || echo 0
}

get_file_size_human() {
  local filepath="$1"
  numfmt --to=iec-i --suffix=B "$(get_file_size "$filepath")" 2>/dev/null || echo "0B"
}

validate_model() {
  local filepath="$1"
  local min_bytes="$2"
  
  log_debug "Validando modelo: $filepath"
  
  if ! [[ -f "$filepath" ]]; then
    log_debug "Archivo no existe"
    return 1
  fi
  
  if ! is_gguf "$filepath"; then
    log_error "Archivo no es un GGUF válido: $filepath"
    return 1
  fi
  
  local size
  size="$(get_file_size "$filepath")"
  
  # Permitir una tolerancia del 5% menos del mínimo esperado
  # Esto evita falsos positivos por diferencias de compresión o metadatos
  local min_with_tolerance=$((min_bytes * 95 / 100))
  
  if [[ "$size" -lt "$min_with_tolerance" ]]; then
    log_error "Archivo demasiado pequeño: $(get_file_size_human "$filepath")"
    log_error "Tamaño actual: $(get_file_size_human "$size")"
    log_error "Mínimo esperado (con tolerancia): $(get_file_size_human "$min_with_tolerance")"
    return 1
  fi
  
  log_debug "Modelo válido: $(get_file_size_human "$filepath")"
  return 0
}

verify_checksum() {
  local filepath="$1"
  local expected_sha256="$2"
  
  [[ -z "$expected_sha256" ]] && return 0
  
  log_debug "Verificando checksum SHA256..."
  
  local actual_sha256
  actual_sha256="$(sha256sum "$filepath" | awk '{print $1}')"
  
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    log_error "Checksum no coincide para $filepath"
    log_error "Esperado: $expected_sha256"
    log_error "Actual:   $actual_sha256"
    return 1
  fi
  
  log_debug "Checksum verificado correctamente"
  return 0
}

# ============================================================================
# GESTIÓN DE DEPENDENCIAS
# ============================================================================
install_system_dependencies() {
  log_header "Instalando Dependencias del Sistema"
  
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[DRY-RUN] Se instalarían dependencias del sistema"
    return 0
  fi
  
  local packages=(
    build-essential
    cmake
    git
    curl
    wget
    python3
    python3-pip
    python3-venv
    libgomp1
    ccache
  )
  
  log_info "Actualizando índice de paquetes..."
  sudo apt-get update -qq || log_warn "No se pudo actualizar el índice de paquetes"
  
  log_info "Instalando: ${packages[*]}"
  sudo apt-get install -y -qq "${packages[@]}" || {
    log_error "Falló la instalación de dependencias del sistema"
    return 1
  }
  
  log_success "Dependencias del sistema instaladas"
}

install_python_dependencies() {
  log_header "Instalando Dependencias de Python"
  
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[DRY-RUN] Se instalarían dependencias de Python"
    return 0
  fi
  
  log_info "Actualizando pip..."
  python3 -m pip install --user --upgrade pip >/dev/null 2>&1 || {
    log_warn "No se pudo actualizar pip"
  }
  
  local py_packages=(
    "huggingface_hub[cli]>=0.20.0"
    "hf_transfer>=0.1.0"
    "requests>=2.31.0"
    "tqdm>=4.65.0"
  )
  
  log_info "Instalando paquetes Python: ${py_packages[*]}"
  python3 -m pip install --user --upgrade "${py_packages[@]}" >/dev/null 2>&1 || {
    log_error "Falló la instalación de paquetes Python"
    return 1
  }
  
  log_success "Dependencias de Python instaladas"
  
  # Verificar que tqdm está disponible
  if python3 -c "import tqdm" 2>/dev/null; then
    log_success "tqdm disponible para barras de progreso"
  else
    log_warn "tqdm no disponible, se usarán métodos alternativos"
  fi
}

# ============================================================================
# GESTIÓN DE llama.cpp
# ============================================================================
detect_llama_binary() {
  local candidates=(
    "$BUILD_DIR/bin/llama-cli"
    "$BUILD_DIR/bin/llama-run"
    "$BUILD_DIR/bin/main"
    "$BUILD_DIR/Release/bin/llama-cli"
    "$BUILD_DIR/Release/bin/llama-run"
    "$BUILD_DIR/Release/bin/main"
  )
  
  for binary in "${candidates[@]}"; do
    if [[ -x "$binary" ]]; then
      echo "$binary"
      return 0
    fi
  done
  
  return 1
}

clone_or_update_llama() {
  log_header "Configurando llama.cpp"
  
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[DRY-RUN] Se clona/actualizaría llama.cpp"
    return 0
  fi
  
  if [[ -d "$LLAMA_DIR/.git" ]]; then
    log_success "Repositorio llama.cpp ya existe"
    
    if [[ "$SKIP_GIT_PULL" == "1" ]]; then
      log_info "SKIP_GIT_PULL=1: omitiendo actualización"
    else
      log_info "Actualizando repositorio..."
      (
        cd "$LLAMA_DIR"
        local current_commit
        current_commit="$(git rev-parse --short HEAD)"
        
        git fetch origin
        git pull origin master || git pull origin main || {
          log_warn "No se pudo actualizar el repositorio"
          return 0
        }
        
        local new_commit
        new_commit="$(git rev-parse --short HEAD)"
        
        if [[ "$current_commit" != "$new_commit" ]]; then
          log_success "Actualizado de $current_commit a $new_commit"
        else
          log_info "Ya está actualizado ($current_commit)"
        fi
      )
    fi
  elif [[ -d "$LLAMA_DIR" ]]; then
    log_error "Existe $LLAMA_DIR pero no es un repositorio git"
    log_error "Solución: mv $LLAMA_DIR ${LLAMA_DIR}.backup && rerun"
    return 1
  else
    log_info "Clonando llama.cpp desde $REPO_LLAMA..."
    git clone --depth=1 "$REPO_LLAMA" "$LLAMA_DIR" || {
      log_error "Falló la clonación del repositorio"
      return 1
    }
    log_success "Repositorio clonado"
  fi
}

build_llama() {
  log_header "Compilando llama.cpp"
  
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[DRY-RUN] Se compilaría llama.cpp"
    return 0
  fi
  
  local existing_binary
  existing_binary="$(detect_llama_binary || true)"
  
  if [[ -n "${existing_binary:-}" && "$FORCE_REBUILD" != "1" ]]; then
    log_success "Binario ya existe: $existing_binary"
    log_info "Use FORCE_REBUILD=1 para forzar recompilación"
    return 0
  fi
  
  log_info "Configurando build con CMake..."
  mkdir -p "$BUILD_DIR"
  
  (
    cd "$BUILD_DIR"
    
    # Limpiar build anterior si es rebuild forzado
    if [[ "$FORCE_REBUILD" == "1" && -f "CMakeCache.txt" ]]; then
      log_info "Limpiando build anterior..."
      rm -rf ./*
    fi
    
    # Configurar con optimizaciones
    cmake .. \
      -DCMAKE_BUILD_TYPE=Release \
      -DLLAMA_NATIVE=ON \
      -DLLAMA_BUILD_TESTS=OFF \
      -DLLAMA_BUILD_EXAMPLES=ON \
      -DCMAKE_C_COMPILER_LAUNCHER=ccache \
      -DCMAKE_CXX_COMPILER_LAUNCHER=ccache || {
      log_error "Falló la configuración de CMake"
      return 1
    }
    
    # Compilar con todos los núcleos disponibles
    local num_jobs
    num_jobs="$(nproc)"
    log_info "Compilando con $num_jobs jobs..."
    
    cmake --build . --config Release -j"$num_jobs" -- -s || {
      log_error "Falló la compilación"
      return 1
    }
  )
  
  local new_binary
  new_binary="$(detect_llama_binary || true)"
  
  if [[ -z "${new_binary:-}" ]]; then
    log_error "No se encontró binario después de compilar"
    return 1
  fi
  
  log_success "Compilación exitosa: $new_binary"
}

# ============================================================================
# BARRA DE PROGRESO
# ============================================================================
show_progress_bar() {
  local current="$1"
  local total="$2"
  local width=50
  local percentage=0
  
  if [[ "$total" -gt 0 ]]; then
    percentage=$((current * 100 / total))
  fi
  
  local filled=$((width * current / total))
  [[ "$filled" -gt "$width" ]] && filled=$width
  
  local empty=$((width - filled))
  
  # Construir barra
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done
  
  # Tamaños legibles
  local current_human
  local total_human
  current_human="$(numfmt --to=iec-i --suffix=B "$current" 2>/dev/null || echo "${current}B")"
  total_human="$(numfmt --to=iec-i --suffix=B "$total" 2>/dev/null || echo "${total}B")"
  
  # Mostrar barra (con \r para actualizar en la misma línea)
  printf "\r${COLOR_CYAN}[${bar}]${COLOR_RESET} %3d%% ${COLOR_YELLOW}%s${COLOR_RESET} / ${COLOR_GREEN}%s${COLOR_RESET}" \
    "$percentage" "$current_human" "$total_human"
}

# Función para obtener el tamaño del archivo remoto
get_remote_file_size() {
  local url="$1"
  local auth_header="${2:-}"
  
  local size=0
  
  if [[ -n "$auth_header" ]]; then
    size=$(curl -sI -L -H "$auth_header" "$url" | grep -i "content-length" | tail -1 | awk '{print $2}' | tr -d '\r')
  else
    size=$(curl -sI -L "$url" | grep -i "content-length" | tail -1 | awk '{print $2}' | tr -d '\r')
  fi
  
  echo "${size:-0}"
}

# Descarga con barra de progreso usando curl
download_with_progress_curl() {
  local url="$1"
  local output="$2"
  local auth_header="${3:-}"
  
  log_info "Obteniendo información del archivo..."
  
  # Obtener tamaño total
  local total_size
  total_size=$(get_remote_file_size "$url" "$auth_header")
  
  if [[ "$total_size" -eq 0 ]]; then
    log_warn "No se pudo obtener tamaño del archivo, descargando sin barra de progreso..."
    
    local curl_opts=(
      -L
      --fail
      --retry 5
      --retry-delay 3
      --connect-timeout 30
      --max-time 7200
      -#
    )
    
    [[ -n "$auth_header" ]] && curl_opts+=(-H "$auth_header")
    
    curl "${curl_opts[@]}" "$url" -o "$output"
    return $?
  fi
  
  log_info "Tamaño: $(numfmt --to=iec-i --suffix=B "$total_size")"
  echo ""
  
  # Descarga con progreso
  local curl_opts=(
    -L
    --fail
    --retry 5
    --retry-delay 3
    --connect-timeout 30
    --max-time 7200
  )
  
  [[ -n "$auth_header" ]] && curl_opts+=(-H "$auth_header")
  
  # Usar proceso en background para actualizar barra
  (
    while true; do
      if [[ -f "$output" ]]; then
        local current_size
        current_size=$(stat -c%s "$output" 2>/dev/null || echo 0)
        show_progress_bar "$current_size" "$total_size"
        
        [[ "$current_size" -ge "$total_size" ]] && break
      fi
      sleep 0.5
    done
    echo ""  # Nueva línea al terminar
  ) &
  
  local progress_pid=$!
  
  # Descargar archivo
  curl "${curl_opts[@]}" "$url" -o "$output" 2>/dev/null
  local result=$?
  
  # Detener proceso de progreso
  kill "$progress_pid" 2>/dev/null
  wait "$progress_pid" 2>/dev/null
  
  # Mostrar barra final al 100%
  if [[ $result -eq 0 && -f "$output" ]]; then
    local final_size
    final_size=$(stat -c%s "$output" 2>/dev/null || echo 0)
    show_progress_bar "$final_size" "$total_size"
    echo ""
  fi
  
  return $result
}

# Descarga con Python y barra de progreso
download_with_progress_python() {
  local repo="$1"
  local filename="$2"
  local outdir="$3"
  
  python3 - <<PYEOF "$repo" "$filename" "$outdir"
import sys
import os
from pathlib import Path

try:
    from huggingface_hub import hf_hub_download
    from tqdm import tqdm
except ImportError:
    print("Error: huggingface_hub o tqdm no disponibles", file=sys.stderr)
    sys.exit(1)

repo_id = sys.argv[1]
filename = sys.argv[2]
local_dir = sys.argv[3]

# Configurar barra de progreso
class TqdmProgress:
    def __init__(self):
        self.pbar = None
    
    def __call__(self, current, total):
        if self.pbar is None:
            self.pbar = tqdm(
                total=total,
                unit='B',
                unit_scale=True,
                unit_divisor=1024,
                desc=f"Descargando {filename}",
                ncols=100,
                bar_format='{desc}: {percentage:3.0f}%|{bar}| {n_fmt}/{total_fmt} [{elapsed}<{remaining}]'
            )
        self.pbar.update(current - self.pbar.n)

try:
    progress = TqdmProgress()
    hf_hub_download(
        repo_id=repo_id,
        filename=filename,
        local_dir=local_dir,
        local_dir_use_symlinks=False,
        resume_download=True,
    )
    
    if progress.pbar:
        progress.pbar.close()
    
    print()  # Nueva línea
    sys.exit(0)
    
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

# ============================================================================
# DESCARGA DE MODELOS
# ============================================================================
download_with_hf_cli() {
  local repo="$1"
  local filename="$2"
  local outdir="$3"
  local target="$outdir/$filename"
  
  mkdir -p "$outdir"
  
  log_info "Descargando: ${COLOR_CYAN}$filename${COLOR_RESET}"
  log_info "Repositorio: ${COLOR_BLUE}$repo${COLOR_RESET}"
  
  # Verificar si ya existe y está completo
  if [[ -f "$target" ]]; then
    if is_gguf "$target"; then
      local size
      size="$(get_file_size "$target")"
      
      # Si el archivo es > 1MB, asumimos que está completo o casi completo
      # (Hugging Face Hub reanudará la descarga si está incompleto)
      if [[ "$size" -gt 1048576 ]]; then
        log_info "Archivo parcial encontrado ($(get_file_size_human "$size"))"
        log_info "La descarga se reanudará desde donde se quedó"
      fi
    else
      log_warn "Archivo existe pero está corrupto, eliminando..."
      rm -f "$target"
    fi
  fi
  
  # Método 1: Python con tqdm (mejor barra de progreso)
  if python3 -c "import huggingface_hub, tqdm" 2>/dev/null; then
    log_debug "Intentando con Python + tqdm (barra de progreso)..."
    
    if download_with_progress_python "$repo" "$filename" "$outdir"; then
      log_success "✓ Descargado con Python + tqdm"
      return 0
    fi
  fi
  
  # Método 2: hf download (CLI nuevo) - sin quiet para ver progreso
  if command -v hf >/dev/null 2>&1; then
    log_debug "Intentando con 'hf download'..."
    echo ""
    
    if hf download "$repo" "$filename" \
        --local-dir "$outdir" 2>&1 | grep -v "^Fetching"; then
      echo ""
      log_success "✓ Descargado con 'hf download'"
      return 0
    fi
  fi
  
  # Método 3: huggingface-cli (legacy) - con progreso
  if command -v huggingface-cli >/dev/null 2>&1; then
    log_debug "Intentando con 'huggingface-cli'..."
    echo ""
    
    if huggingface-cli download "$repo" "$filename" \
        --local-dir "$outdir" \
        --local-dir-use-symlinks False 2>&1; then
      echo ""
      log_success "✓ Descargado con 'huggingface-cli'"
      return 0
    fi
  fi
  
  # Método 4: Descarga directa con curl y barra personalizada
  log_warn "Fallback a descarga directa con curl"
  
  local url="https://huggingface.co/${repo}/resolve/main/${filename}"
  local auth_header=""
  
  if [[ -n "${HF_TOKEN:-}" ]]; then
    auth_header="Authorization: Bearer ${HF_TOKEN}"
  fi
  
  if download_with_progress_curl "$url" "$target" "$auth_header"; then
    log_success "✓ Descargado con curl"
    return 0
  fi
  
  log_error "✗ Fallaron todos los métodos de descarga"
  return 1
}

# ============================================================================
# EJECUCIÓN DE MODELOS
# ============================================================================
run_inference() {
  local binary="$1"
  local model_path="$2"
  local prompt="${3:-$DEFAULT_PROMPT}"
  
  local binary_name
  binary_name="$(basename "$binary")"
  
  log_debug "Ejecutando inferencia con $binary_name"
  
  # Argumentos comunes
  local common_args=(
    --threads "$DEFAULT_THREADS"
    --ctx-size "$DEFAULT_CTX"
    --temp "$DEFAULT_TEMP"
    --n-predict "$DEFAULT_MAX_TOKENS"
  )
  
  if [[ "$binary_name" == "llama-run" ]]; then
    "$binary" "$model_path" "${common_args[@]}" "$prompt"
  else
    # llama-cli o main
    "$binary" -m "$model_path" "${common_args[@]}" -p "$prompt"
  fi
}

test_model_with_recovery() {
  local binary="$1"
  local model_path="$2"
  local min_bytes="$3"
  local repo="$4"
  local filename="$5"
  local outdir="$6"
  local checksum="${7:-}"
  
  local max_attempts=2
  local attempt=1
  
  while [[ $attempt -le $max_attempts ]]; do
    log_debug "Intento $attempt de $max_attempts"
    
    # Validar modelo
    if ! validate_model "$model_path" "$min_bytes"; then
      log_warn "Modelo inválido, re-descargando..."
      rm -f "$model_path"
      download_with_hf_cli "$repo" "$filename" "$outdir" || return 1
      
      if [[ -n "$checksum" ]]; then
        verify_checksum "$model_path" "$checksum" || {
          log_error "Checksum inválido después de re-descarga"
          return 1
        }
      fi
    fi
    
    # Ejecutar inferencia
    local output
    local exit_code
    
    set +e
    output="$(run_inference "$binary" "$model_path" "$DEFAULT_PROMPT" 2>&1)"
    exit_code=$?
    set -e
    
    if [[ $exit_code -eq 0 ]]; then
      echo "$output"
      return 0
    fi
    
    # Analizar error
    if echo "$output" | grep -qiE "model is corrupted|not within the file bounds|failed to load|unable to load|error loading"; then
      log_error "Error detectado (posible corrupción): intento $attempt"
      echo "$output" >&2
      
      if [[ $attempt -lt $max_attempts ]]; then
        log_warn "Re-descargando modelo..."
        rm -f "$model_path"
        download_with_hf_cli "$repo" "$filename" "$outdir" || return 1
      fi
    else
      log_error "Error desconocido en inferencia"
      echo "$output" >&2
      return 1
    fi
    
    ((attempt++))
  done
  
  log_error "Agotados todos los intentos de recuperación"
  return 1
}

# ============================================================================
# DEFINICIÓN DE MODELOS
# ============================================================================
# Formato: ID|REPO|FILENAME|MIN_BYTES|SHA256(opcional)
# MIN_BYTES debe ser ~95% del tamaño real para permitir variaciones
declare -a MODELS=(
  "gpt-oss-20b-q4_k_m|unsloth/gpt-oss-20b-GGUF|gpt-oss-20b-Q4_K_M.gguf|11000000000|"
  "llama-3.1-8b-q4_k_m|bartowski/Meta-Llama-3.1-8B-Instruct-GGUF|Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf|4600000000|"
  "mistral-7b-v0.3-q4_k_m|bartowski/Mistral-7B-Instruct-v0.3-GGUF|Mistral-7B-Instruct-v0.3-Q4_K_M.gguf|3800000000|"
  "qwen2.5-7b-q4_k_m|bartowski/Qwen2.5-7B-Instruct-GGUF|Qwen2.5-7B-Instruct-Q4_K_M.gguf|4100000000|"
  "phi-3.5-mini-q4_k_m|bartowski/Phi-3.5-mini-instruct-GGUF|Phi-3.5-mini-instruct-Q4_K_M.gguf|2100000000|"
)

# ============================================================================
# PROCESAMIENTO DE MODELOS
# ============================================================================
process_single_model() {
  local entry="$1"
  
  IFS="|" read -r model_id repo filename min_bytes checksum <<< "$entry"
  
  local model_dir="$MODELS_DIR/$model_id"
  local model_path="$model_dir/$filename"
  
  log_header "Procesando: $model_id"
  
  log_info "Repositorio: $repo"
  log_info "Archivo: $filename"
  log_info "Tamaño mínimo esperado: ~$(numfmt --to=iec-i --suffix=B "$min_bytes")"
  log_info "Destino: $model_path"
  
  # Verificar si el archivo ya existe y es válido
  if [[ -f "$model_path" ]]; then
    log_info "Archivo encontrado, verificando validez..."
    
    # Validar con tolerancia del 5%
    local size
    size="$(get_file_size "$model_path")"
    local min_with_tolerance=$((min_bytes * 95 / 100))
    
    if is_gguf "$model_path" && [[ "$size" -ge "$min_with_tolerance" ]]; then
      log_success "Modelo ya existe y es válido: $(get_file_size_human "$model_path")"
      
      # Verificar checksum si está disponible
      if [[ -n "$checksum" ]]; then
        if verify_checksum "$model_path" "$checksum"; then
          log_success "Checksum verificado correctamente"
        else
          log_warn "Checksum no coincide, re-descargando..."
          rm -f "$model_path"
        fi
      fi
      
      # Si llegamos aquí y el archivo existe, omitir descarga
      if [[ -f "$model_path" ]]; then
        log_info "Omitiendo descarga (archivo ya válido)"
      else
        log_info "Descargando modelo..."
        download_with_hf_cli "$repo" "$filename" "$model_dir" || {
          log_error "Falló la descarga de $model_id"
          return 1
        }
      fi
    else
      log_warn "Archivo existe pero no es válido (tamaño: $(get_file_size_human "$size"))"
      log_info "Re-descargando modelo..."
      rm -f "$model_path"
      download_with_hf_cli "$repo" "$filename" "$model_dir" || {
        log_error "Falló la descarga de $model_id"
        return 1
      }
    fi
  else
    log_info "Modelo no encontrado, descargando..."
    download_with_hf_cli "$repo" "$filename" "$model_dir" || {
      log_error "Falló la descarga de $model_id"
      return 1
    }
  fi
  
  # Verificar checksum final si está disponible
  if [[ -n "$checksum" && -f "$model_path" ]]; then
    verify_checksum "$model_path" "$checksum" || {
      log_error "Checksum inválido para $model_id"
      return 1
    }
  fi
  
  # Probar modelo (si no se omiten tests)
  if [[ "$SKIP_TESTS" == "1" ]]; then
    log_info "SKIP_TESTS=1: omitiendo prueba de inferencia"
    return 0
  fi
  
  local binary
  binary="$(detect_llama_binary)"
  
  log_info "Probando inferencia..."
  
  local output
  if output="$(test_model_with_recovery "$binary" "$model_path" "$min_bytes" "$repo" "$filename" "$model_dir" "$checksum")"; then
    log_success "✓ Inferencia exitosa para $model_id"
    
    if [[ "$VERBOSE" == "1" ]]; then
      echo -e "\n${COLOR_CYAN}--- Salida del modelo ---${COLOR_RESET}"
      echo "$output" | tail -n 20
      echo -e "${COLOR_CYAN}-------------------------${COLOR_RESET}\n"
    fi
    
    return 0
  else
    log_error "✗ Inferencia falló para $model_id"
    return 1
  fi
}

# ============================================================================
# FUNCIÓN PRINCIPAL
# ============================================================================
print_banner() {
  cat << 'EOF'
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║  llama.cpp Multi-Model Auto-Setup Script                 ║
║  Version 2.0.0                                            ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
}

print_configuration() {
  log_header "Configuración"
  
  echo "Directorio base:      $BASE_DIR"
  echo "Directorio llama.cpp: $LLAMA_DIR"
  echo "Directorio modelos:   $MODELS_DIR"
  echo "Archivo de log:       $LOG_FILE"
  echo ""
  echo "Threads:              $DEFAULT_THREADS"
  echo "Context size:         $DEFAULT_CTX"
  echo "Temperature:          $DEFAULT_TEMP"
  echo "Max tokens:           $DEFAULT_MAX_TOKENS"
  echo ""
  echo "Force rebuild:        $FORCE_REBUILD"
  echo "Skip git pull:        $SKIP_GIT_PULL"
  echo "Skip tests:           $SKIP_TESTS"
  echo "Verbose:              $VERBOSE"
  echo "Dry run:              $DRY_RUN"
  echo ""
}

generate_summary_report() {
  local -n results=$1
  
  log_header "Resumen de Resultados"
  
  local total=${#results[@]}
  local successful=0
  local failed=0
  
  echo -e "${BOLD}Modelo${COLOR_RESET}                       ${BOLD}Estado${COLOR_RESET}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  for result in "${results[@]}"; do
    IFS="|" read -r model_id status <<< "$result"
    
    printf "%-30s " "$model_id"
    
    if [[ "$status" == "OK" ]]; then
      echo -e "${COLOR_GREEN}✓ OK${COLOR_RESET}"
      ((successful++))
    else
      echo -e "${COLOR_RED}✗ FAIL${COLOR_RESET}"
      ((failed++))
    fi
  done
  
  echo ""
  echo -e "${BOLD}Total:${COLOR_RESET}        $total"
  echo -e "${COLOR_GREEN}Exitosos:${COLOR_RESET}     $successful"
  echo -e "${COLOR_RED}Fallidos:${COLOR_RESET}     $failed"
  echo ""
  
  if [[ $failed -gt 0 ]]; then
    log_warn "Algunos modelos fallaron. Revisa el log: $LOG_FILE"
    return 1
  else
    log_success "Todos los modelos procesados exitosamente"
    return 0
  fi
}

main() {
  # Crear directorio de logs
  mkdir -p "$LOG_DIR"
  
  # Banner
  print_banner
  echo ""
  
  # Mostrar configuración
  print_configuration
  
  # Validar comandos básicos
  for cmd in git cmake python3 pip; do
    check_command "$cmd" || {
      log_error "Comando requerido no disponible: $cmd"
      exit 1
    }
  done
  
  # Instalar dependencias
  install_system_dependencies || exit 1
  install_python_dependencies || exit 1
  
  # Configurar llama.cpp
  clone_or_update_llama || exit 1
  build_llama || exit 1
  
  # Detectar binario
  local BINARY
  BINARY="$(detect_llama_binary || true)"
  
  if [[ -z "${BINARY:-}" ]]; then
    log_error "No se encontró binario ejecutable de llama.cpp"
    log_error "Ubicaciones revisadas: $BUILD_DIR/bin, $BUILD_DIR/Release/bin"
    exit 1
  fi
  
  log_success "Binario detectado: $BINARY"
  
  # Crear directorio de modelos
  mkdir -p "$MODELS_DIR"
  
  # Procesar modelos
  log_header "Procesando ${#MODELS[@]} Modelos"
  
  declare -a RESULTS=()
  
  for model_entry in "${MODELS[@]}"; do
    IFS="|" read -r model_id _ _ _ _ <<< "$model_entry"
    
    if process_single_model "$model_entry"; then
      RESULTS+=("$model_id|OK")
    else
      RESULTS+=("$model_id|FAIL")
    fi
    
    echo ""
  done
  
  # Generar reporte final
  generate_summary_report RESULTS
  local exit_code=$?
  
  # Mensaje final
  echo ""
  log_info "Ejecución completa. Log guardado en: $LOG_FILE"
  log_info "Tip: Use VERBOSE=1 para ver salidas detalladas"
  log_info "Tip: Use DRY_RUN=1 para simular sin ejecutar"
  echo ""
  
  exit $exit_code
}

# ============================================================================
# MANEJO DE SEÑALES
# ============================================================================
cleanup() {
  log_warn "Recibida señal de interrupción, limpiando..."
  exit 130
}

trap cleanup SIGINT SIGTERM

# ============================================================================
# PUNTO DE ENTRADA
# ============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi