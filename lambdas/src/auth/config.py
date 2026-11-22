"""Settings read from the Lambda environment, validated once per container."""

import os
from functools import cache

from pydantic import BaseModel, Field


class Settings(BaseModel):
    site_url: str = Field(pattern=r"^https://[a-z0-9.-]+$")
    origin_secret: str = Field(min_length=32)
    codes_table: str
    code_ttl_seconds: int = Field(gt=0)
    # Only the function that needs each resource is given its environment variable.
    rate_limits_table: str | None = None
    visitors_table: str | None = None
    sender: str | None = None
    signing_key_parameter: str | None = None
    key_pair_id: str | None = None
    cookie_ttl_seconds: int | None = Field(default=None, gt=0)


@cache
def settings() -> Settings:
    return Settings.model_validate({key.lower(): value for key, value in os.environ.items()})


def required[T](value: T | None, name: str) -> T:
    """Return an optional setting that this function depends on, or fail loudly."""
    if value is None:
        raise RuntimeError(f"{name} is not set")
    return value
