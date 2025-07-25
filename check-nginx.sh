#!/bin/bash

# Script: check-nginx
# Descripcion: Verifica la integridad y estado del servidor Nginx.
# Autor: Miguel Hernandez (Hackhit)
# Nota: Debe ejecutarse con privilegios de root o mediante sudo.

echo "========================"
echo " VERIFICACION DE NGINX "
echo "========================"
fecha_actual=$(date)
echo "Fecha y hora: $fecha_actual"
echo ""

# --- 1. Informacion del Sistema ---
echo "1. Informacion del Sistema:"
echo "   Nucleos de CPU: $(nproc)"
echo "   Memoria Total: $(free -h | awk '/^Mem:/ {print $2}')"
echo "   Usuario Actual: $(whoami)"
echo ""

# --- 2. Estado del Servicio Nginx ---
echo "2. Estado del Servicio Nginx:"
# Verificar si el servicio nginx existe
if systemctl list-unit-files | grep -q '^nginx.service'; then
    estado_servicio=$(systemctl is-active nginx)
    echo "   Estado: $estado_servicio"
    if [ "$estado_servicio" != "active" ]; then
        echo "   ADVERTENCIA: El servicio nginx no esta activo."
    fi
    # Mostrar un resumen del estado
    systemctl status nginx --no-pager -l | head -n 5
else
    echo "   ERROR: El servicio 'nginx' no parece estar instalado o no se encuentra."
fi
echo ""

# --- 3. Sintaxis de la Configuracion ---
echo "3. Sintaxis de la Configuracion:"
# Ejecutar la prueba de sintaxis y capturar la salida
resultado_sintaxis=$(sudo nginx -t 2>&1)
codigo_salida=$?
echo "$resultado_sintaxis"
if [ $codigo_salida -ne 0 ]; then
    echo "   ERROR: La sintaxis de configuracion de Nginx contiene errores."
fi
echo ""

# --- 4. Version de Nginx ---
echo "4. Version de Nginx:"
# Obtener la version de Nginx instalada
version_nginx=$(nginx -v 2>&1)
echo "   $version_nginx"
echo ""

# --- 5. Procesos Nginx en Ejecucion ---
echo "5. Procesos Nginx en Ejecucion:"
# Contar los procesos nginx
num_procesos=$(pgrep -c nginx)
echo "   Numero total de procesos nginx: $num_procesos"
# Mostrar los detalles de los procesos master y workers
echo "   Detalles de procesos:"
ps aux | grep nginx | grep -v grep
echo ""

# --- 6. Puertos en Escucha ---
echo "6. Puertos en Escucha por Nginx:"
# Verificar puertos 80 y 443
puertos=(80 443)
for puerto in "${puertos[@]}"; do
    if sudo lsof -i :$puerto -t >/dev/null 2>&1; then
        echo "   Puerto $puerto: ABIERTO"
        # Opcional: Mostrar detalles de quien escucha
        # sudo lsof -i :$puerto | grep LISTEN
    else
        echo "   Puerto $puerto: CERRADO o no escuchado por Nginx"
    fi
done
echo ""

# --- 7. Ultimos Errores del Log ---
echo "7. Ultimos 20 Errores del Log de Nginx (/var/log/nginx/error.log):"
# Verificar si el archivo de log existe
if [ -f /var/log/nginx/error.log ]; then
    num_lineas_error=$(wc -l < /var/log/nginx/error.log)
    echo "   Lineas totales en error.log: $num_lineas_error"
    # Mostrar las ultimas 20 lineas o todas si son menos de 20
    tail -n 20 /var/log/nginx/error.log
    # Buscar errores criticos recientes (ultimas 100 lineas)
    echo ""
    echo "   Buscando errores criticos recientes (ultimas 100 lineas):"
    tail -n 100 /var/log/nginx/error.log | grep -i -E "(error|crit|alert|emerg)" | tail -n 10 || echo "     No se encontraron errores criticos en las ultimas 100 lineas."
else
    echo "   ADVERTENCIA: El archivo /var/log/nginx/error.log no se encontro."
fi
echo ""

# --- 8. Ultimos Accesos del Log ---
echo "8. Ultimos 10 Accesos del Log de Nginx (/var/log/nginx/access.log):"
# Verificar si el archivo de log existe
if [ -f /var/log/nginx/access.log ]; then
    num_lineas_access=$(wc -l < /var/log/nginx/access.log)
    echo "   Lineas totales en access.log: $num_lineas_access"
    tail -n 10 /var/log/nginx/access.log
else
    echo "   Nota: El archivo /var/log/nginx/access.log no se encontro o esta vacio."
fi
echo ""

# --- 9. Configuracion de Workers ---
echo "9. Configuracion de Workers:"
# Extraer informacion de worker_processes y worker_connections del archivo de configuracion principal
config_principal="/etc/nginx/nginx.conf"
if [ -f "$config_principal" ]; then
    worker_processes=$(grep -E "^[[:space:]]*worker_processes" $config_principal | awk '{print $2}' | tr -d ';')
    worker_connections=$(grep -E "^[[:space:]]*worker_connections" $config_principal | awk '{print $2}' | tr -d ';')
    echo "   worker_processes: ${worker_processes:-No encontrado o comentado}"
    echo "   worker_connections: ${worker_connections:-No encontrado o comentado}"
    # Calcular conexiones maximas teoricas (solo informativo)
    if [[ "$worker_processes" =~ ^[0-9]+$ ]] && [[ "$worker_connections" =~ ^[0-9]+$ ]]; then
        conexiones_max=$((worker_processes * worker_connections))
        echo "   Conexiones maximas teoricas: $conexiones_max"
    fi
else
    echo "   ADVERTENCIA: No se pudo encontrar el archivo de configuracion principal $config_principal."
fi
echo ""

echo "========================"
echo " VERIFICACION COMPLETADA "
echo "========================"

