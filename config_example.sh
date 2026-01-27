# ============================================================================
# Configuración de Ejemplo para llama.cpp Auto-Setup
# ============================================================================
# Copia este archivo como .env y edita según tus necesidades:
#   cp config.example.sh .env
#   source .env
#   ./llama_auto_setup_improved.sh
# ============================================================================

# ----------------------------------------------------------------------------
# AUTENTICACIÓN HUGGING FACE
# ----------------------------------------------------------------------------
# Obtén tu token en: https://huggingface.co/settings/tokens
# Recomendado para evitar rate limits
export HUGGING_FACE_TOKEN="hf_your_token_here"

# ----------------------------------------------------------------------------
# CONFIGURACIÓN DE INFERENCIA
# ----------------------------------------------------------------------------
# Número de threads (default: automático = nproc)
# Ajusta según tus núcleos de CPU
export HILOS=8

# Tamaño del contexto en tokens (default: 2048)
# Valores comunes: 2048, 4096, 8192, 16384
export CTX=4096

# Temperatura de generación (default: 0.8)
# Rango: 0.0 (determinista) - 2.0 (muy creativo)
export TEMP=0.7

# Máximo de tokens a generar (default: 100)
export MAX_TOKENS=200

# ----------------------------------------------------------------------------
# CONTROL DE COMPORTAMIENTO
# ----------------------------------------------------------------------------
# Forzar recompilación de llama.cpp (default: 0)
# 1 = siempre recompila, 0 = solo si no existe binario
export FORCE_REBUILD=0

# Omitir actualización del repositorio (default: 0)
# 1 = no hace git pull, 0 = actualiza si hay cambios
export SKIP_GIT_PULL=0

# Omitir tests de inferencia (default: 0)
# 1 = solo descarga modelos, 0 = descarga y prueba
export SKIP_TESTS=0

# Modo verbose (default: 0)
# 1 = muestra información de debug detallada
export VERBOSE=0

# Modo dry-run (default: 0)
# 1 = simula acciones sin ejecutarlas
export DRY_RUN=0

# ----------------------------------------------------------------------------
# ESCENARIOS PREDEFINIDOS
# ----------------------------------------------------------------------------

# ESCENARIO 1: Primera instalación (recomendado)
# export HUGGING_FACE_TOKEN="hf_xxxx"
# export VERBOSE=1
# Resto por defecto

# ESCENARIO 2: Solo descargar modelos (sin tests)
# export SKIP_TESTS=1
# export VERBOSE=0

# ESCENARIO 3: Desarrollo / testing
# export FORCE_REBUILD=1
# export VERBOSE=1
# export MAX_TOKENS=50

# ESCENARIO 4: Producción / máximo performance
# export HILOS=16
# export CTX=8192
# export SKIP_TESTS=0
# export VERBOSE=0

# ESCENARIO 5: Debugging de problemas
# export VERBOSE=1
# export DRY_RUN=1
# export FORCE_REBUILD=1

# ----------------------------------------------------------------------------
# NOTAS
# ----------------------------------------------------------------------------
# - Las variables se pueden sobrescribir en la línea de comando:
#     VERBOSE=1 ./llama_auto_setup_improved.sh
#
# - Los logs se guardan automáticamente en logs/
#
# - Para máxima velocidad de descarga, instala:
#     python3 -m pip install --user -U hf_transfer
#
# - Modelos con Q4_K_M usan ~4-5 bits por parámetro
#   Fórmula aproximada: tamaño_GB = (parametros * 4.5) / 8 / 1024