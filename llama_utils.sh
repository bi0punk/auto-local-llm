#!/bin/bash
# ============================================================================
# Utilidades para llama.cpp Auto-Setup
# ============================================================================
# Script auxiliar con herramientas útiles para gestionar modelos
# ============================================================================

set -euo pipefail

MODELS_DIR="${MODELS_DIR:-$(pwd)/llama.cpp/models_multi}"
LLAMA_DIR="${LLAMA_DIR:-$(pwd)/llama.cpp}"
BUILD_DIR="$LLAMA_DIR/build"

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Funciones Auxiliares
# ============================================================================

print_usage() {
  cat << EOF
Uso: $0 <comando> [argumentos]

Comandos Disponibles:

  list              Lista todos los modelos descargados
  info <modelo>     Muestra información detallada de un modelo
  test <modelo>     Ejecuta test de inferencia en un modelo
  clean             Limpia modelos corruptos/incompletos
  sizes             Muestra tamaños de todos los modelos
  verify            Verifica integridad de todos los modelos
  chat <modelo>     Inicia chat interactivo con un modelo
  benchmark         Ejecuta benchmark de velocidad en todos los modelos
  export <modelo>   Exporta modelo a formato diferente
  remove <modelo>   Elimina un modelo específico
  disk-usage        Muestra uso de disco por modelos

Ejemplos:
  $0 list
  $0 info llama-3.1-8b-q4_k_m
  $0 test phi-3.5-mini-q4_k_m
  $0 clean
  $0 chat mistral-7b-v0.3-q4_k_m

EOF
}

get_binary() {
  local candidates=(
    "$BUILD_DIR/bin/llama-cli"
    "$BUILD_DIR/bin/llama-run"
    "$BUILD_DIR/bin/main"
  )
  
  for bin in "${candidates[@]}"; do
    if [[ -x "$bin" ]]; then
      echo "$bin"
      return 0
    fi
  done
  
  return 1
}

is_gguf() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  local magic
  magic="$(dd if="$file" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
  [[ "$magic" == "47475546" ]]
}

human_size() {
  numfmt --to=iec-i --suffix=B "$1" 2>/dev/null || echo "$1"
}

