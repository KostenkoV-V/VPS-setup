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
