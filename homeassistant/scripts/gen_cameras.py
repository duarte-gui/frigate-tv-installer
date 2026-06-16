#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Gerador automático das entidades do HA para as câmeras do Frigate na TV.
- Lê as câmeras do Frigate (/api/config) e resolve o stream "detect" de cada uma.
- Gera input_select + input_boolean.pip_<slug> + automation pip_voz_<slug>
  (com exclusão mútua) em /config/packages/frigate_cameras_generated.yaml.
- Idempotente: só reescreve se o conteúdo mudar (retorna se mudou + resumo JSON).
- Avisa se o stream do overlay for H265 (WebRTC não toca -> overlay preto).

Uso:
  python3 gen_cameras.py --dry-run         # imprime o YAML, NÃO grava
  python3 gen_cameras.py                    # grava se mudou; imprime JSON de resumo
"""
import json, sys, re, urllib.request, unicodedata

FRIGATE = "http://192.168.1.110:5000"
GO2RTC  = "http://192.168.1.110:1984"
OUT     = "/config/packages/frigate_cameras_generated.yaml"

# O NOME da câmera coincide com o cadastrado no Frigate (só troca _ por espaço).
# OVERRIDES opcional: fixar slug/stream/icone de alguma câmera específica (vazio por padrão).
OVERRIDES = {}

def http_json(url, timeout=8):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return json.loads(r.read().decode())

def slugify(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")

def resolve_detect_stream(cam_cfg, streams):
    """Acha o nome do stream go2rtc do papel 'detect' (senão record/qualquer)."""
    inputs = cam_cfg.get("ffmpeg", {}).get("inputs", [])
    chosen = None
    for role in ("detect", "record"):
        for i in inputs:
            if role in i.get("roles", []):
                chosen = i.get("path", ""); break
        if chosen: break
    if not chosen and inputs:
        chosen = inputs[0].get("path", "")
    chosen = chosen or ""
    # 1) restream go2rtc: rtsp://127.0.0.1:8554/<nome> -> <nome>
    m = re.search(r"8554/([A-Za-z0-9_]+)", chosen)
    if m and m.group(1) in streams:
        return m.group(1)
    # 2) URL direta: casa pela parte APÓS o '@' (host+path+query), ignorando credenciais
    def after_at(u):
        mm = re.search(r"@(.*)$", u or "")
        return (mm.group(1) if mm else (u or "")).strip()
    target = after_at(chosen)
    if target:
        for name, srcs in streams.items():
            srcs = srcs if isinstance(srcs, list) else [srcs]
            if any(after_at(s) == target for s in srcs):
                return name
    return None

def probe_codec(stream):
    """Retorna 'H264'/'H265'/None consultando o go2rtc (acorda o produtor)."""
    import time
    try:
        # acorda o produtor consumindo um trecho do mp4
        try: urllib.request.urlopen(f"{GO2RTC}/api/stream.mp4?src={stream}", timeout=3).read(2048)
        except Exception: pass
        for _ in range(5):
            d = http_json(f"{GO2RTC}/api/streams?src={stream}", timeout=5)
            for p in d.get("producers", []):
                for med in p.get("medias", []) or []:
                    if "H265" in med or "HEVC" in med: return "H265"
                    if "H264" in med: return "H264"
            time.sleep(0.6)
    except Exception:
        pass
    return None

def build():
    cfg = http_json(f"{FRIGATE}/api/config")
    streams = cfg.get("go2rtc", {}).get("streams", {})
    cams = []
    for cam_name, cam_cfg in cfg.get("cameras", {}).items():
        key = cam_name.lower()
        ov = OVERRIDES.get(key)
        if ov:
            slug, name, icon, stream = ov["slug"], ov["name"], ov["icon"], ov["stream"]
        else:
            slug = slugify(cam_name)
            # "Camera <nome do Frigate>" -> comando "ligar camera <x>" (prefixo desambigua na Alexa)
            name = "Camera " + cam_name.replace("_", " ")
            icon = "mdi:cctv"
            stream = resolve_detect_stream(cam_cfg, streams) or slug
        cams.append({"slug": slug, "name": name, "icon": icon, "stream": stream,
                     "codec": probe_codec(stream)})
    cams.sort(key=lambda c: c["slug"])
    return cams

def gen_yaml(cams):
    L = ["# GERADO AUTOMATICAMENTE por gen_cameras.py — NAO editar a mao.",
         "# (booleans + seletor + automacoes de voz, com exclusao mutua)", "",
         "input_select:", "  camera_pip:", "    name: Camera PIP", "    icon: mdi:cctv",
         "    options:"]
    for c in cams: L.append(f"      - {c['stream']}")
    L += [f"    initial: {cams[0]['stream']}" if cams else "", "", "input_boolean:"]
    for c in cams:
        L += [f"  pip_{c['slug']}:", f"    name: \"{c['name']}\"", f"    icon: {c['icon']}"]
    L += ["", "automation:"]
    slugs = [c["slug"] for c in cams]
    for c in cams:
        others = [f"input_boolean.pip_{s}" for s in slugs if s != c["slug"]]
        all_off = " and ".join([f"is_state('input_boolean.pip_{s}','off')" for s in slugs])
        L += [
            f"  - alias: PIP voz - {c['slug']}",
            f"    id: pip_voz_{c['slug']}",
            f"    mode: queued",
            f"    trigger:",
            f"      - platform: state",
            f"        entity_id: input_boolean.pip_{c['slug']}",
            f"    action:",
            f"      - choose:",
            f"          - conditions: \"{{{{ trigger.to_state.state == 'on' }}}}\"",
            f"            sequence:",
        ]
        if others:
            L += [f"              - service: input_boolean.turn_off", f"                target:", f"                  entity_id:"]
            for o in others: L.append(f"                    - {o}")
        L += [
            f"              - service: script.pip_mostrar",
            f"                data: {{ cam: {c['stream']} }}",
            f"        default:",
            f"          - condition: template",
            f"            value_template: \"{{{{ {all_off} }}}}\"",
            f"          - service: script.pip_desligar",
        ]
    return "\n".join(L) + "\n"

if __name__ == "__main__":
    dry = "--dry-run" in sys.argv
    cams = build()
    yaml_text = gen_yaml(cams)
    changed = True
    try:
        with open(OUT) as f: changed = (f.read() != yaml_text)
    except FileNotFoundError:
        changed = True
    if dry:
        print(yaml_text)
        print("# ---- RESUMO ----", file=sys.stderr)
        print(json.dumps({"cameras": cams, "changed": changed}, ensure_ascii=False, indent=2), file=sys.stderr)
    else:
        if changed:
            with open(OUT, "w") as f: f.write(yaml_text)
        print(json.dumps({"changed": changed,
                          "cameras": [c["slug"] for c in cams],
                          "h265": [c["slug"] for c in cams if c["codec"] == "H265"]},
                         ensure_ascii=False))