# ============================================================================
# Comando: list
# ============================================================================
cmd_list() {
  echo -e "${BLUE}=== Modelos Descargados ===${NC}\n"
  
  if [[ ! -d "$MODELS_DIR" ]]; then
    echo -e "${YELLOW}No se encontró directorio de modelos: $MODELS_DIR${NC}"
    return 1
  fi
  
  local count=0
  
  for model_dir in "$MODELS_DIR"/*; do
    [[ -d "$model_dir" ]] || continue
    
    local model_name
    model_name="$(basename "$model_dir")"
    
    echo -e "${GREEN}$model_name${NC}"
    
    for gguf in "$model_dir"/*.gguf; do
      [[ -f "$gguf" ]] || continue
      
      local size
      size="$(stat -c%s "$gguf" 2>/dev/null || echo 0)"
      local human
      human="$(human_size "$size")"
      
      local filename
      filename="$(basename "$gguf")"
      
      local status="✓"
      local color="$GREEN"
      
      if ! is_gguf "$gguf"; then
        status="✗"
        color="$RED"
      fi
      
      echo -e "  ${color}${status}${NC} $filename ($human)"
      ((count++))
    done
    
    echo ""
  done
  
  echo -e "${BLUE}Total: $count archivo(s) GGUF${NC}"
}

# ============================================================================
# Comando: info
# ============================================================================
cmd_info() {
  local model_id="$1"
  local model_dir="$MODELS_DIR/$model_id"
  
  if [[ ! -d "$model_dir" ]]; then
    echo -e "${RED}Error: Modelo no encontrado: $model_id${NC}"
    return 1
  fi
  
  echo -e "${BLUE}=== Información: $model_id ===${NC}\n"
  
  echo "Directorio: $model_dir"
  
  for gguf in "$model_dir"/*.gguf; do
    [[ -f "$gguf" ]] || continue
    
    local filename
    filename="$(basename "$gguf")"
    
    local size
    size="$(stat -c%s "$gguf" 2>/dev/null || echo 0)"
    
    local modified
    modified="$(stat -c%y "$gguf" 2>/dev/null | cut -d. -f1)"
    
    echo ""
    echo "Archivo:    $filename"
    echo "Tamaño:     $(human_size "$size") ($size bytes)"
    echo "Modificado: $modified"
    echo -n "Formato:    "
    
    if is_gguf "$gguf"; then
      echo -e "${GREEN}GGUF válido ✓${NC}"
      
      # Extraer información con llama-cli si está disponible
      local binary
      if binary="$(get_binary 2>/dev/null)"; then
        echo ""
        echo -e "${YELLOW}Metadatos del modelo:${NC}"
        "$binary" -m "$gguf" --verbose 2>&1 | grep -E "^(llm|model|vocab)" | head -20 || true
      fi
    else
      echo -e "${RED}Formato inválido ✗${NC}"
    fi
    
    # SHA256
    echo ""
    echo -n "Calculando SHA256... "
    local sha256
    sha256="$(sha256sum "$gguf" | awk '{print $1}')"
    echo "$sha256"
  done
  
  echo ""
}

# ============================================================================
# Comando: test
# ============================================================================
cmd_test() {
  local model_id="$1"
  local model_dir="$MODELS_DIR/$model_id"
  
  if [[ ! -d "$model_dir" ]]; then
    echo -e "${RED}Error: Modelo no encontrado: $model_id${NC}"
    return 1
  fi
  
  local binary
  if ! binary="$(get_binary)"; then
    echo -e "${RED}Error: No se encontró binario de llama.cpp${NC}"
    return 1
  fi
  
  local gguf
  gguf="$(find "$model_dir" -name "*.gguf" -type f | head -1)"
  
  if [[ -z "$gguf" ]]; then
    echo -e "${RED}Error: No se encontró archivo GGUF en $model_dir${NC}"
    return 1
  fi
  
  echo -e "${BLUE}=== Test de Inferencia: $model_id ===${NC}\n"
  echo "Modelo: $gguf"
  echo "Binario: $binary"
  echo ""
  
  local prompt="Hola, ¿quién eres? Responde en una frase."
  
  echo -e "${YELLOW}Ejecutando inferencia...${NC}\n"
  
  "$binary" -m "$gguf" \
    -p "$prompt" \
    -n 100 \
    -t "$(nproc)" \
    -c 2048 \
    --temp 0.7
  
  echo -e "\n${GREEN}✓ Test completado${NC}"
}

# ============================================================================
# Comando: clean
# ============================================================================
cmd_clean() {
  echo -e "${YELLOW}=== Limpiando Modelos Corruptos ===${NC}\n"
  
  local cleaned=0
  local total=0
  
  for gguf in "$MODELS_DIR"/*/*.gguf; do
    [[ -f "$gguf" ]] || continue
    ((total++))
    
    if ! is_gguf "$gguf"; then
      echo -e "${RED}✗ Corrupto: $gguf${NC}"
      echo -n "  ¿Eliminar? [y/N] "
      read -r response
      
      if [[ "$response" =~ ^[Yy]$ ]]; then
        rm -f "$gguf"
        echo -e "  ${GREEN}Eliminado${NC}"
        ((cleaned++))
      fi
    fi
  done
  
  echo ""
  echo "Total revisados: $total"
  echo "Total eliminados: $cleaned"
}

