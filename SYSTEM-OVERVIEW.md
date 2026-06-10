# Câmeras na TV — Frigate + Home Assistant + Alexa

Sistema que mostra as câmeras do [Frigate](https://frigate.video) **por cima** do que está
passando na Android TV (overlay/PIP), dispara automaticamente por sensores de porta/alarme e
permite **controle por voz** pela Alexa — incluindo um **alerta de intrusão** falado.

Este arquivo é o índice geral: cada função aponta para o repositório responsável.

## 📦 Repositórios

| Repositório | Camada | Função |
|---|---|---|
| [**Frigate-on-Firestick**](https://github.com/duarte-gui/Frigate-on-Firestick) | App TV | `com.frigate.tv` — Fire TV: PIP + tela cheia (D-pad) |
| [**FrigateTV4Xiaomi**](https://github.com/duarte-gui/FrigateTV4Xiaomi) | App TV | `com.frigate.tvx` — overlay (janela flutuante) p/ Android TV sem PIP (Xiaomi) |
| [**homeguard**](https://github.com/duarte-gui/homeguard) | Firmware | ESP32 — sensores de porta/presença, alarme e sirene (via MQTT) |
| **frigate-pip-homeassistant** _(privado)_ | Home Assistant | Automações/scripts que orquestram tudo (o "cérebro") |
| [**homeassistant-alexa-lambda**](https://github.com/duarte-gui/homeassistant-alexa-lambda) | Nuvem | AWS Lambda — ponte da Alexa Smart Home → HA |
| [frigate-config-ui](https://github.com/duarte-gui/frigate-config-ui) | Frigate | Editor web da config do Frigate (opcional) |
| [ha-backup](https://github.com/duarte-gui/ha-backup) | Backup | Snapshot cifrado do Home Assistant |

## 🧱 Infraestrutura

| Componente | Endereço | Papel |
|---|---|---|
| Home Assistant | `192.168.1.90:8123` | Orquestrador central |
| Frigate (+go2rtc) | `192.168.1.110:5000` | Câmeras / streams WebRTC |
| Xiaomi TV Stick 4K | `192.168.1.190` | Tela onde a câmera aparece |
| ESP32 Homeguard | via MQTT | Sensores + alarme + sirene |
| Echos Alexa | nuvem Amazon | Voz (entrada) + áudio (saída) |
| Cloudflare Tunnel | `ha.duito.com.br` | Expõe o HA (contorna bloqueio 80/443 do ISP) |
| AWS Lambda | `us-east-1` | Skill Alexa → HA |

## ⚙️ Funcionalidades (→ repositório)

1. **Ver câmera em tela cheia (manual)** — app `com.frigate.tv`
   → [Frigate-on-Firestick](https://github.com/duarte-gui/Frigate-on-Firestick)
2. **Overlay (janelinha) na TV** — app `com.frigate.tvx`, intent `show`/`hide`
   → [FrigateTV4Xiaomi](https://github.com/duarte-gui/FrigateTV4Xiaomi)
3. **Overlay automático por sensor** — `pip_auto_garagem` (portão/presença → overlay)
   → [frigate-pip-homeassistant](https://github.com/duarte-gui/frigate-pip-homeassistant) + [homeguard](https://github.com/duarte-gui/homeguard)
4. **Controle por voz (Alexa)** — `pip_voz_*` (ligar/desligar câmera)
   → [frigate-pip-homeassistant](https://github.com/duarte-gui/frigate-pip-homeassistant) + [homeassistant-alexa-lambda](https://github.com/duarte-gui/homeassistant-alexa-lambda)
5. **Alerta de intrusão** 🔔 — `alarme_garagem_intruso` (alarme armado + sensor → overlay + Alexa anuncia "ALERTA")
   → [frigate-pip-homeassistant](https://github.com/duarte-gui/frigate-pip-homeassistant) + [homeguard](https://github.com/duarte-gui/homeguard)
6. **Sincronia de estado (proactive reporting)** — HA avisa a Alexa → habilita o "desligar" por voz
   → [frigate-pip-homeassistant](https://github.com/duarte-gui/frigate-pip-homeassistant) + [homeassistant-alexa-lambda](https://github.com/duarte-gui/homeassistant-alexa-lambda)

## 🔗 Mapa de dependências

```
                        ┌─────────────────────────────┐
                        │   HOME ASSISTANT (cérebro)   │
                        │  frigate-pip-homeassistant   │
                        └─────────────────────────────┘
   ┌───────────────┬──────────────┼───────────────┬──────────────────┐
   │               │              │               │                  │
[homeguard]     [Frigate       [Xiaomi         [Alexa voz         [Alexa
 sensores/       streams]       overlay]        entrada]           announce]
 alarme/MQTT     go2rtc         FrigateTV4X.    Lambda+CF tunnel   alexa_devices
   │               │              │               │                  │
   └──── (3) Overlay automático ──┘               │                  │
   │                              │               │                  │
   └──── (5) Alerta intrusão ─────┴───────────────┼──────────────────┘
                                  │               │
        (4) Controle por voz ─────┴───────────────┘
                                  │
        (6) Proactive reporting ──┘  → mantém a Alexa em sincronia (habilita o "desligar")
```

**Acoplamentos-chave:**
- `input_boolean.pip_*` é o **ponto de encontro** entre voz (4), automático (3) e intrusão (5).
- **Proactive reporting (6)** é o que faz o "desligar" por voz ser confiável.
- **Cloudflare Tunnel** é gargalo único da voz (4) — se cair, o controle local e os sensores seguem.
- **`media_player.fire_tv`** (androidtv → Xiaomi) é o canal ADB de todo overlay; se o IP do Xiaomi mudar, quebra 2/3/4/5.

## ⚠️ Pontos frágeis / pendências

- Sirene física desconectada (refino futuro no firmware [homeguard](https://github.com/duarte-gui/homeguard)).
- Echo do banheiro / grupo "todo lugar" caem offline → `continue_on_error` garante que as outras anunciam.
- Permissão de overlay do app some ao reinstalar (reconceder via `adb appops`).
- Sensor Tuya "Porta sala" ainda sem integração (decisão de hardware pendente).

## 🗂️ Estrutura local

```
.
├── frigate-tv/            → repo Frigate-on-Firestick (app com.frigate.tv)
├── frigate-tv-xiaomi/     → repo FrigateTV4Xiaomi (app com.frigate.tvx)
├── homeassistant/         → repo frigate-pip-homeassistant (config HA)
├── aws-lambda/            → repo homeassistant-alexa-lambda (Lambda)
├── frigate_pip.yaml       → cópia do package do HA
└── firepip.sh             → script ADB legado (referência)
```

> 🔒 Segredos (chaves Alexa/OpenAI/Google, tokens) **nunca** vão pro git — ficam em
> `~/.config/secrets/` localmente e em `secrets.yaml` (no `.gitignore`) no HA.
