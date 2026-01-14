# myapp/models/managers.py - Custom model managers

from django.db import models
from django.contrib.auth.models import BaseUserManager
from django.db.models import Q, Count, Avg
from django.utils import timezone
from datetime import timedelta


class SoftDeleteManager(models.Manager):
    """Manager that filters out soft-deleted records by default."""

    def get_queryset(self):
        return super().get_queryset().filter(is_deleted=False)

    def with_deleted(self):
        """Include soft-deleted records."""
        return super().get_queryset()

    def only_deleted(self):
        """Only return soft-deleted records."""
        return super().get_queryset().filter(is_deleted=True)


class UserManager(BaseUserManager):
    """Custom manager for User model."""

    def get_queryset(self):
        return super().get_queryset().select_related('profile', 'preferences')

    def create_user(self, email, username, password=None, **extra_fields):
        if not email:
            raise ValueError('Users must have an email address')
        if not username:
            raise ValueError('Users must have a username')

        email = self.normalize_email(email)
        user = self.model(email=email, username=username, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, email, username, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        extra_fields.setdefault('role', 'admin')
        extra_fields.setdefault('status', 'active')
        extra_fields.setdefault('email_verified', True)

        if extra_fields.get('is_staff') is not True:
            raise ValueError('Superuser must have is_staff=True.')
        if extra_fields.get('is_superuser') is not True:
            raise ValueError('Superuser must have is_superuser=True.')

        return self.create_user(email, username, password, **extra_fields)

    def active(self):
        """Return only active users."""
        return self.get_queryset().filter(status='active', is_active=True)

    def by_role(self, role):
        """Filter users by role."""
        return self.get_queryset().filter(role=role)

    def admins(self):
        """Return admin users."""
        return self.by_role('admin')

    def search(self, query):
        """Search users by email, username, or profile name."""
        return self.get_queryset().filter(
            Q(email__icontains=query) |
            Q(username__icontains=query) |
            Q(profile__first_name__icontains=query) |
            Q(profile__last_name__icontains=query)
        )

    # Q: How can we optimize this query for large datasets with millions of users?
    def get_stats(self):
        """Get user statistics."""
        queryset = self.get_queryset()
        now = timezone.now()
        month_ago = now - timedelta(days=30)

        return {
            'total': queryset.count(),
            'active': queryset.filter(status='active').count(),
            'by_role': dict(
                queryset.values('role').annotate(count=Count('id')).values_list('role', 'count')
            ),
            'by_status': dict(
                queryset.values('status').annotate(count=Count('id')).values_list('status', 'count')
            ),
            'new_this_month': queryset.filter(created_at__gte=month_ago).count(),
            'verified': queryset.filter(email_verified=True).count(),
        }

    def recently_active(self, days=7):
        """Return users who logged in recently."""
        cutoff = timezone.now() - timedelta(days=days)
        return self.get_queryset().filter(last_login_at__gte=cutoff)

    def inactive_for(self, days=30):
        """Return users who haven't logged in for specified days."""
        cutoff = timezone.now() - timedelta(days=days)
        return self.get_queryset().filter(
            Q(last_login_at__lt=cutoff) | Q(last_login_at__isnull=True)
        )
