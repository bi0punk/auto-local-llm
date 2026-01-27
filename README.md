# llama.cpp Multi-Model Auto-Setup Script v2.0

Script robusto y profesional para automatizar la descarga, validación y prueba de múltiples modelos GGUF usando llama.cpp.

##  Características Principales

### Mejoras Implementadas

1. **Logging Profesional**
   - Sistema de logs con niveles (INFO, WARN, ERROR, DEBUG)
   - Logs persistentes con timestamps en archivos
   - Colores en terminal para mejor visualización
   - Modo verbose para debugging

2. **Robustez y Recuperación**
   - Validación GGUF mediante magic number
   - Verificación de checksums SHA256 (opcional)
   - Sistema de reintentos automáticos
   - Recuperación ante archivos corruptos
   - Manejo inteligente de errores

3. **Rendimiento Optimizado**
   - Uso de `ccache` para compilación incremental
   - Detección automática de núcleos disponibles
   - Compilación con `-DLLAMA_NATIVE=ON` para optimizaciones específicas
   - Descarga acelerada con `hf_transfer`

4. **Flexibilidad y Control**
   - Variables de entorno para personalización
   - Modo dry-run para simulación sin ejecución
   - Skip de tests para descarga masiva
   - Control granular de rebuild y updates

5. **Código Mantenible**
   - Estructura modular con funciones bien definidas
   - Constantes readonly para seguridad
   - Documentación inline completa
   - Cumple con ShellCheck best practices

6. **Características Adicionales**
   - Banner informativo con versión
   - Resumen ejecutivo de resultados
   - Detección inteligente de binarios
   - Soporte para múltiples métodos de descarga
   - Validación de tamaño mínimo de archivos
   - Conversión de tamaños a formato legible (GiB, MiB)

##  Requisitos

- Ubuntu 20.04+ (o distribución Debian-based)
- Bash 4.4+
- Conexión a internet
- Mínimo 50GB de espacio libre (para los 5 modelos)
- 8GB RAM recomendado

## 🔧 Instalación

```bash
# Descargar el script
chmod +x llama_auto_setup_improved.sh

# Ejecutar (instala dependencias automáticamente)
./llama_auto_setup_improved.sh
```

##  Uso Básico

### Ejecución Estándar

```bash
./llama_auto_setup_improved.sh
```

### Con Token de Hugging Face (recomendado)

```bash
export HUGGING_FACE_TOKEN="hf_xxxxxxxxxxxx"
./llama_auto_setup_improved.sh
```

##  Variables de Entorno

### Configuración de Inferencia

```bash
# Número de threads (default: todos los núcleos)
export HILOS=8

# Tamaño del contexto (default: 2048)
export CTX=4096

# Temperatura (default: 0.8)
export TEMP=0.7

# Máximo de tokens a generar (default: 100)
export MAX_TOKENS=200
```

### Control de Comportamiento

```bash
# Forzar recompilación de llama.cpp
export FORCE_REBUILD=1

# No actualizar repositorio (mantener versión actual)
export SKIP_GIT_PULL=1

# Omitir pruebas de inferencia (solo descargar)
export SKIP_TESTS=1

# Modo verbose (mostrar debug info)
export VERBOSE=1

# Modo dry-run (simular sin ejecutar)
export DRY_RUN=1
```

### Autenticación Hugging Face

```bash
# Token de Hugging Face (evita rate limits)
export HUGGING_FACE_TOKEN="hf_your_token_here"
```

##  Ejemplos de Uso

### Ejemplo 1: Primera Instalación Completa

```bash
# Con token de HF para mejor velocidad
export HUGGING_FACE_TOKEN="hf_xxxxxxxxxxxx"
./llama_auto_setup_improved.sh
```

### Ejemplo 2: Solo Descargar Modelos (Sin Tests)

```bash
export SKIP_TESTS=1
./llama_auto_setup_improved.sh
```

### Ejemplo 3: Actualizar y Recompilar Todo

```bash
export FORCE_REBUILD=1
export SKIP_GIT_PULL=0
./llama_auto_setup_improved.sh
```

### Ejemplo 4: Debugging de Problemas

```bash
export VERBOSE=1
./llama_auto_setup_improved.sh 2>&1 | tee debug.log
```

### Ejemplo 5: Simular Sin Ejecutar

```bash
export DRY_RUN=1
export VERBOSE=1
./llama_auto_setup_improved.sh
```

### Ejemplo 6: Configuración de Alta Performance

```bash
export HILOS=16
export CTX=8192
export TEMP=0.5
export MAX_TOKENS=500
./llama_auto_setup_improved.sh
```

##  Estructura de Directorios

