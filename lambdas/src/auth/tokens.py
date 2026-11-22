"""One-time sign-in tokens. Only the SHA-256 hash is ever stored."""

import hashlib
import secrets


def new_token() -> str:
    return secrets.token_urlsafe(32)


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def email_id(email: str) -> str:
    """Short, stable pseudonym for an email address, for logs and rate-limit keys."""
    return hashlib.sha256(email.encode()).hexdigest()[:16]
