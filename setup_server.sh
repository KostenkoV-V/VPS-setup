#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # Без цвета

# Функция для красивого вывода текста
function print_info {
    echo -e "${CYAN}$1${NC}"
}

function print_success {
    echo -e "${GREEN}$1${NC}"
}

function print_warning {
    echo -e "${YELLOW}$1${NC}"
}

function print_error {
    echo -e "${RED}$1${NC}"
}

function print_step {
    echo -e "${PURPLE}[Шаг] $1${NC}"
}

# Обновляем список доступных пакетов
print_info "Обновляем список доступных пакетов..."
apt update -y

# Обновляем все установленные пакеты
print_info "Обновляем все установленные пакеты..."
apt upgrade -y

# Обновляем дистрибутив до последней версии
print_info "Обновляем дистрибутив до последней версии..."
apt dist-upgrade -y

# Устанавливаем sudo
print_info "Устанавливаем sudo..."
apt install sudo -y

# Устанавливаем ufw (если не установлен)
print_info "Устанавливаем ufw (фаервол)..."
apt install ufw -y

# Устанавливаем fail2ban для защиты от брутфорс атак
print_info "Устанавливаем fail2ban для защиты от атак..."
apt install fail2ban -y

# Проверка наличия ss или netstat
print_info "Проверяем наличие утилиты ss или netstat..."
if ! command -v ss &> /dev/null; then
    print_warning "ss не найден, будет установлена утилита netstat."
    apt install net-tools -y
    ss() {
        netstat "$@"
    }
fi

# Функция для проверки, занят ли порт
is_port_free() {
    local port=$1
    # Проверка, используется ли порт
    ss -tuln | grep ":$port" > /dev/null
    return $?
}

# Генерация случайного порта в диапазоне 1024-49151
generate_random_port() {
    local port
    while true; do
        # Генерация случайного порта в диапазоне от 1024 до 49151
        port=$((RANDOM % 48128 + 1024))
        
        # Проверка, свободен ли порт
        if is_port_free $port; then
            echo $port
            return 0
        fi
    done
}

# Генерируем случайный порт для SSH
print_step "Генерируем случайный порт для SSH..."
new_ssh_port=$(generate_random_port)

# Запрашиваем имя нового пользователя
print_info "Введите имя нового пользователя:"
read new_user

# Создаем нового пользователя
print_step "Создаем нового пользователя $new_user..."
adduser $new_user

# Добавляем пользователя в группу sudo
print_step "Добавляем пользователя $new_user в группу sudo..."
usermod -aG sudo $new_user

# Подтверждаем, что пользователь был успешно добавлен в группу sudo
print_success "$new_user добавлен в группу sudo."

print_info "Настройка SSH для повышения безопасности..."

# Редактируем конфигурацию sshd
# Отключаем доступ root по ssh
print_step "Отключаем доступ root по SSH..."
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

# Меняем порт на случайно сгенерированный
print_step "Меняем порт SSH на $new_ssh_port..."
sed -i "s/#Port 22/Port $new_ssh_port/" /etc/ssh/sshd_config

# Отключаем аутентификацию по паролю
print_step "Отключаем аутентификацию по паролю..."
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# Перезапускаем ssh сервис
print_step "Перезапускаем SSH..."
systemctl restart ssh

print_success "SSH настроен: доступ по паролю отключен, доступ root отключен, порт изменен на $new_ssh_port."

# Настройка фаервола
print_info "Настройка фаервола..."
ufw allow $new_ssh_port/tcp
ufw default deny incoming
ufw default allow outgoing
ufw enable

# Запуск и настройка fail2ban
print_info "Настройка fail2ban..."
systemctl start fail2ban
systemctl enable fail2ban

# Очистка пакетов
print_info "Очистка пакетов..."
apt clean
apt autoremove -y

print_success "Фаервол и защита от брутфорса настроены. Система очищена от ненужных пакетов."

echo -e "${GREEN}Процесс завершен успешно! Все настройки выполнены.${NC}"
