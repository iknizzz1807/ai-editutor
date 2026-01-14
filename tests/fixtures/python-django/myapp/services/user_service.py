# myapp/services/user_service.py - User business logic

from typing import Optional, List, Dict, Any
from django.db import transaction
from django.core.exceptions import ValidationError
from django.utils import timezone
from datetime import timedelta

from ..models.user import User, UserProfile, UserAddress, UserPreferences, UserStatus
from .email_service import EmailService


class UserService:
    """Service layer for user-related business logic."""

    def __init__(self):
        self.email_service = EmailService()

    @transaction.atomic
    def create_user(
        self,
        email: str,
        username: str,
        password: str,
        profile_data: Optional[Dict[str, Any]] = None,
        send_verification: bool = True
    ) -> User:
        """Create a new user with profile and preferences."""
        # Check for existing user
        if User.objects.filter(email=email).exists():
            raise ValidationError({'email': 'Email already registered'})

        if User.objects.filter(username=username).exists():
            raise ValidationError({'username': 'Username already taken'})

        # Create user
        user = User.objects.create_user(
            email=email,
            username=username,
            password=password
        )

        # Create profile
        profile_data = profile_data or {}
        UserProfile.objects.create(user=user, **profile_data)

        # Create default preferences
        UserPreferences.objects.create(user=user)

        # Send verification email
        if send_verification:
            self.email_service.send_verification_email(user)

        return user

    def activate_user(self, user: User) -> User:
        """Activate a user account."""
        user.status = UserStatus.ACTIVE
        user.email_verified = True
        user.save(update_fields=['status', 'email_verified', 'updated_at'])
        return user

    def deactivate_user(self, user: User, reason: str = '') -> User:
        """Deactivate a user account."""
        user.status = UserStatus.INACTIVE
        user.save(update_fields=['status', 'updated_at'])

        # Log deactivation
        self._log_status_change(user, UserStatus.INACTIVE, reason)

        return user

    def suspend_user(self, user: User, reason: str, duration_days: Optional[int] = None) -> User:
        """Suspend a user account."""
        user.status = UserStatus.SUSPENDED
        user.save(update_fields=['status', 'updated_at'])

        self._log_status_change(user, UserStatus.SUSPENDED, reason)

        # Send notification
        self.email_service.send_suspension_notice(user, reason, duration_days)

        return user

    # Q: How should we handle bulk operations efficiently without hitting memory limits?
    def bulk_update_status(
        self,
        user_ids: List[str],
        new_status: str,
        reason: str = ''
    ) -> int:
        """Update status for multiple users."""
        users = User.objects.filter(id__in=user_ids)
        updated_count = users.update(status=new_status, updated_at=timezone.now())

        # Log changes
        for user in users:
            self._log_status_change(user, new_status, reason)

        return updated_count

    def update_profile(self, user: User, data: Dict[str, Any]) -> UserProfile:
        """Update user profile information."""
        profile, created = UserProfile.objects.get_or_create(user=user)

        allowed_fields = ['first_name', 'last_name', 'avatar', 'bio', 'phone', 'date_of_birth']

        for field in allowed_fields:
            if field in data:
                setattr(profile, field, data[field])

        profile.save()
        return profile

    def update_preferences(self, user: User, data: Dict[str, Any]) -> UserPreferences:
        """Update user preferences."""
        preferences, created = UserPreferences.objects.get_or_create(user=user)

        allowed_fields = [
            'theme', 'language', 'timezone',
            'email_notifications', 'push_notifications', 'sms_notifications'
        ]

        for field in allowed_fields:
            if field in data:
                setattr(preferences, field, data[field])

        preferences.save()
        return preferences

    @transaction.atomic
    def add_address(self, user: User, address_data: Dict[str, Any]) -> UserAddress:
        """Add a new address for user."""
        is_default = address_data.pop('is_default', False)

        # If this is the first address, make it default
        if not user.addresses.exists():
            is_default = True

        address = UserAddress.objects.create(
            user=user,
            is_default=is_default,
            **address_data
        )

        return address

    def set_default_address(self, user: User, address_id: str) -> UserAddress:
        """Set an address as default."""
        address = user.addresses.get(id=address_id)

        # Clear other defaults
        user.addresses.filter(is_default=True).update(is_default=False)

        # Set new default
        address.is_default = True
        address.save(update_fields=['is_default', 'updated_at'])

        return address

    def get_user_stats(self, user: User) -> Dict[str, Any]:
        """Get statistics for a specific user."""
        return {
            'account_age_days': (timezone.now() - user.created_at).days,
            'address_count': user.addresses.count(),
            'last_login': user.last_login_at,
            'is_verified': user.email_verified,
        }

    def search_users(
        self,
        query: str,
        filters: Optional[Dict[str, Any]] = None,
        limit: int = 20
    ) -> List[User]:
        """Search users by query and filters."""
        queryset = User.objects.search(query)

        if filters:
            if 'role' in filters:
                queryset = queryset.filter(role=filters['role'])
            if 'status' in filters:
                queryset = queryset.filter(status=filters['status'])
            if 'verified' in filters:
                queryset = queryset.filter(email_verified=filters['verified'])

        return list(queryset[:limit])

    def get_inactive_users(self, days: int = 30) -> List[User]:
        """Get users who haven't logged in for specified days."""
        return list(User.objects.inactive_for(days=days))

    def cleanup_unverified_users(self, days: int = 7) -> int:
        """Remove unverified users older than specified days."""
        cutoff = timezone.now() - timedelta(days=days)

        unverified = User.objects.filter(
            email_verified=False,
            status=UserStatus.PENDING,
            created_at__lt=cutoff
        )

        count = unverified.count()
        unverified.delete()

        return count

    def _log_status_change(self, user: User, new_status: str, reason: str) -> None:
        """Log user status changes for audit."""
        # Would integrate with audit logging system
        pass


class UserAddressService:
    """Service for managing user addresses."""

    def validate_address(self, address_data: Dict[str, Any]) -> bool:
        """Validate address data."""
        required_fields = ['street', 'city', 'state', 'country', 'zip_code']

        for field in required_fields:
            if not address_data.get(field):
                raise ValidationError({field: f'{field} is required'})

        return True

    def format_address(self, address: UserAddress) -> str:
        """Format address for display."""
        parts = [
            address.street,
            f"{address.city}, {address.state} {address.zip_code}",
            address.country
        ]
        return '\n'.join(parts)
