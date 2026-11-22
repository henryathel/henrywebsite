"""Six-digit sign-in codes.

A code is guessable (one in a million), so its security comes from the attempt limit and
short expiry, not from the hash. Hashing keeps codes out of the table in readable form,
and including the email means the same code for two people never hashes the same.
"""

import hashlib
import secrets

CODE_DIGITS = 6


def new_code() -> str:
    return f"{secrets.randbelow(10**CODE_DIGITS):0{CODE_DIGITS}d}"


def code_hash(email: str, code: str) -> str:
    return hashlib.sha256(f"{email}:{code}".encode()).hexdigest()


def email_id(email: str) -> str:
    """Short, stable pseudonym for an email address, for logs and rate-limit keys."""
    return hashlib.sha256(email.encode()).hexdigest()[:16]
