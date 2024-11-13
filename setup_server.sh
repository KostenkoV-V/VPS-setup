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

# Анимация загрузки рядом с прогресс-баром
loading_animation() {
    local pid=$1
    local spin='-\|/'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${spin:i++%${#spin}:1}"
        sleep 0.1
    done
    printf "\r "
}

# Функция для проверки валидности имени пользователя
validate_username() {
    local username=$1
    if [[ "$username" =~ [^a-zA-Z0-9_] ]]; then
        echo "Имя пользователя может содержать только буквы, цифры и подчеркивания. Пожалуйста, попробуйте снова."
        return 1
    fi
    return 0
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

    echo -e "\nПользователь $username успешно создан и добавлен в группу sudo."
else
    echo -e "\nОставляем root-пользователя для входа в систему."
fi

# Настройка порта для SSH
while true; do
    echo "Для повышения безопасности сервера рекомендуется изменить стандартный порт SSH."
    read -p "Введите новый порт SSH (рекомендуется диапазон от 1024 до 65535): " ssh_port
    if [[ "$ssh_port" =~ ^[0-9]+$ ]] && ((ssh_port >= 1024 && ssh_port <= 65535)); then
        break
    else
        echo "Пожалуйста, введите корректный порт в диапазоне от 1024 до 65535."
    fi
done

# Настройка порта SSH в конфигурации
sed -i "s/^#Port 22/Port $ssh_port/" /etc/ssh/sshd_config
systemctl restart ssh
echo -e "\nПорт SSH успешно изменен на $ssh_port."

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