# ============================================================================
# Comando: sizes
# ============================================================================
cmd_sizes() {
  echo -e "${BLUE}=== Tamaños de Modelos ===${NC}\n"
  
  printf "%-35s %15s\n" "Modelo" "Tamaño"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  local total_bytes=0
  
  for model_dir in "$MODELS_DIR"/*; do
    [[ -d "$model_dir" ]] || continue
    
    local model_name
    model_name="$(basename "$model_dir")"
    
    local dir_size=0
    
    for gguf in "$model_dir"/*.gguf; do
      [[ -f "$gguf" ]] || continue
      local size
      size="$(stat -c%s "$gguf" 2>/dev/null || echo 0)"
      ((dir_size += size))
    done
    
    if [[ $dir_size -gt 0 ]]; then
      printf "%-35s %15s\n" "$model_name" "$(human_size "$dir_size")"
      ((total_bytes += dir_size))
    fi
  done
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  printf "%-35s %15s\n" "TOTAL" "$(human_size "$total_bytes")"
}

# ============================================================================
# Comando: verify
# ============================================================================
cmd_verify() {
  echo -e "${BLUE}=== Verificando Integridad ===${NC}\n"
  
  local total=0
  local valid=0
  local invalid=0
  
  for gguf in "$MODELS_DIR"/*/*.gguf; do
    [[ -f "$gguf" ]] || continue
    ((total++))
    
    local name
    name="$(basename "$gguf")"
    
    if is_gguf "$gguf"; then
      echo -e "${GREEN}✓${NC} $name"
      ((valid++))
    else
      echo -e "${RED}✗${NC} $name"
      ((invalid++))
    fi
  done
  
  echo ""
  echo "Total: $total"
  echo -e "${GREEN}Válidos: $valid${NC}"
  echo -e "${RED}Inválidos: $invalid${NC}"
  
  [[ $invalid -eq 0 ]]
}

# ============================================================================
# Comando: chat
# ============================================================================
cmd_chat() {
  local model_id="$1"
  local model_dir="$MODELS_DIR/$model_id"
  
  if [[ ! -d "$model_dir" ]]; then
    echo -e "${RED}Error: Modelo no encontrado: $model_id${NC}"
    return 1
  fi
  
  local binary
  if ! binary="$(get_binary)"; then
    echo -e "${RED}Error: No se encontró binario de llama.cpp${NC}"
    return 1
  fi
  
  local gguf
  gguf="$(find "$model_dir" -name "*.gguf" -type f | head -1)"
  
  if [[ -z "$gguf" ]]; then
    echo -e "${RED}Error: No se encontró archivo GGUF${NC}"
    return 1
  fi
  
  echo -e "${BLUE}=== Chat Interactivo: $model_id ===${NC}\n"
  echo "Presiona Ctrl+C para salir"
  echo ""
  
  "$binary" -m "$gguf" \
    -c 4096 \
    -n -1 \
    --interactive \
    --color \
    -t "$(nproc)"
}

