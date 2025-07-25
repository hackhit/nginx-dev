#!/bin/bash

# Script: check-nginx
# Descripcion: Verifica la integridad y estado del servidor Nginx.
# Autor: Miguel Hernandez - Hackhit 
# Nota: Debe ejecutarse con privilegios de root o mediante sudo.

# --- 1. Informacion de Tiempo de Ejecucion ---
hora_inicio=$(date +%s)
echo "========================"
echo " VERIFICACION DE NGINX "
echo "========================"
echo "Hora de inicio de verificacion: $(date)"
echo ""

# --- 2. Informacion del Sistema ---
echo "1. Informacion del Sistema:"
echo "   Nucleos de CPU: $(nproc)"
ram_total=$(free -b | awk '/^Mem:/ {print $2}')
ram_total_mb=$((ram_total / 1024 / 1024))
echo "   Memoria RAM Total: ${ram_total_mb} MB"
echo "   Usuario Actual: $(whoami)"
echo "   Uptime del Sistema: $(uptime -p)"
echo ""

# --- 3. Estado del Servicio Nginx ---
echo "2. Estado del Servicio Nginx:"
if systemctl list-unit-files | grep -q '^nginx.service'; then
    estado_servicio=$(systemctl is-active nginx)
    echo "   Estado: $estado_servicio"
    if [ "$estado_servicio" != "active" ]; then
        echo "   ADVERTENCIA: El servicio nginx no esta activo."
    fi
    echo "   Detalles del estado:"
    systemctl status nginx --no-pager -l | head -n 5
    echo "   Tiempo de actividad (ActiveEnterTimestamp):"
    systemctl show nginx --property=ActiveEnterTimestamp --no-pager | cut -d'=' -f2
else
    echo "   ERROR: El servicio 'nginx' no parece estar instalado o no se encuentra."
fi
echo ""

# --- 4. Sintaxis de la Configuracion ---
echo "3. Sintaxis de la Configuracion:"
resultado_sintaxis=$(sudo nginx -t 2>&1)
codigo_salida=$?
echo "$resultado_sintaxis"
if [ $codigo_salida -ne 0 ]; then
    echo "   ERROR: La sintaxis de configuracion de Nginx contiene errores."
fi
echo ""

# --- 5. Version de Nginx ---
echo "4. Version de Nginx:"
version_nginx=$(nginx -v 2>&1)
echo "   $version_nginx"
echo ""

# --- 6. Procesos Nginx en Ejecucion ---
echo "5. Procesos Nginx en Ejecucion:"
num_procesos=$(pgrep -c nginx)
echo "   Numero total de procesos nginx: $num_procesos"
echo "   Detalles de procesos (Master y Workers):"
ps aux | grep nginx | grep -v grep
# Uso de RAM por Nginx
echo "   Uso estimado de RAM por procesos Nginx:"
ps -o pid,vsz,rss,comm -C nginx 2>/dev/null | awk 'NR>1 { vsz_sum += $2; rss_sum += $3 } END { printf "     VSZ (Virtual): %.2f MB\n     RSS (Residente): %.2f MB\n", vsz_sum/1024, rss_sum/1024 }' || echo "     No se pudieron obtener metricas de memoria para Nginx."
echo ""

# --- 7. Puertos en Escucha ---
echo "6. Puertos en Escucha por Nginx:"
puertos=(80 443)
for puerto in "${puertos[@]}"; do
    if sudo lsof -i :$puerto -t >/dev/null 2>&1; then
        echo "   Puerto $puerto: ABIERTO"
    else
        echo "   Puerto $puerto: CERRADO o no escuchado por Nginx"
    fi
done
echo ""

# --- 8. Informacion de Certificados SSL ---
echo "7. Informacion de Certificados SSL (Dominios comunes):"
# Busca posibles archivos de certificado en las configuraciones de Nginx
# Esta busqueda es basica, puede necesitar ajustes segun tu estructura
cert_files=$(sudo grep -r "ssl_certificate" /etc/nginx/sites-enabled/ /etc/nginx/conf.d/ 2>/dev/null | grep -o '/[^;]*\.crt' | sort -u)
if [ -n "$cert_files" ]; then
    for cert_file in $cert_files; do
        if [ -f "$cert_file" ]; then
            echo "   Certificado: $cert_file"
            # Extrae informacion del certificado usando openssl
            echo "     Dominio (Subject): $(openssl x509 -in "$cert_file" -noout -subject | sed 's/.*CN=\([^,]*\).*/\1/')"
            echo "     Emitido por (Issuer): $(openssl x509 -in "$cert_file" -noout -issuer | sed 's/.*O=\([^,]*\).*/\1/' | cut -d'=' -f2)"
            echo "     Valido desde: $(openssl x509 -in "$cert_file" -noout -startdate | cut -d'=' -f2)"
            echo "     Valido hasta: $(openssl x509 -in "$cert_file" -noout -enddate | cut -d'=' -f2)"
            exp_date_epoch=$(date -d "$(openssl x509 -in "$cert_file" -noout -enddate | cut -d'=' -f2)" +%s 2>/dev/null)
            current_date_epoch=$(date +%s)
            if [ $? -eq 0 ] && [ -n "$exp_date_epoch" ]; then
                 days_until_expiry=$(( (exp_date_epoch - current_date_epoch) / 86400 ))
                 if [ $days_until_expiry -lt 0 ]; then
                     echo "     Estado: EXPIRADO hace $((days_until_expiry * -1)) dias"
                 elif [ $days_until_expiry -lt 30 ]; then
                     echo "     Estado: VENCE en $days_until_expiry dias - RENOVACION RECOMENDADA"
                 else
                     echo "     Estado: Valido por $days_until_expiry dias mas"
                 fi
            else
                echo "     Estado: No se pudo determinar la fecha de expiracion."
            fi
            echo ""
        else
            echo "   ADVERTENCIA: Archivo de certificado referenciado no encontrado: $cert_file"
        fi
    done