```
.
├── llama.cpp/                  # Repositorio clonado
│   ├── build/                  # Archivos de compilación
│   │   └── bin/
│   │       ├── llama-cli       # Binario principal
│   │       └── llama-run       # Binario alternativo
│   └── models_multi/           # Modelos descargados
│       ├── gpt-oss-20b-q4_k_m/
│       ├── llama-3.1-8b-q4_k_m/
│       ├── mistral-7b-v0.3-q4_k_m/
│       ├── qwen2.5-7b-q4_k_m/
│       └── phi-3.5-mini-q4_k_m/
└── logs/                       # Logs de ejecución
    └── setup_20260127_143052.log
```

##  Modelos Incluidos

| Modelo | Tamaño | Contexto | Uso Recomendado |
|--------|--------|----------|-----------------|
| **GPT-OSS 20B Q4_K_M** | ~12GB | 4K | Tareas generales, razonamiento |
| **Llama 3.1 8B Q4_K_M** | ~4.9GB | 128K | Chat, instrucciones |
| **Mistral 7B v0.3 Q4_K_M** | ~4.1GB | 32K | Generación de texto |
| **Qwen 2.5 7B Q4_K_M** | ~4.4GB | 32K | Multilingüe, código |
| **Phi 3.5 Mini Q4_K_M** | ~2.3GB | 128K | Modelo ligero, rápido |

## 🔍 Validación de Modelos

El script incluye múltiples capas de validación:

1. **Magic Number GGUF**: Verifica los primeros 4 bytes (`0x47475546`)
2. **Tamaño Mínimo**: Compara contra tamaño esperado
3. **Checksum SHA256**: Opcional, cuando está disponible
4. **Test de Inferencia**: Ejecuta prompt de prueba

## 🐛 Troubleshooting

### Error: "No se encontró binario ejecutable"

```bash
# Forzar recompilación
export FORCE_REBUILD=1
./llama_auto_setup_improved.sh
```

### Error: "Modelo corrupto"

El script intenta recuperación automática. Si persiste:

```bash
# Borrar modelo y re-descargar
rm -rf llama.cpp/models_multi/NOMBRE_MODELO
./llama_auto_setup_improved.sh
```

### Error: Rate limit de Hugging Face

```bash
# Usar token de autenticación
export HUGGING_FACE_TOKEN="hf_xxxxxxxxxxxx"
./llama_auto_setup_improved.sh
```

### Descarga muy lenta

```bash
# Asegurar que hf_transfer está instalado
python3 -m pip install --user -U hf_transfer
export HF_HUB_ENABLE_HF_TRANSFER=1
./llama_auto_setup_improved.sh
```

### Problemas de compilación

```bash
# Instalar dependencias manualmente
sudo apt update
sudo apt install -y build-essential cmake git curl python3-pip ccache

# Limpiar y recompilar
rm -rf llama.cpp/build
export FORCE_REBUILD=1
./llama_auto_setup_improved.sh
```

##  Logs

Los logs se guardan automáticamente en `logs/setup_YYYYMMDD_HHMMSS.log`

### Ver último log:

```bash
tail -f logs/setup_*.log | tail -1
```

### Buscar errores:

```bash
grep ERROR logs/setup_*.log | tail -1
```

##  Seguridad

- El script usa `set -euo pipefail` para fail-fast
- Variables readonly para prevenir modificaciones accidentales
- Validación de comandos antes de ejecución
- No ejecuta código descargado sin validación
- Logs de auditoría de todas las operaciones

##  Códigos de Salida

- `0`: Éxito completo
- `1`: Error general o algún modelo falló
- `130`: Interrupción por usuario (Ctrl+C)

##  Performance

### Tiempos Estimados (conexión 100Mbps)

- **Primera ejecución**: 30-60 minutos
  - Clonación: 2-5 min
  - Compilación: 5-10 min
  - Descarga modelos: 20-45 min
  - Tests: 5-10 min

- **Ejecuciones posteriores**: 1-5 minutos
  - Solo validación y tests

### Uso de Recursos

- **Disco**: ~50GB
- **RAM (compilación)**: 4-8GB
- **RAM (inferencia)**: 8-16GB (según modelo)
- **CPU**: Todos los núcleos disponibles

##  Contribuciones

Para añadir modelos, editar la sección `MODELS` en el script:

```bash
declare -a MODELS=(
  "id|repo|filename|min_bytes|sha256_opcional"
)
```

Ejemplo:

```bash
"llama-3.3-70b|meta-llama/Llama-3.3-70B-Instruct-GGUF|llama-3.3-70b-Q4_K_M.gguf|40000000000|"
```

## Licencia

Este script es de código abierto. llama.cpp está bajo licencia MIT.

## Enlaces Útiles

- [llama.cpp GitHub](https://github.com/ggml-org/llama.cpp)
- [Hugging Face Hub](https://huggingface.co)
- [Documentación GGUF](https://github.com/ggerganov/ggml/blob/master/docs/gguf.md)

## Soporte

Para problemas o preguntas:

1. Revisa el log en `logs/`
2. Ejecuta con `VERBOSE=1`
3. Verifica los requisitos del sistema
4. Consulta la sección de troubleshooting

---

**Versión**: 2.0.0  
**Última actualización**: Enero 2026