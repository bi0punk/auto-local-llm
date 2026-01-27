#!/bin/bash

set -euo pipefail

# === CONFIGURACIÓN ===
REPO_LLAMA="https://github.com/ggerganov/llama.cpp"
MODELO_URL="https://huggingface.co/unsloth/gpt-oss-20b-GGUF/resolve/main/gpt-oss-20b-Q4_K_M.gguf?download=true"
MODELO_NOMBRE="gpt-oss-20b-Q4_K_M.gguf"
MODELO_DIR="./llama.cpp/models"
PROMPT_PRUEBA="Hola, ¿quién eres?"
HILOS=6

# === COLORES PARA SALIDA ===
VERDE='\033[0;32m'
ROJO='\033[0;31m'
AMARILLO='\033[1;33m'
NC='\033[0m'

trap 'echo -e "${ROJO}[!] Error en la línea ${LINENO}. Abortando.${NC}"; exit 1' ERR

function esperar() {
    sleep "$1"
}

function mensaje() {
    echo -e "${AMARILLO}[+] $1${NC}"
}

function exito() {
    echo -e "${VERDE}[*] $1${NC}"
}

# === PASO 1: Verificar sudo ===
if ! command -v sudo &>/dev/null; then
    echo -e "${ROJO}[X] sudo no está instalado. Instálalo y vuelve a intentar.${NC}"
    exit 1
fi

# === PASO 2: Instalar dependencias ===
mensaje "Instalando dependencias..."
esperar 1
sudo apt update && sudo apt install -y \
    build-essential cmake git curl unzip wget \
    libcurl4-openssl-dev python3 python3-pip

# === PASO 3: Clonar llama.cpp ===
mensaje "Clonando llama.cpp..."
esperar 1
if [ ! -d "llama.cpp" ]; then
    git clone "$REPO_LLAMA"
else
    exito "Repositorio llama.cpp ya existe."
fi

# === PASO 4: Compilar con CMake ===
mensaje "Compilando llama.cpp con CMake..."
esperar 1
cd llama.cpp
mkdir -p build
cd build
cmake ..
cmake --build . --config Release -j"$(nproc)"
cd ../..

# === PASO 5: Verificar token ===
if [[ -z "${HUGGING_FACE_TOKEN:-}" ]]; then
  echo -e "${ROJO}[X] Variable HUGGING_FACE_TOKEN no definida.${NC}"
  echo -e "${AMARILLO}1) Ve a https://huggingface.co/settings/tokens"
  echo -e "2) Crea un token con permisos READ"
  echo -e "3) Luego ejecuta: export HUGGING_FACE_TOKEN=tu_token_aquí${NC}"
  exit 1
fi

# === PASO 6: Descargar modelo con wget ===
mensaje "Descargando modelo GPT-OSS-20B Q4_K_M desde Hugging Face..."
mkdir -p "$MODELO_DIR"

if [ ! -f "$MODELO_DIR/$MODELO_NOMBRE" ]; then
    wget --header="Authorization: Bearer $HUGGING_FACE_TOKEN" \
        "$MODELO_URL" \
        -O "$MODELO_DIR/$MODELO_NOMBRE"
    exito "Modelo descargado correctamente."
else
    exito "Modelo ya existe. Se omite descarga."
fi

# === PASO 7: Ejecutar modelo con llama-run ===
BINARIO="./llama.cpp/build/bin/llama-run"
if [ ! -f "$BINARIO" ]; then
    echo -e "${ROJO}[X] No se encontró el ejecutable llama-run. Verifica la compilación.${NC}"
    exit 1
fi

mensaje "Ejecutando prueba con el modelo..."
esperar 2

$BINARIO "$MODELO_DIR/$MODELO_NOMBRE" \
    --threads "$HILOS" \
    --temp 0.8 \
    --context-size 2048 \
    "$PROMPT_PRUEBA"

exito "GPT‑OSS está funcionando correctamente con llama.cpp 🎉"
