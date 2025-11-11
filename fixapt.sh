bash -c 'cat << "EOS" > /usr/local/bin/fix-apt.sh
#!/bin/bash
cp /etc/apt/sources.list /etc/apt/sources.list.bak
cat <<EOF > /etc/apt/sources.list
deb http://archive.ubuntu.com/ubuntu focal main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu focal-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu focal-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu focal-security main restricted universe multiverse
EOF
apt-get clean
apt-get update --fix-missing
apt-get upgrade -y
EOS
chmod +x /usr/local/bin/fix-apt.sh
/usr/local/bin/fix-apt.sh'