# ============================================================================
# Comando: benchmark
# ============================================================================
cmd_benchmark() {
  echo -e "${BLUE}=== Benchmark de Velocidad ===${NC}\n"
  
  local binary
  if ! binary="$(get_binary)"; then
    echo -e "${RED}Error: No se encontró binario de llama.cpp${NC}"
    return 1
  fi
  
  local prompt="La inteligencia artificial es"
  local n_tokens=50
  
  # Contar modelos
  local total_models=0
  for model_dir in "$MODELS_DIR"/*; do
    [[ -d "$model_dir" ]] || continue
    local gguf
    gguf="$(find "$model_dir" -name "*.gguf" -type f | head -1)"
    [[ -n "$gguf" ]] && ((total_models++))
  done
  
  printf "%-35s %15s %15s %15s\n" "Modelo" "Tokens/seg" "Tiempo" "Progreso"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  local current_model=0
  
  for model_dir in "$MODELS_DIR"/*; do
    [[ -d "$model_dir" ]] || continue
    
    local model_name
    model_name="$(basename "$model_dir")"
    
    local gguf
    gguf="$(find "$model_dir" -name "*.gguf" -type f | head -1)"
    
    [[ -n "$gguf" ]] || continue
    
    ((current_model++))
    
    # Barra de progreso simple
    local progress_pct=$((current_model * 100 / total_models))
    local progress_bar=""
    local filled=$((current_model * 20 / total_models))
    for ((i=0; i<filled; i++)); do progress_bar+="█"; done
    for ((i=filled; i<20; i++)); do progress_bar+="░"; done
    
    echo -ne "\r${YELLOW}Progreso: [${progress_bar}] ${progress_pct}%${NC} - Probando: $model_name..."
    
    local start
    start="$(date +%s)"
    
    "$binary" -m "$gguf" \
      -p "$prompt" \
      -n "$n_tokens" \
      -t "$(nproc)" \
      --log-disable \
      >/dev/null 2>&1 || {
        echo -ne "\r"
        printf "%-35s %15s %15s %15s\n" "$model_name" "${RED}ERROR${NC}" "-" "[$progress_bar]"
        continue
      }
    
    local end
    end="$(date +%s)"
    local elapsed=$((end - start))
    
    local tps
    if [[ $elapsed -gt 0 ]]; then
      tps=$((n_tokens / elapsed))
    else
      tps="N/A"
    fi
    
    # Limpiar línea y mostrar resultado
    echo -ne "\r"
    printf "%-35s %15s %15s %15s\n" \
      "$model_name" \
      "${GREEN}$tps${NC}" \
      "${elapsed}s" \
      "[${progress_bar}]"
  done
  
  echo ""
  echo -e "${GREEN}✓ Benchmark completado${NC}"
}

# ============================================================================
# Comando: remove
# ============================================================================
cmd_remove() {
  local model_id="$1"
  local model_dir="$MODELS_DIR/$model_id"
  
  if [[ ! -d "$model_dir" ]]; then
    echo -e "${RED}Error: Modelo no encontrado: $model_id${NC}"
    return 1
  fi
  
  echo -e "${YELLOW}¿Eliminar modelo '$model_id'?${NC}"
  echo "Directorio: $model_dir"
  echo -n "Confirmar [y/N]: "
  read -r response
  
  if [[ "$response" =~ ^[Yy]$ ]]; then
    rm -rf "$model_dir"
    echo -e "${GREEN}✓ Modelo eliminado${NC}"
  else
    echo "Cancelado"
  fi
}

# ============================================================================
# Comando: disk-usage
# ============================================================================
cmd_disk_usage() {
  echo -e "${BLUE}=== Uso de Disco ===${NC}\n"
  
  if [[ ! -d "$MODELS_DIR" ]]; then
    echo -e "${YELLOW}No se encontró directorio de modelos${NC}"
    return 1
  fi
  
  du -sh "$MODELS_DIR"/* 2>/dev/null | sort -hr || true
  echo ""
  echo "Total:"
  du -sh "$MODELS_DIR" 2>/dev/null || true
}

# ============================================================================
# Main
# ============================================================================
main() {
  if [[ $# -eq 0 ]]; then
    print_usage
    exit 0
  fi
  
  local command="$1"
  shift
  
  case "$command" in
    list)
      cmd_list "$@"
      ;;
    info)
      [[ $# -eq 1 ]] || { echo "Uso: $0 info <modelo>"; exit 1; }
      cmd_info "$@"
      ;;
    test)
      [[ $# -eq 1 ]] || { echo "Uso: $0 test <modelo>"; exit 1; }
      cmd_test "$@"
      ;;
    clean)
      cmd_clean "$@"
      ;;
    sizes)
      cmd_sizes "$@"
      ;;
    verify)
      cmd_verify "$@"
      ;;
    chat)
      [[ $# -eq 1 ]] || { echo "Uso: $0 chat <modelo>"; exit 1; }
      cmd_chat "$@"
      ;;
    benchmark)
      cmd_benchmark "$@"
      ;;
    remove)
      [[ $# -eq 1 ]] || { echo "Uso: $0 remove <modelo>"; exit 1; }
      cmd_remove "$@"
      ;;
    disk-usage)
      cmd_disk_usage "$@"
      ;;
    *)
      echo -e "${RED}Error: Comando desconocido: $command${NC}"
      echo ""
      print_usage
      exit 1
      ;;
  esac
}

main "$@"