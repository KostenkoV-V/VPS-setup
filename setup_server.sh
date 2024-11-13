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

# Функция для проверки валидности имени пользователя
validate_username() {
    local username=$1
    # Проверка на наличие пробелов и запрещенных символов
    if [[ "$username" =~ [^a-zA-Z0-9_] ]]; then
        echo "Имя пользователя может содержать только буквы, цифры и подчеркивания. Пожалуйста, попробуйте снова."
        return 1
    fi
    return 0
}

# Запрос имени пользователя
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
