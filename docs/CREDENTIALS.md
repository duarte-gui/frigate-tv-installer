# Cadastro de credenciais (passo a passo)

Tudo que precisa de chave/segredo para o sistema funcionar. Nada disso vai para o git
(use `config.env` local e `secrets.yaml` no HA — ambos no `.gitignore`).

## 1) Token do Home Assistant (para o instalador)

HA → seu **Perfil → Segurança → Tokens de acesso de longa duração** → criar → copiar.
Use no `setup.sh` (ou em `config.env` como `HA_TOKEN`).

## 2) Alexa — criar a skill + Lambda (controle por voz)

Resumo (deploy do Lambda via [`aws/template.yaml`](../aws/template.yaml), `sam deploy`):

1. **Amazon Developer Console** (https://developer.amazon.com/alexa/console/ask) → **Create Skill** → modelo **Smart Home**. Anote o **Skill ID**.
2. **Lambda** (região `us-east-1`): `cd aws && sam build && sam deploy --guided --parameter-overrides BaseUrl=https://SEU-HOST AlexaSkillId=amzn1.ask.skill.XXXX`. Copie o **ARN** de saída → cole como *Default endpoint* da skill.
3. **Login with Amazon** (https://developer.amazon.com/loginwithamazon) → Security Profile → pegue **Client ID/Secret** (LWA).
4. **Account Linking** da skill:
   - Authorization URI: `https://SEU-HOST/auth/authorize`
   - Access Token URI: `https://SEU-HOST/auth/token`
   - Client ID: `https://pitangui.amazon.com/` (com a barra final)
   - Auth Scheme: **Credentials in request body** · Scope: `smart_home`
5. App Alexa → ative a skill → faça login → "Alexa, descobrir dispositivos".

> Se o ISP bloqueia 80/443 de entrada (comum no Brasil), exponha o HA por **Cloudflare Tunnel**
> e use esse hostname como `BaseUrl`/`SEU-HOST`.

## 3) Alexa — proactive state reporting (faz o "desligar" por voz funcionar)

Sem isso, a Alexa "congela" o estado e o **desligar** por voz não funciona.

1. Na sua **Smart Home Skill** → menu **PERMISSIONS** → ligue **"Send Alexa Events"**.
2. Copie **Alexa Client Id** e **Alexa Client Secret** (são DIFERENTES do LWA acima).
3. No HA, em `secrets.yaml`:
   ```yaml
   alexa_events_client_id: "amzn1.application-oa2-client.XXXX"
   alexa_events_client_secret: "amzn1.oa2-cs.v1.XXXX"
   ```
4. No `configuration.yaml`, o bloco `alexa: smart_home:` deve ter (já vem no package de referência):
   ```yaml
   alexa:
     smart_home:
       endpoint: https://api.amazonalexa.com/v3/events   # América do Norte (vale p/ pt-BR)
       client_id: !secret alexa_events_client_id
       client_secret: !secret alexa_events_client_secret
       filter: ...
   ```
5. **Reinicie o HA.**
6. No app Alexa: **desative e reative a skill** (refaça o login). Isso faz a Amazon enviar o
   `AcceptGrant` → o HA guarda o token em `.storage/alexa_auth`. **Sem esse passo não há reporte.**

Conferir se o grant chegou (token salvo):
```bash
# no HA, o arquivo .storage/alexa_auth deve conter access_token + refresh_token
```

## 4) Anúncios falados nas Echos (alerta de intrusão)

Use a integração oficial **Amazon Devices** (`alexa_devices`) no HA. Ela cria entidades
`notify.<echo>_announce`. Mire nas **Echos individuais** (o grupo "todo lugar" costuma ficar
`unavailable`). O blueprint de intrusão já aceita uma lista de alvos `notify.*`.

## 5) Segurança

- Nunca commite `secrets.yaml`, `config.env`, `client_secret*.json` ou tokens.
- Se alguma credencial já vazou em histórico/print, **rotacione-a**.
