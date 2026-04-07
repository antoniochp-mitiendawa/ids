#!/data/data/com.termux/files/usr/bin/bash

echo -e "\n\e[1;34m[1/5] ACTUALIZANDO SISTEMA...\e[0m"
pkg update -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" 2>/dev/null
pkg upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" 2>/dev/null
if [ $? -eq 0 ]; then echo -e "\e[1;32m[OK] Sistema actualizado.\e[0m"; else echo -e "\e[1;31m[ERROR] Falló actualización.\e[0m"; exit 1; fi

echo -e "\n\e[1;34m[2/5] INSTALANDO HERRAMIENTAS...\e[0m"
pkg install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" nodejs git python clang make binutils 2>/dev/null
if [ $? -eq 0 ]; then echo -e "\e[1;32m[OK] Herramientas instaladas.\e[0m"; else echo -e "\e[1;31m[ERROR] Falló instalación.\e[0m"; exit 1; fi

echo -e "\n\e[1;34m[3/5] PREPARANDO DIRECTORIO Y LIBRERÍAS...\e[0m"
mkdir -p $HOME/extractor_ids && cd $HOME/extractor_ids
npm init -y > /dev/null 2>&1
npm install @whiskeysockets/baileys pino axios readline --force --silent 2>/dev/null
if [ $? -eq 0 ]; then echo -e "\e[1;32m[OK] Librerías instaladas.\e[0m"; else echo -e "\e[1;31m[ERROR] Falló NPM.\e[0m"; exit 1; fi

echo -e "\n\e[1;34m[4/5] CREANDO EXTRACTOR...\e[0m"
cat << 'EOF' > extractor.js
const { default: makeWASocket, useMultiFileAuthState, fetchLatestBaileysVersion, delay, DisconnectReason } = require("@whiskeysockets/baileys");
const pino = require("pino");
const axios = require("axios");
const fs = require("fs");
const readline = require("readline");

const CONFIG_FILE = "./config.json";
const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const cuestion = (t) => new Promise((r) => rl.question(t, r));

async function obtenerConfiguracion() {
    if (fs.existsSync(CONFIG_FILE)) return JSON.parse(fs.readFileSync(CONFIG_FILE));
    console.log("\n\x1b[44m\x1b[37m CONFIGURACIÓN INICIAL \x1b[0m");
    const url = await cuestion("\x1b[33m[ ? ] Pega tu URL de Google Sheets: \x1b[0m");
    const config = { url_sheets: url.trim() };
    fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));
    console.log("\x1b[32m[OK] URL guardada en config.json\x1b[0m");
    return config;
}

async function iniciar() {
    const config = await obtenerConfiguracion();
    const { state, saveCreds } = await useMultiFileAuthState('sesion_extractor');
    const { version } = await fetchLatestBaileysVersion();
    const sock = makeWASocket({ version, logger: pino({ level: 'silent' }), auth: state, printQRInTerminal: false });

    if (!sock.authState.creds.registered) {
        console.log("\n\x1b[36m[SISTEMA] Generando código de vinculación...\x1b[0m");
        const num = await cuestion("\x1b[33m[?] Número (ej: 5215512345678): \x1b[0m");
        const codigo = await sock.requestPairingCode(num.replace(/[^0-9]/g, ''));
        console.log(`\n\x1b[32m[CÓDIGO] Vincular en WhatsApp con: \x1b[1m\x1b[47m\x1b[30m ${codigo} \x1b[0m\n`);
    }

    sock.ev.on('creds.update', saveCreds);
    sock.ev.on('connection.update', async (u) => {
        const { connection: c, lastDisconnect: ld } = u;
        if (c === 'open') {
            console.log("\n\x1b[32m[OK] Conectado. Sincronizando grupos (15s)...\x1b[0m");
            await delay(15000);
            try {
                const chats = await sock.groupFetchAllParticipating();
                const lista = Object.values(chats).map(g => ({ id: g.id, nombre: g.subject }));
                console.log(`\x1b[36m[INFO] Encontrados ${lista.length} grupos. Enviando...\x1b[0m`);
                const res = await axios.post(config.url_sheets, { action: 'upload', grupos: JSON.stringify(lista) });
                if (res.data.status === "success") console.log("\x1b[32m[ÉXITO] Hoja actualizada correctamente.\x1b[0m");
            } catch (e) { console.log("\x1b[31m[ERROR] Al enviar datos:\x1b[0m", e.message); }
            process.exit(0);
        }
        if (c === 'close' && ld.error?.output?.statusCode !== DisconnectReason.loggedOut) iniciar();
    });
}
iniciar();
EOF

echo -e "\e[1;32m[OK] extractor.js creado.\e[0m"

echo -e "\n\e[1;34m[5/5] VALIDANDO...\e[0m"
node -c extractor.js > /dev/null 2>&1
if [ $? -eq 0 ]; then 
    echo -e "\e[1;32m[COMPLETO] Instalación exitosa.\e[0m"
    echo -e "\e[1;33mPara iniciar: cd ~/extractor_ids && node extractor.js\e[0m\n"
else 
    echo -e "\e[1;31m[ERROR] Archivo corrupto.\e[0m"; 
    exit 1; 
fi
