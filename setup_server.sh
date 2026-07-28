#!/bin/bash

# Функция для отображения цветного прогресс-бара
show_progress() {
    local progress=$1
    local width=50  # ширина прогресс-бара
    local fill=$((progress * width / 100))
    local empty=$((width - fill))

    # Цвета
    local color_reset="\e[0m"
    local color_fill="\e[42m"  # зеленый фон
    local color_empty="\e[41m"  # красный фон

    # Построение строки прогресс-бара
    printf "\r[" 
    printf "${color_fill}%*s${color_reset}" "$fill" ""
    printf "${color_empty}%*s${color_reset}" "$empty" ""
    printf "] %d%%" "$progress"
}

# Функция для проверки имени пользователя
validate_username() {
    local username=$1
    # Проверка, что имя пользователя не пустое и не содержит пробелов или специальных символов
    if [[ "$username" =~ ^[a-zA-Z0-9_]+$ ]]; then
        return 0  # Имя пользователя валидно
    else
        echo "Неверное имя пользователя. Оно должно содержать только буквы, цифры и подчеркивания."
        return 1  # Имя пользователя невалидно
    fi
}

# Функция для проверки наличия логов
check_logs() {
    # Проверка, существует ли файл auth.log
    if ! ls /var/log/*.log 1> /dev/null 2>&1 || ! grep -q 'auth.log' /var/log/*.log; then
        return 1  # Логи не найдены
    fi
    return 0  # Логи найдены
}

# Этапы установки и обновления
echo "Обновление и установка пакетов..."

# 1. Обновление списка пакетов
show_progress 20
apt-get update -y >/dev/null 2>&1
show_progress 30

# 2. Обновление существующих пакетов
apt-get upgrade -y >/dev/null 2>&1
show_progress 50

# 3. Установка sudo
apt-get install -y sudo >/dev/null 2>&1
show_progress 70

# 4. Установка базовых утилит (ufw и fail2ban)
apt-get install -y ufw fail2ban >/dev/null 2>&1
show_progress 90

# Финальная проверка
show_progress 100
echo -e "\nНастройка завершена!"

# Проверка наличия логов
if ! check_logs; then
    echo -e "\nЛоги не найдены. Устанавливаем rsyslog..."
    apt-get install -y rsyslog >/dev/null 2>&1
    systemctl restart rsyslog
    echo -e "\nRsyslog установлен и перезапущен."
else
    echo -e "\nЛоги найдены, продолжаем настройку Fail2Ban."
fi

# Запрос на создание нового пользователя вместо root
echo -e "\nХотите создать нового пользователя для входа в систему вместо root? (да/нет)"
read -p "(Ваш ответ: да или нет): " create_new_user

# Убираем пробелы и конвертируем ответ в нижний регистр для корректной проверки
create_new_user=$(echo "$create_new_user" | tr '[:upper:]' '[:lower:]' | tr -s ' ')

if [[ "$create_new_user" =~ ^(да|y|yes)$ ]]; then
    # Запрос имени нового пользователя
    while true; do
        read -p "Введите имя нового пользователя (без пробелов и специальных символов): " username
        validate_username "$username" && break
    done

    # Запрос пароля для нового пользователя
    while true; do
        read -s -p "Введите пароль для нового пользователя: " password
        echo
        read -s -p "Повторите пароль: " password_confirm
        echo
        if [[ "$password" == "$password_confirm" && -n "$password" ]]; then
            break
        else
            echo "Пароли не совпадают или пусты. Попробуйте снова."
        fi
    done

    # Создание нового пользователя и добавление его в группу sudo
    useradd -m -s /bin/bash "$username"
    echo "$username:$password" | chpasswd
    usermod -aG sudo "$username"
    echo "${username} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${username}

    echo -e "\nПользователь $username успешно создан и добавлен в группу sudo."
else
    echo -e "\nОставляем root-пользователя для входа в систему."
fi

# Настройка порта для SSH
echo -e "\nДля повышения безопасности сервера рекомендуется изменить стандартный порт SSH."
ssh_ready=false

while [[ "$ssh_ready" != "true" ]]; do
    read -p "Введите новый порт SSH (1024–65535): " ssh_port

    # Валидация диапазона
    if ! [[ "$ssh_port" =~ ^[0-9]+$ ]] || ((ssh_port < 1024 || ssh_port > 65535)); then
        echo "\nНекорректный диапазон. Попробуйте снова."
        continue
    fi

    # Настройка конфигурации
    if grep -q "^#\?Port " /etc/ssh/sshd_config; then
        sed -i "s/^#\?Port .*/Port $ssh_port/" /etc/ssh/sshd_config
    else
        echo "Port $ssh_port" >> /etc/ssh/sshd_config
    fi
    
    # Перезапуск службы
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
    sleep 2

    # Проверяем, что SSH действительно слушает новый порт
    if ss -tlnp | grep -q ":$ssh_port "; then
        echo "\nSSH успешно запущен на порту $ssh_port."
        ssh_ready=true
    else
        echo "\nSSH не поднялся на порту $ssh_port."
        echo "\nВозможные причины: порт занят, заблокирован файрволом или синтаксическая ошибка в sshd_config."
        echo "\nПопробуйте ввести другой порт."
    fi
done

# Настройка firewall с UFW
echo "Настройка фаервола (ufw)..."

# Разрешить подключение по новому порту SSH
ufw allow "$ssh_port"/tcp >/dev/null 2>&1
show_progress 20

# Разрешить трафик на HTTP и HTTPS порты
ufw allow http >/dev/null 2>&1
ufw allow https >/dev/null 2>&1
show_progress 50

# Запретить входящий трафик по умолчанию и разрешить исходящий
ufw default deny incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1
show_progress 70

# Включить UFW
ufw --force enable >/dev/null 2>&1
show_progress 100
echo -e "\nФаервол успешно настроен!"

# Предложение запретить root доступ по SSH
read -p "Хотите запретить вход по SSH для root-пользователя? (да/нет): " disable_root_ssh
if [[ "$disable_root_ssh" =~ ^(да|y|yes)$ ]]; then
    sed -i '/^#*PermitRootLogin/s/^#*\(.*\)/PermitRootLogin no/' /etc/ssh/sshd_config
    systemctl restart ssh
    echo -e "\nВход по SSH для root-пользователя успешно запрещен."
else
    echo -e "\nВход по SSH для root-пользователя оставлен включенным."
fi

# Предложение установить защиту от брутфорса с fail2ban
read -p "Хотите установить защиту от брутфорса с помощью fail2ban? (да/нет): " install_fail2ban

if [[ "$install_fail2ban" =~ ^(да|y|yes)$ ]]; then
    # Конфигурирование fail2ban
    echo -e "\nНастройка fail2ban..."

    # Запрос параметров для fail2ban
    read -p "Введите количество неудачных попыток входа до блокировки: " max_attempts
    read -p "Введите время блокировки в секундах: " bantime
    read -p "Введите временной интервал (в секундах) для подсчета попыток: " findtime

    # Создание или изменение конфигурации для SSH
    cat <<EOL > /etc/fail2ban/jail.d/ssh.local
[sshd]
enabled = true
port    = $ssh_port
logpath = /var/log/auth.log
maxretry = $max_attempts
bantime = $bantime
findtime = $findtime
EOL
    # Перезапуск fail2ban для применения изменений
    systemctl restart fail2ban

    echo -e "\nЗащита от брутфорса с помощью fail2ban настроена и активирована."
else
    echo -e "\nЗащита от брутфорса с помощью fail2ban не будет установлена."
fi


read -p "Хотите настроить маскировку под обычный веб-хостинг? (да/нет): " enable_masking

if [[ "${enable_masking,,}" =~ ^(да|y|yes)$ ]]; then
    echo -e "\nНастройка маскировки сервера"

    # 1. Запрос порта AmneziaWG с валидацией
    while true; do
        read -p "Введите порт для AmneziaWG (по умолчанию 51820): " input_wg_port
        WG_PORT="${input_wg_port:-51820}"
        if [[ "$WG_PORT" =~ ^[0-9]+$ ]] && ((WG_PORT >= 1024 && WG_PORT <= 65535)); then
            break
        else
            echo -e "n\Некорректный порт. Допустимый диапазон: 1024-65535"
        fi
    done

    # 2. Установка зависимостей
    apt install -y curl gnupg2 ca-certificates lsb-release ubuntu-keyring ssl-cert nginx >/dev/null 2>&1 || {
        echo -e "\nОшибка установки Nginx. Проверьте подключение к репозиториям."
        exit 1
    }

    # 3. Настройка Nginx
    cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;

    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    server_tokens off;
    server_name _;
    default_type text/html;

    location / {
        return 403 "<!DOCTYPE html><html><head><title>403 Forbidden</title></head><body style='font-family:sans-serif;text-align:center;padding:50px;background:#f5f5f5;'><h1>403 Forbidden</h1><p>nginx server</p><hr><center>Access denied by server configuration.</center></body></html>";
    }
    location ~ /\. { deny all; }
    location ~* \.(php|asp|aspx|jsp|cgi|pl|py)$ { deny all; }
}
EOF

    # 4. Проверка и запуск Nginx
    if ! nginx -t >/dev/null 2>&1; then
        echo -e "\nОшибка синтаксиса Nginx. Проверьте конфигурацию."
        exit 1
    fi
    systemctl restart nginx
    systemctl enable nginx >/dev/null 2>&1

    # 5. Добавляем порты в уже работающий UFW
    echo -e "\nОбновляем правила файрвола..."
    ufw allow "$ssh_port"/tcp >/dev/null 2>&1
    ufw allow "${WG_PORT}"/udp >/dev/null 2>&1
    ufw allow 80/tcp >/dev/null 2>&1
    ufw allow 443/tcp >/dev/null 2>&1
    ufw reload >/dev/null 2>&1

    echo -e "\nМаскировка успешно настроена"
    echo -e "   🌐 Веб-заглушка активна на портах 80/443"
    echo -e "   🛡️ AmneziaWG будет работать на UDP/${WG_PORT}"
    echo -e "   🔒 Доступ разрешён только по SSH (порт ${ssh_port:-22}) и указанным портам"
else
    echo -e "\nМаскировка пропущена. Сервер останется в режиме 'по умолчанию'."
fi
