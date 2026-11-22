"""Request bodies, validated with Pydantic."""

from typing import Annotated

from pydantic import AfterValidator, BaseModel, ConfigDict, EmailStr, Field


class SignInRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="ignore")

    # Lower-cased so rate limits and the visitor log treat "Jo@x.com" and "jo@x.com" as one.
    email: Annotated[EmailStr, Field(max_length=254), AfterValidator(str.lower)]


class VerifyRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    # secrets.token_urlsafe(32) is always 43 URL-safe base64 characters.
    token: str = Field(pattern=r"^[A-Za-z0-9_-]{43}$")
