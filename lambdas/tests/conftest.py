import base64
import json
from collections.abc import Iterator
from typing import Any

import boto3
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from moto import mock_aws

from auth import config, cookies, mailer, store

SECRET = "s" * 40
SITE = "https://www.example.test"


@pytest.fixture
def signing_key() -> rsa.RSAPrivateKey:
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


@pytest.fixture
def aws(monkeypatch: pytest.MonkeyPatch, signing_key: rsa.RSAPrivateKey) -> Iterator[None]:
    env = {
        "AWS_DEFAULT_REGION": "eu-north-1",
        "AWS_ACCESS_KEY_ID": "testing",
        "AWS_SECRET_ACCESS_KEY": "testing",
        "SITE_URL": SITE,
        "ORIGIN_SECRET": SECRET,
        "TOKENS_TABLE": "tokens",
        "TOKEN_TTL_SECONDS": "1800",
        "RATE_LIMITS_TABLE": "rate-limits",
        "VISITORS_TABLE": "visitors",
        "SENDER": "signin@example.test",
        "SIGNING_KEY_PARAMETER": "/test/cookie-signing-key",
        "KEY_PAIR_ID": "K2TESTKEYPAIR",
        "COOKIE_TTL_SECONDS": "432000",
    }
    for name, value in env.items():
        monkeypatch.setenv(name, value)
    for cached in (config.settings, store._table, mailer._ses, cookies._ssm, cookies._private_key):
        cached.cache_clear()

    with mock_aws():
        dynamodb = boto3.client("dynamodb")
        for table, key in (("tokens", "token_hash"), ("rate-limits", "key"), ("visitors", "email")):
            dynamodb.create_table(
                TableName=table,
                KeySchema=[{"AttributeName": key, "KeyType": "HASH"}],
                AttributeDefinitions=[{"AttributeName": key, "AttributeType": "S"}],
                BillingMode="PAY_PER_REQUEST",
            )
        boto3.client("ses").verify_domain_identity(Domain="example.test")
        pem = signing_key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        ).decode()
        boto3.client("ssm").put_parameter(
            Name="/test/cookie-signing-key", Value=pem, Type="SecureString"
        )
        yield


def event(
    method: str,
    path: str,
    *,
    body: str | None = None,
    query: dict[str, str] | None = None,
    secret: str = SECRET,
    viewer: str = "198.51.100.7:51234",
    content_type: str = "application/x-www-form-urlencoded",
    encode: bool = True,
) -> dict[str, Any]:
    """An HTTP API payload 2.0 event as it arrives through CloudFront."""
    return {
        "version": "2.0",
        "rawPath": path,
        "headers": {
            "content-type": content_type,
            "x-origin-verify": secret,
            "cloudfront-viewer-address": viewer,
        },
        "queryStringParameters": query,
        "requestContext": {"http": {"method": method, "path": path}},
        "body": base64.b64encode(body.encode()).decode() if body and encode else body,
        "isBase64Encoded": bool(body and encode),
    }


def sent_messages() -> list[dict[str, Any]]:
    """Emails captured by moto's SES backend."""
    from moto.core.models import DEFAULT_ACCOUNT_ID
    from moto.ses.models import ses_backends

    backend = ses_backends[DEFAULT_ACCOUNT_ID]["eu-north-1"]
    return [json.loads(json.dumps(vars(message), default=str)) for message in backend.sent_messages]
