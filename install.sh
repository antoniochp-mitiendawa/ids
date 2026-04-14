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

async function esperarConfirmacion(mensaje) {
    const respuesta = await cuestion(mensaje);
    return respuesta.toLowerCase();
}

async function extraerCanalPorMensaje(sock, config) {
    return new Promise((resolve) => {
        const handler = async (msg) => {
            const messages = msg.messages;
            if (!messages || messages.length === 0) return;
            
            const message = messages[0];
            const remoteJid = message.key.remoteJid;
            
            if (remoteJid && remoteJid.includes('@newsletter')) {
                let nombreCanal = "Sin nombre";
                try {
                    const metadata = await sock.newsletterMetadata(remoteJid);
                    if (metadata && metadata.name) {
                        nombreCanal = metadata.name;
                    }
                } catch (e) {
                    nombreCanal = remoteJid.split('@')[0];
                }
                
                const canalData = {
                    id: remoteJid,
                    nombre: nombreCanal
                };
                
                console.log(`\n\x1b[32m[CANAL DETECTADO]\x1b[0m`);
                console.log(`   ID: ${canalData.id}`);
                console.log(`   Nombre: ${canalData.nombre}`);
                
                try {
                    console.log(`\x1b[36m[INFO] Enviando canal a Google Sheets...\x1b[0m`);
                    await axios.post(config.url_sheets, { 
                        action: 'uploadCanales', 
                        canales: JSON.stringify([canalData]) 
                    });
                    console.log(`\x1b[32m[ÉXITO] Canal guardado en pestaña 'Canales'.\x1b[0m`);
                } catch (e) {
                    console.log(`\x1b[31m[ERROR] Al enviar canal:\x1b[0m`, e.message);
                }
                
                sock.ev.off('messages.upsert', handler);
                resolve(true);
            }
        };
        
        sock.ev.on('messages.upsert', handler);
    });
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
            
            console.log("\n\x1b[1;33m═══════════════════════════════════════════════════════════════\x1b[0m");
            console.log("\x1b[1;36m[EXTRACTOR DE CANALES]\x1b[0m");
            console.log("\x1b[1;33m═══════════════════════════════════════════════════════════════\x1b[0m\n");
            
            const tieneCanales = await esperarConfirmacion("\x1b[33m[?] ¿Tienes canales que quieras extraer el ID? (si/no): \x1b[0m");
            
            if (tieneCanales === 'si' || tieneCanales === 's' || tieneCanales === 'sí') {
                let continuar = true;
                let canalesExtraidos = 0;
                
                while (continuar) {
                    console.log(`\n\x1b[1;34m[CANAL ${canalesExtraidos + 1}]\x1b[0m Escribe un mensaje en el canal que deseas extraer...`);
                    await extraerCanalPorMensaje(sock, config);
                    canalesExtraidos++;
                    
                    const respuesta = await esperarConfirmacion("\n\x1b[33m[?] ¿Tienes otro canal para extraer? (si/no): \x1b[0m");
                    if (respuesta !== 'si' && respuesta !== 's' && respuesta !== 'sí') {
                        continuar = false;
                    }
                }
                console.log(`\n\x1b[32m[FINALIZADO] Se extrajeron ${canalesExtraidos} canal(es). Saliendo...\x1b[0m`);
            } else {
                console.log("\n\x1b[33m[INFO] No se extrajeron canales. Saliendo...\x1b[0m");
            }
            
            process.exit(0);
        }
        if (c === 'close' && ld.error?.output?.statusCode !== DisconnectReason.loggedOut) iniciar();
    });
}
iniciar();
EOF

echo -e "\e[1;32m[OK] extractor.js creado.\e[0m"

echo -e "\n\e[1;34m[5/5] INICIANDO EXTRACTOR...\e[0m"
cd $HOME/extractor_ids && node extractor.js
