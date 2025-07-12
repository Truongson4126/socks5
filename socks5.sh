#!/bin/bash

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Cố định thông tin
port=3128
username="tung8386"
password="zxcv1234"

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Vui lòng chạy script với quyền root hoặc sudo.${NC}"
  exit 1
fi

echo -e "${CYAN}Port SOCKS5 proxy sẽ dùng: $port${NC}"
echo -e "${CYAN}Username: $username${NC}"

# Cài đặt Dante nếu chưa có
if ! command -v danted &> /dev/null; then
    echo -e "${YELLOW}Đang cài đặt Dante SOCKS5 server...${NC}"
    apt update -y && apt install dante-server curl -y
fi

# Tạo file log cho Dante
touch /var/log/danted.log
chown nobody:nogroup /var/log/danted.log

# Phát hiện interface mạng chính
primary_interface=$(ip route | grep default | awk '{print $5}')
if [[ -z "$primary_interface" ]]; then
    echo -e "${RED}Không thể phát hiện interface mạng chính.${NC}"
    exit 1
fi

# Tạo file cấu hình danted.conf
cat <<EOF > /etc/danted.conf
logoutput: /var/log/danted.log
internal: 0.0.0.0 port = $port
external: $primary_interface
method: username
user.privileged: root
user.notprivileged: nobody
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}
EOF

# Tạo hoặc cập nhật user
if id "$username" &>/dev/null; then
    echo -e "${YELLOW}User $username đã tồn tại, cập nhật mật khẩu.${NC}"
else
    useradd --shell /usr/sbin/nologin "$username"
    echo -e "${GREEN}Đã tạo user $username.${NC}"
fi

echo "$username:$password" | chpasswd
echo -e "${GREEN}Đã đặt mật khẩu cho user $username.${NC}"

# Mở port trên firewall (UFW và iptables)
if command -v ufw &> /dev/null; then
    if ufw status | grep -q "Status: active"; then
        ufw allow "$port/tcp"
    fi
fi

iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport "$port" -j ACCEPT

# Sửa file systemd nếu cần để danted ghi log
service_path=$(systemctl show -p FragmentPath danted | cut -d= -f2)
if [[ -f "$service_path" ]]; then
    sed -i '/\[Service\]/a ReadWriteDirectories=/var/log' "$service_path"
fi

# Khởi động lại và bật tự động danted
systemctl daemon-reload
systemctl restart danted
systemctl enable danted

if systemctl is-active --quiet danted; then
    echo -e "${GREEN}Dante SOCKS5 server đang chạy trên port $port.${NC}"
else
    echo -e "${RED}Khởi động Dante SOCKS5 server thất bại.${NC}"
    exit 1
fi

# Test proxy với curl
proxy_ip=$(hostname -I | awk '{print $1}')
echo -e "${CYAN}Đang test SOCKS5 proxy...${NC}"
curl -v --proxy socks5h://"$username:$password@$proxy_ip:$port" https://ipinfo.io/ || echo -e "${RED}Test proxy thất bại.${NC}"
