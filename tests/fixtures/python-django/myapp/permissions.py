# myapp/permissions.py - Custom permissions

from rest_framework import permissions
from rest_framework.request import Request
from rest_framework.views import APIView


class IsOwnerOrAdmin(permissions.BasePermission):
    """Allow access to object owner or admin users."""

    def has_object_permission(self, request: Request, view: APIView, obj) -> bool:
        # Admin can access anything
        if request.user.is_staff or request.user.role == 'admin':
            return True

        # Check if user owns the object
        if hasattr(obj, 'user'):
            return obj.user == request.user

        # Check if object is the user itself
        if hasattr(obj, 'email'):
            return obj == request.user

        return False


class IsAdminUser(permissions.BasePermission):
    """Allow access only to admin users."""

    def has_permission(self, request: Request, view: APIView) -> bool:
        return (
            request.user.is_authenticated and
            (request.user.is_staff or request.user.role == 'admin')
        )


class IsModeratorOrAdmin(permissions.BasePermission):
    """Allow access to moderators and admins."""

    def has_permission(self, request: Request, view: APIView) -> bool:
        if not request.user.is_authenticated:
            return False

        return request.user.role in ['admin', 'moderator'] or request.user.is_staff


class IsActiveUser(permissions.BasePermission):
    """Allow access only to active users."""

    def has_permission(self, request: Request, view: APIView) -> bool:
        return (
            request.user.is_authenticated and
            request.user.is_active and
            request.user.status == 'active'
        )


class IsVerifiedUser(permissions.BasePermission):
    """Allow access only to email-verified users."""

    def has_permission(self, request: Request, view: APIView) -> bool:
        return (
            request.user.is_authenticated and
            request.user.email_verified
        )


class ReadOnly(permissions.BasePermission):
    """Allow read-only access."""

    def has_permission(self, request: Request, view: APIView) -> bool:
        return request.method in permissions.SAFE_METHODS


# Q: How should we implement role-based permissions for complex hierarchies?
class RoleBasedPermission(permissions.BasePermission):
    """Role-based permission with hierarchy support."""

    # Role hierarchy (higher index = more privileges)
    ROLE_HIERARCHY = ['guest', 'user', 'moderator', 'admin']

    def __init__(self, required_role: str = 'user'):
        self.required_role = required_role

    def has_permission(self, request: Request, view: APIView) -> bool:
        if not request.user.is_authenticated:
            return False

        user_role = request.user.role

        # Get role indices
        try:
            user_level = self.ROLE_HIERARCHY.index(user_role)
            required_level = self.ROLE_HIERARCHY.index(self.required_role)
        except ValueError:
            return False

        return user_level >= required_level

    @classmethod
    def require_role(cls, role: str):
        """Factory method to create permission for specific role."""
        return type(f'Require{role.title()}', (cls,), {'required_role': role})


class ResourcePermission(permissions.BasePermission):
    """Permission based on resource-specific rules."""

    # Resource-specific permission map
    RESOURCE_PERMISSIONS = {
        'user': {
            'list': ['admin', 'moderator'],
            'retrieve': ['admin', 'moderator', 'user'],
            'create': ['admin'],
            'update': ['admin', 'moderator'],
            'delete': ['admin'],
        },
        'post': {
            'list': ['admin', 'moderator', 'user', 'guest'],
            'retrieve': ['admin', 'moderator', 'user', 'guest'],
            'create': ['admin', 'moderator', 'user'],
            'update': ['admin', 'moderator'],
            'delete': ['admin'],
        }
    }

    def has_permission(self, request: Request, view: APIView) -> bool:
        if not request.user.is_authenticated:
            return False

        resource = getattr(view, 'resource_name', None)
        action = getattr(view, 'action', None)

        if not resource or not action:
            return True

        allowed_roles = self.RESOURCE_PERMISSIONS.get(resource, {}).get(action, [])

        return request.user.role in allowed_roles


class ConditionalPermission(permissions.BasePermission):
    """Permission with conditional logic."""

    def has_permission(self, request: Request, view: APIView) -> bool:
        # Allow all GET requests
        if request.method in permissions.SAFE_METHODS:
            return request.user.is_authenticated

        # POST requires verified user
        if request.method == 'POST':
            return (
                request.user.is_authenticated and
                request.user.email_verified
            )

        # PUT/PATCH requires active user
        if request.method in ['PUT', 'PATCH']:
            return (
                request.user.is_authenticated and
                request.user.status == 'active'
            )

        # DELETE requires admin
        if request.method == 'DELETE':
            return request.user.role == 'admin'

        return False
