# myapp/models/base.py - Base models and mixins

import uuid
from django.db import models
from django.utils import timezone


class TimestampMixin(models.Model):
    """Mixin that adds created_at and updated_at fields."""

    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class SoftDeleteMixin(models.Model):
    """Mixin for soft delete functionality."""

    deleted_at = models.DateTimeField(null=True, blank=True, db_index=True)
    is_deleted = models.BooleanField(default=False, db_index=True)

    class Meta:
        abstract = True

    def soft_delete(self):
        self.is_deleted = True
        self.deleted_at = timezone.now()
        self.save(update_fields=['is_deleted', 'deleted_at'])

    def restore(self):
        self.is_deleted = False
        self.deleted_at = None
        self.save(update_fields=['is_deleted', 'deleted_at'])


class BaseModel(TimestampMixin, SoftDeleteMixin):
    """Base model with UUID primary key and common fields."""

    id = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False
    )

    class Meta:
        abstract = True
        ordering = ['-created_at']

    def __repr__(self):
        return f"<{self.__class__.__name__}(id={self.id})>"


class AuditMixin(models.Model):
    """Mixin for tracking who created/modified records."""

    created_by = models.ForeignKey(
        'myapp.User',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='%(class)s_created'
    )
    modified_by = models.ForeignKey(
        'myapp.User',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='%(class)s_modified'
    )

    class Meta:
        abstract = True
