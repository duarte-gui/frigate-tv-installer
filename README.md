# frigate-tv-installer

Instalador e orquestrador do sistema **Câmeras na TV** — mostra as câmeras do
[Frigate](https://frigate.video) por cima da Android TV (overlay/PIP), dispara por
sensores/alarme e dá controle por voz pela Alexa.

> **Comece por aqui.** Este repo amarra os outros e instala tudo com um comando.

## 🚀 Instalação rápida

```bash
git clone https://github.com/duarte-gui/frigate-tv-installer
cd frigate-tv-installer
./setup.sh            # menu interativo
```

No menu você consegue:
1. **Scan da rede** — descobre Home Assistant, Frigate e a Android TV automaticamente.
2. **Configurar** — IPs/token/credenciais (ou aceita o que o scan achou). Salva em `config.env`.
3. **Instalar apps na TV** — baixa o APK certo e instala via `adb`.
4. **Instalar no Home Assistant** — envia o package e reinicia.
5. **Tudo de uma vez.**

Linha de comando direto (sem menu): `./setup.sh scan|configure|apps|ha|all|doctor`.

## 📺 Escolha do dispositivo de TV

O instalador pergunta o tipo, porque a técnica muda:

| Dispositivo | Técnica | App instalado |
|---|---|---|
| **Fire TV Stick** | PIP nativo | [`com.frigate.tv`](https://github.com/duarte-gui/Frigate-on-Firestick) |
| **Xiaomi / Android TV sem PIP** | Overlay (janela flutuante) | [`com.frigate.tvx`](https://github.com/duarte-gui/FrigateTV4Xiaomi) |
| **Outro compatível** | Você escolhe (pip/overlay) | conforme a escolha |

## 🧩 O que o instalador cobre

- ✅ **Apps de TV** — via `adb` a partir das *Releases* (sem precisar buildar).
- ✅ **Home Assistant** — package `frigate_pip` + bloco `alexa:` (envia por Samba/SSH ou guia o manual).
- ✅ **Blueprints** — automações importáveis por URL (ver abaixo), sem editar YAML.
- ✅ **Alexa/Lambda** — template AWS SAM em [`aws/`](aws/) (deploy em 1 comando) + checklist.

## 🏠 Blueprints (Home Assistant)

Importe por **Configurações → Automações → Blueprints → Importar Blueprint** e cole a URL:

- **Overlay por sensor** — câmera aparece quando um sensor dispara
  `homeassistant/blueprints/frigate_overlay_por_sensor.yaml`
- **Alerta de intrusão** — alarme armado + sensor → overlay + Alexa anuncia
  `homeassistant/blueprints/frigate_alerta_intrusao.yaml`
- **Câmera por voz** — `input_boolean` (exposto à Alexa) liga/desliga o overlay
  `homeassistant/blueprints/frigate_camera_por_voz.yaml`

> Os blueprints usam os scripts `script.pip_mostrar` / `pip_desligar` do package
> **incluído aqui** em [`homeassistant/packages/frigate_pip.yaml`](homeassistant/packages/frigate_pip.yaml)
> (copie para `/config/packages/` do seu HA — o `setup.sh` faz isso por você).

## ☁️ Alexa (skill self-hosted) + Lambda

```bash
cd aws
sam build && sam deploy --guided \
  --region us-east-1 \
  --parameter-overrides BaseUrl=https://SEU-HOST AlexaSkillId=amzn1.ask.skill.XXXX
```

O passo a passo completo da skill (Login with Amazon, account linking, descoberta e o
**proactive state reporting** que faz o "desligar" por voz funcionar) está em
**[docs/CREDENTIALS.md](docs/CREDENTIALS.md)** (e no repo
[homeassistant-alexa-lambda](https://github.com/duarte-gui/homeassistant-alexa-lambda)).

## 🔌 Pré-requisitos

- `adb` (instalar apps na TV) e `curl`. Opcionais: `nmap` (scan rápido), `gh` (baixar Releases), `sam` (deploy do Lambda).
- Android TV com **depuração por rede (ADB)** ligada.
- Home Assistant com **token de longa duração** (Perfil → Segurança).
- (Voz) HA acessível por HTTPS público — se o ISP bloqueia 80/443, use **Cloudflare Tunnel**.

## 🗺️ Arquitetura e dependências

Veja o **[SYSTEM-OVERVIEW.md](SYSTEM-OVERVIEW.md)** (mapa de todos os repos e como dependem entre si).

| Repositório | Papel |
|---|---|
| [Frigate-on-Firestick](https://github.com/duarte-gui/Frigate-on-Firestick) | App PIP (Fire TV) |
| [FrigateTV4Xiaomi](https://github.com/duarte-gui/FrigateTV4Xiaomi) | App overlay (Android TV) |
| [homeassistant-alexa-lambda](https://github.com/duarte-gui/homeassistant-alexa-lambda) | Lambda da skill Alexa |
| [homeguard](https://github.com/duarte-gui/homeguard) | Firmware ESP32 (sensores/alarme) |
| `frigate-pip-homeassistant` _(privado)_ | Config HA de referência — o essencial (package + blueprints + credenciais) está **neste repo** |

## 🔒 Segurança

`config.env` (token/senha) e `*.apk` estão no `.gitignore`. Nunca commite credenciais.

## Licença

MIT.