else
    echo "   Nota: No se encontraron referencias a ssl_certificate en las configuraciones habilitadas."
fi
echo ""

# --- 9. Ultimos Errores del Log ---
echo "8. Ultimos 20 Errores del Log de Nginx (/var/log/nginx/error.log):"
if [ -f /var/log/nginx/error.log ]; then
    num_lineas_error=$(wc -l < /var/log/nginx/error.log)
    echo "   Lineas totales en error.log: $num_lineas_error"
    tail -n 20 /var/log/nginx/error.log
    echo ""
    echo "   Buscando errores criticos recientes (ultimas 100 lineas):"
    tail -n 100 /var/log/nginx/error.log | grep -i -E "(error|crit|alert|emerg)" | tail -n 10 || echo "     No se encontraron errores criticos en las ultimas 100 lineas."
else
    echo "   ADVERTENCIA: El archivo /var/log/nginx/error.log no se encontro."
fi
echo ""

# --- 10. Ultimos Accesos del Log ---
echo "9. Ultimos 10 Accesos del Log de Nginx (/var/log/nginx/access.log):"
if [ -f /var/log/nginx/access.log ]; then
    num_lineas_access=$(wc -l < /var/log/nginx/access.log)
    echo "   Lineas totales en access.log: $num_lineas_access"
    tail -n 10 /var/log/nginx/access.log
else
    echo "   Nota: El archivo /var/log/nginx/access.log no se encontro o esta vacio."
fi
echo ""

# --- 11. Configuracion de Workers ---
echo "10. Configuracion de Workers:"
config_principal="/etc/nginx/nginx.conf"
if [ -f "$config_principal" ]; then
    worker_processes=$(grep -E "^[[:space:]]*worker_processes" $config_principal | awk '{print $2}' | tr -d ';')
    worker_connections=$(grep -E "^[[:space:]]*worker_connections" $config_principal | awk '{print $2}' | tr -d ';')
    echo "   worker_processes: ${worker_processes:-No encontrado o comentado}"
    echo "   worker_connections: ${worker_connections:-No encontrado o comentado}"
    if [[ "$worker_processes" =~ ^[0-9]+$ ]] && [[ "$worker_connections" =~ ^[0-9]+$ ]]; then
        conexiones_max=$((worker_processes * worker_connections))
        echo "   Conexiones maximas teoricas: $conexiones_max"
    fi
else
    echo "   ADVERTENCIA: No se pudo encontrar el archivo de configuracion principal $config_principal."
fi
echo ""

# --- 12. Verificacion de Espacio en Disco y Mantenimiento ---
echo "11. Espacio en Disco y Mantenimiento:"
echo "   Espacio en particiones criticas:"
df -h / /var /var/log /var/cache/nginx 2>/dev/null | column -t
echo ""
echo "   Tamano de los logs de Nginx:"
sudo du -sh /var/log/nginx/* 2>/dev/null || echo "     No se pudo determinar el tamano de los logs."
echo ""
echo "   Archivos temporales grandes en /tmp y /var/tmp (mayores a 10MB):"
find /tmp /var/tmp -type f -size +10M -exec ls -lh {} \; 2>/dev/null | head -n 5 || echo "     No se encontraron archivos temporales grandes."
echo ""
echo "   SUGERENCIAS DE MANTENIMIENTO:"
echo "   - Rota los logs de Nginx regularmente usando logrotate."
echo "   - Verifica y limpia archivos temporales grandes si no son necesarios."
echo "   - Asegurate de que los certificados SSL se renueven automaticamente antes de su expiracion."
echo "   - Revisa los logs de error regularmente para detectar problemas."
echo ""

# --- 13. Tiempo Total de Ejecucion ---
hora_fin=$(date +%s)
tiempo_ejecucion=$((hora_fin - hora_inicio))
echo "========================"
echo " VERIFICACION COMPLETADA "
echo "========================"
echo "Hora de finalizacion: $(date)"
echo "Tiempo total de ejecucion: ${tiempo_ejecucion} segundos"
echo ""
