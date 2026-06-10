"""
Home Assistant Alexa Smart Home Skill Adapter
Baseado em Jason Hu / Matthew Hilton (Apache 2.0)
Reenvia as diretivas da Alexa para o endpoint /api/alexa/smart_home do HA.
"""
import json
import logging
import os
from typing import Any
import urllib3

_debug = bool(os.environ.get('DEBUG'))
_logger = logging.getLogger('HomeAssistant-SmartHome')
_logger.setLevel(logging.DEBUG if _debug else logging.INFO)
_handler = logging.StreamHandler()
_handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
_logger.addHandler(_handler)
logging.getLogger('urllib3').setLevel(logging.INFO)


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    base_url = os.environ.get('BASE_URL')
    if not base_url:
        raise ValueError('BASE_URL environment variable must be set')
    base_url = base_url.rstrip('/')

    directive = event.get('directive')
    if directive is None:
        raise ValueError('Request missing required directive field')
    if directive.get('header', {}).get('payloadVersion') != '3':
        raise ValueError('Only payloadVersion 3 is supported')

    scope = directive.get('endpoint', {}).get('scope')
    if scope is None:
        scope = directive.get('payload', {}).get('grantee')
    if scope is None:
        scope = directive.get('payload', {}).get('scope')
    if scope is None:
        raise ValueError('Request missing scope')
    if scope.get('type') != 'BearerToken':
        raise ValueError('Only BearerToken scope is supported')

    token = scope.get('token')
    if token is None and _debug:
        token = os.environ.get('LONG_LIVED_ACCESS_TOKEN')

    verify_ssl = not bool(os.environ.get('NOT_VERIFY_SSL'))
    http = urllib3.PoolManager(
        cert_reqs='CERT_REQUIRED' if verify_ssl else 'CERT_NONE',
        timeout=urllib3.Timeout(connect=2.0, read=10.0),
    )

    response = http.request(
        'POST',
        f'{base_url}/api/alexa/smart_home',
        headers={
            'Authorization': f'Bearer {token}',
            'Content-Type': 'application/json',
        },
        body=json.dumps(event).encode('utf-8'),
    )

    if response.status >= 400:
        return {
            'event': {
                'payload': {
                    'type': 'INVALID_AUTHORIZATION_CREDENTIAL'
                    if response.status in (401, 403) else 'INTERNAL_ERROR',
                    'message': response.data.decode('utf-8'),
                }
            }
        }
    return json.loads(response.data.decode('utf-8'))
