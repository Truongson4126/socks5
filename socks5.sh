#!/bin/bash

# Màu hiển thị
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

# 🔧 Cấu hình cố định
port=3128
username="tung8386"
password="zxcv1234"

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Vui lòng chạy script với quyền root.${NC}"
  exit 1
fi

echo -e "${CYAN}→ Port: $port"
echo -e "→ User: $username${NC}"

# Cài nếu chưa có Dante
if ! command -v danted &> /dev/null; then
  echo -e "${YELLOW}Đang cài Dante...${NC}"
  apt update -y && apt install dante-server curl -y
fi

# Tạo file log và đặt quyền
touch /var/log/danted.log
chown nobody:nogroup /var/log/danted.log

# Xác định interface mạng chính
iface=$(ip route | awk '/default/ {print $5; exit}')
if [[ -z "$iface" ]]; then
  echo -e "${RED}Không xác định được interface mạng.${NC}"
  exit 1
fi

# Ghi cấu hình
cat <<EOF > /etc/danted.conf
logoutput: /var/log/danted.log
internal: 0.0.0.0 port = $port
external: $iface
method: username
user.privileged: root
user.notprivileged: nobody
client pass { from: 0.0.0.0/0 to: 0.0.0.0/0 log: connect disconnect error }
socks pass  { from: 0.0.0.0/0 to: 0.0.0.0/0 log: connect disconnect error }
EOF


# Mở port trên firewall
if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
  ufw allow "$port/tcp"
fi

iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null \
  || iptables -A INPUT -p tcp --dport "$port" -j ACCEPT

# Cập nhật service (fix log permission)
svc=$(systemctl show -p FragmentPath danted | cut -d= -f2)
if [[ -f "$svc" ]]; then
  sed -i '/\[Service\]/a ReadWriteDirectories=/var/log' "$svc"
fi

# Khởi động lại dịch vụ
systemctl daemon-reload
systemctl restart danted
systemctl enable danted

# Kiểm tra kết quả
if systemctl is-active --quiet danted; then
  echo -e "${GREEN}Dante đang chạy trên port $port.${NC}"
else
  echo -e "${RED}Khởi động Dante thất bại. Kiểm tra /var/log/danted.log.${NC}"
  exit 1
fi

# Test proxy
echo -e "${CYAN}Đang kiểm tra kết nối proxy...${NC}"
ip=$(hostname -I | awk '{print $1}')
curl -s --proxy socks5h://"$username:$password@$ip:$port" https://ipinfo.io
