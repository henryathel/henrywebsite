"""Request bodies, validated with Pydantic."""

from typing import Annotated

from pydantic import AfterValidator, BaseModel, BeforeValidator, ConfigDict, EmailStr, Field

from auth.codes import CODE_DIGITS

# Lower-cased so rate limits and the visitor log treat "Jo@x.com" and "jo@x.com" as one.
Email = Annotated[EmailStr, Field(max_length=254), AfterValidator(str.lower)]


def _digits_only(value: object) -> object:
    # Accept "482 913" or "482-913" as typed or pasted.
    return "".join(ch for ch in value if ch not in " -") if isinstance(value, str) else value


class SignInRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="ignore")

    email: Email


class VerifyRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="ignore")

    email: Email
    code: Annotated[str, BeforeValidator(_digits_only), Field(pattern=rf"^\d{{{CODE_DIGITS}}}$")]
