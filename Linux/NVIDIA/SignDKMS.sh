#!/bin/bash
set -e

# 1. Generate a MOK signing key for DKMS (Debian's dkms does this automatically
#    if we tell it to sign)
cat > /etc/dkms/framework.conf.d/nvidia-sign.conf <<'EOF'
mok_signing_key=/var/lib/dkms/mok.key
mok_certificate=/var/lib/dkms/mok.pub
sign_file=/lib/modules/$kernelver/build/scripts/sign-file
EOF

# Generate the key pair if it doesn't exist
if [ ! -f /var/lib/dkms/mok.key ]; then
    openssl req -new -x509 -newkey rsa:2048 \
        -keyout /var/lib/dkms/mok.key \
        -outform DER -out /var/lib/dkms/mok.pub \
        -nodes -days 36500 -subj "/CN=DKMS module signing key/"
fi

# 2. Enroll the key with the firmware — you'll be asked to create a one-time password
mokutil --import /var/lib/dkms/mok.pub

# 3. Rebuild the module so it gets signed
dkms uninstall nvidia-current/550.163.01 || true
dkms install nvidia-current/550.163.01

echo
echo "Now REBOOT. During startup a blue MOK Manager screen will appear:"
echo "  Enroll MOK → Continue → Yes → enter the password you just set → Reboot"
