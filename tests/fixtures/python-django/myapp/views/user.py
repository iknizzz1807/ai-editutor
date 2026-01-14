# myapp/views/user.py - User API views

from rest_framework import viewsets, status, permissions
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.exceptions import ValidationError
from django.shortcuts import get_object_or_404
from django.db import transaction

from ..models.user import User, UserProfile, UserAddress, UserPreferences
from ..serializers.user import (
    UserListSerializer,
    UserDetailSerializer,
    UserCreateSerializer,
    UserUpdateSerializer,
    UserAddressSerializer,
    UserPreferencesSerializer,
    ChangePasswordSerializer,
)
from ..services.user_service import UserService
from ..permissions import IsOwnerOrAdmin, IsAdminUser


class UserViewSet(viewsets.ModelViewSet):
    """ViewSet for user CRUD operations."""

    queryset = User.objects.all()
    permission_classes = [permissions.IsAuthenticated]
    user_service = UserService()

    def get_serializer_class(self):
        if self.action == 'list':
            return UserListSerializer
        elif self.action == 'create':
            return UserCreateSerializer
        elif self.action in ['update', 'partial_update']:
            return UserUpdateSerializer
        return UserDetailSerializer

    def get_permissions(self):
        if self.action == 'create':
            return [permissions.AllowAny()]
        elif self.action in ['update', 'partial_update', 'destroy']:
            return [IsOwnerOrAdmin()]
        elif self.action in ['list', 'activate', 'suspend']:
            return [IsAdminUser()]
        return super().get_permissions()

    def get_queryset(self):
        queryset = super().get_queryset()

        # Filter by role
        role = self.request.query_params.get('role')
        if role:
            queryset = queryset.filter(role=role)

        # Filter by status
        status_param = self.request.query_params.get('status')
        if status_param:
            queryset = queryset.filter(status=status_param)

        # Search
        search = self.request.query_params.get('search')
        if search:
            queryset = User.objects.search(search)

        return queryset

    def list(self, request):
        """List all users with pagination."""
        queryset = self.get_queryset()
        page = self.paginate_queryset(queryset)

        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)

        serializer = self.get_serializer(queryset, many=True)
        return Response(serializer.data)

    def retrieve(self, request, pk=None):
        """Get single user details."""
        user = self.get_object()
        serializer = self.get_serializer(user)
        return Response(serializer.data)

    @transaction.atomic
    def create(self, request):
        """Create new user."""
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()

        return Response(
            UserDetailSerializer(user).data,
            status=status.HTTP_201_CREATED
        )

    # Q: How should we handle concurrent updates to the same user from different clients?
    @transaction.atomic
    def update(self, request, pk=None):
        """Update user."""
        user = self.get_object()
        serializer = self.get_serializer(user, data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()

        return Response(UserDetailSerializer(user).data)

    @transaction.atomic
    def partial_update(self, request, pk=None):
        """Partial update user."""
        user = self.get_object()
        serializer = self.get_serializer(user, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()

        return Response(UserDetailSerializer(user).data)

    def destroy(self, request, pk=None):
        """Delete user (soft delete)."""
        user = self.get_object()
        user.soft_delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=False, methods=['get'])
    def me(self, request):
        """Get current user details."""
        serializer = UserDetailSerializer(request.user)
        return Response(serializer.data)

    @action(detail=False, methods=['patch'])
    def update_profile(self, request):
        """Update current user's profile."""
        profile = self.user_service.update_profile(request.user, request.data)
        return Response(UserDetailSerializer(request.user).data)

    @action(detail=False, methods=['patch'])
    def update_preferences(self, request):
        """Update current user's preferences."""
        self.user_service.update_preferences(request.user, request.data)
        return Response(UserDetailSerializer(request.user).data)

    @action(detail=False, methods=['post'])
    def change_password(self, request):
        """Change current user's password."""
        serializer = ChangePasswordSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        user = request.user

        if not user.check_password(serializer.validated_data['current_password']):
            raise ValidationError({'current_password': 'Incorrect password'})

        user.set_password(serializer.validated_data['new_password'])
        user.save()

        return Response({'message': 'Password changed successfully'})

    @action(detail=True, methods=['post'], permission_classes=[IsAdminUser])
    def activate(self, request, pk=None):
        """Activate user account."""
        user = self.get_object()
        user = self.user_service.activate_user(user)
        return Response(UserDetailSerializer(user).data)

    @action(detail=True, methods=['post'], permission_classes=[IsAdminUser])
    def suspend(self, request, pk=None):
        """Suspend user account."""
        user = self.get_object()
        reason = request.data.get('reason', '')
        duration = request.data.get('duration_days')

        user = self.user_service.suspend_user(user, reason, duration)
        return Response(UserDetailSerializer(user).data)

    @action(detail=False, methods=['get'], permission_classes=[IsAdminUser])
    def stats(self, request):
        """Get user statistics."""
        stats = User.objects.get_stats()
        return Response(stats)


class UserAddressViewSet(viewsets.ModelViewSet):
    """ViewSet for user addresses."""

    serializer_class = UserAddressSerializer
    permission_classes = [permissions.IsAuthenticated, IsOwnerOrAdmin]

    def get_queryset(self):
        return UserAddress.objects.filter(user=self.request.user)

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

    @action(detail=True, methods=['post'])
    def set_default(self, request, pk=None):
        """Set address as default."""
        address = self.get_object()

        # Clear other defaults
        self.get_queryset().filter(is_default=True).update(is_default=False)

        address.is_default = True
        address.save()

        return Response(self.get_serializer(address).data)
