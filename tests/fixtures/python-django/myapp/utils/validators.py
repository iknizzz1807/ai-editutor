# myapp/utils/validators.py - Custom validators

import re
from typing import List, Optional
from django.core.exceptions import ValidationError
from django.core.validators import RegexValidator


# Username validation
def validate_username(value: str) -> List[str]:
    """Validate username format and return list of errors."""
    errors = []

    if len(value) < 3:
        errors.append('Username must be at least 3 characters')

    if len(value) > 30:
        errors.append('Username must be at most 30 characters')

    if not re.match(r'^[a-zA-Z]', value):
        errors.append('Username must start with a letter')

    if not re.match(r'^[\w-]+$', value):
        errors.append('Username can only contain letters, numbers, underscores, and hyphens')

    # Check for reserved usernames
    reserved = ['admin', 'root', 'system', 'api', 'www', 'mail', 'support']
    if value.lower() in reserved:
        errors.append('This username is reserved')

    return errors


def validate_phone(value: str) -> List[str]:
    """Validate phone number format."""
    errors = []

    # Remove common formatting characters
    cleaned = re.sub(r'[\s\-\(\)\.]', '', value)

    if not cleaned:
        return errors  # Empty is allowed

    if not re.match(r'^\+?[0-9]{10,15}$', cleaned):
        errors.append('Invalid phone number format')

    return errors


# Q: Should we add more sophisticated validation for international phone numbers?
def validate_international_phone(value: str, country_code: Optional[str] = None) -> List[str]:
    """Validate international phone number with country-specific rules."""
    errors = []

    if not value:
        return errors

    # Basic format check
    cleaned = re.sub(r'[\s\-\(\)\.]', '', value)

    if not cleaned.startswith('+'):
        errors.append('International phone must start with +')
        return errors

    # Country-specific validation
    country_patterns = {
        'US': r'^\+1[2-9]\d{9}$',
        'UK': r'^\+44[1-9]\d{9,10}$',
        'VN': r'^\+84[3-9]\d{8}$',
        'JP': r'^\+81[1-9]\d{8,9}$',
    }

    if country_code and country_code in country_patterns:
        pattern = country_patterns[country_code]
        if not re.match(pattern, cleaned):
            errors.append(f'Invalid phone number format for {country_code}')

    return errors


class PasswordValidator:
    """Custom password validator with configurable rules."""

    def __init__(
        self,
        min_length: int = 8,
        require_uppercase: bool = True,
        require_lowercase: bool = True,
        require_digit: bool = True,
        require_special: bool = True
    ):
        self.min_length = min_length
        self.require_uppercase = require_uppercase
        self.require_lowercase = require_lowercase
        self.require_digit = require_digit
        self.require_special = require_special

    def validate(self, password: str, user=None) -> None:
        errors = []

        if len(password) < self.min_length:
            errors.append(f'Password must be at least {self.min_length} characters')

        if self.require_uppercase and not re.search(r'[A-Z]', password):
            errors.append('Password must contain at least one uppercase letter')

        if self.require_lowercase and not re.search(r'[a-z]', password):
            errors.append('Password must contain at least one lowercase letter')

        if self.require_digit and not re.search(r'\d', password):
            errors.append('Password must contain at least one digit')

        if self.require_special and not re.search(r'[!@#$%^&*(),.?":{}|<>]', password):
            errors.append('Password must contain at least one special character')

        # Check against common passwords
        common_passwords = ['password', '123456', 'qwerty', 'letmein', 'welcome']
        if password.lower() in common_passwords:
            errors.append('This password is too common')

        # Check if password contains user info
        if user:
            if hasattr(user, 'username') and user.username.lower() in password.lower():
                errors.append('Password cannot contain your username')
            if hasattr(user, 'email'):
                email_name = user.email.split('@')[0].lower()
                if email_name in password.lower():
                    errors.append('Password cannot contain your email')

        if errors:
            raise ValidationError(errors)

    def get_help_text(self) -> str:
        requirements = [f'at least {self.min_length} characters']
        if self.require_uppercase:
            requirements.append('one uppercase letter')
        if self.require_lowercase:
            requirements.append('one lowercase letter')
        if self.require_digit:
            requirements.append('one digit')
        if self.require_special:
            requirements.append('one special character')

        return f'Password must contain: {", ".join(requirements)}'


class EmailDomainValidator:
    """Validate email domain against whitelist/blacklist."""

    def __init__(
        self,
        allowed_domains: Optional[List[str]] = None,
        blocked_domains: Optional[List[str]] = None
    ):
        self.allowed_domains = allowed_domains or []
        self.blocked_domains = blocked_domains or ['tempmail.com', 'throwaway.com']

    def __call__(self, value: str) -> None:
        domain = value.split('@')[-1].lower()

        if self.allowed_domains and domain not in self.allowed_domains:
            raise ValidationError(f'Email domain {domain} is not allowed')

        if domain in self.blocked_domains:
            raise ValidationError(f'Email domain {domain} is not allowed')


# Django validators
username_validator = RegexValidator(
    regex=r'^[a-zA-Z][\w-]*$',
    message='Username must start with a letter and contain only letters, numbers, underscores, and hyphens'
)

slug_validator = RegexValidator(
    regex=r'^[a-z0-9]+(?:-[a-z0-9]+)*$',
    message='Slug must contain only lowercase letters, numbers, and hyphens'
)
