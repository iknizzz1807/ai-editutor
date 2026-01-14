# myapp/serializers/user.py - User serializers

from rest_framework import serializers
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from ..models.user import User, UserProfile, UserAddress, UserPreferences, UserRole, UserStatus
from ..utils.validators import validate_username, validate_phone


class UserProfileSerializer(serializers.ModelSerializer):
    """Serializer for UserProfile model."""

    class Meta:
        model = UserProfile
        fields = ['first_name', 'last_name', 'avatar', 'bio', 'phone', 'date_of_birth']
        read_only_fields = []


class UserAddressSerializer(serializers.ModelSerializer):
    """Serializer for UserAddress model."""

    class Meta:
        model = UserAddress
        fields = ['id', 'label', 'street', 'city', 'state', 'country', 'zip_code', 'is_default']
        read_only_fields = ['id']


class UserPreferencesSerializer(serializers.ModelSerializer):
    """Serializer for UserPreferences model."""

    class Meta:
        model = UserPreferences
        fields = ['theme', 'language', 'timezone', 'email_notifications',
                  'push_notifications', 'sms_notifications']


class UserListSerializer(serializers.ModelSerializer):
    """Lightweight serializer for user lists."""

    full_name = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ['id', 'email', 'username', 'role', 'status', 'full_name', 'created_at']

    def get_full_name(self, obj):
        return obj.get_full_name()


class UserDetailSerializer(serializers.ModelSerializer):
    """Detailed serializer for single user."""

    profile = UserProfileSerializer(read_only=True)
    preferences = UserPreferencesSerializer(read_only=True)
    addresses = UserAddressSerializer(many=True, read_only=True)
    full_name = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            'id', 'email', 'username', 'role', 'status', 'full_name',
            'email_verified', 'last_login_at', 'created_at', 'updated_at',
            'profile', 'preferences', 'addresses'
        ]
        read_only_fields = ['id', 'email_verified', 'last_login_at', 'created_at', 'updated_at']

    def get_full_name(self, obj):
        return obj.get_full_name()


class UserCreateSerializer(serializers.ModelSerializer):
    """Serializer for creating new users."""

    password = serializers.CharField(write_only=True, min_length=8)
    confirm_password = serializers.CharField(write_only=True)
    profile = UserProfileSerializer(required=False)

    class Meta:
        model = User
        fields = ['email', 'username', 'password', 'confirm_password', 'role', 'profile']

    def validate_username(self, value):
        errors = validate_username(value)
        if errors:
            raise serializers.ValidationError(errors)
        return value

    def validate_password(self, value):
        try:
            validate_password(value)
        except DjangoValidationError as e:
            raise serializers.ValidationError(list(e.messages))
        return value

    # Q: How should we handle the case where email uniqueness check has a race condition?
    def validate(self, attrs):
        if attrs.get('password') != attrs.get('confirm_password'):
            raise serializers.ValidationError({
                'confirm_password': 'Passwords do not match'
            })
        attrs.pop('confirm_password', None)
        return attrs

    def create(self, validated_data):
        profile_data = validated_data.pop('profile', {})
        password = validated_data.pop('password')

        user = User.objects.create_user(
            password=password,
            **validated_data
        )

        # Create profile
        UserProfile.objects.create(user=user, **profile_data)

        # Create default preferences
        UserPreferences.objects.create(user=user)

        return user


class UserUpdateSerializer(serializers.ModelSerializer):
    """Serializer for updating existing users."""

    profile = UserProfileSerializer(required=False)
    preferences = UserPreferencesSerializer(required=False)

    class Meta:
        model = User
        fields = ['username', 'role', 'status', 'profile', 'preferences']

    def validate_username(self, value):
        # Skip validation if username hasn't changed
        if self.instance and self.instance.username == value:
            return value
        errors = validate_username(value)
        if errors:
            raise serializers.ValidationError(errors)
        return value

    def update(self, instance, validated_data):
        profile_data = validated_data.pop('profile', None)
        preferences_data = validated_data.pop('preferences', None)

        # Update user fields
        for attr, value in validated_data.items():
            setattr(instance, attr, value)
        instance.save()

        # Update profile
        if profile_data:
            profile, _ = UserProfile.objects.get_or_create(user=instance)
            for attr, value in profile_data.items():
                setattr(profile, attr, value)
            profile.save()

        # Update preferences
        if preferences_data:
            preferences, _ = UserPreferences.objects.get_or_create(user=instance)
            for attr, value in preferences_data.items():
                setattr(preferences, attr, value)
            preferences.save()

        return instance


class ChangePasswordSerializer(serializers.Serializer):
    """Serializer for changing password."""

    current_password = serializers.CharField(required=True)
    new_password = serializers.CharField(required=True, min_length=8)
    confirm_password = serializers.CharField(required=True)

    def validate_new_password(self, value):
        try:
            validate_password(value)
        except DjangoValidationError as e:
            raise serializers.ValidationError(list(e.messages))
        return value

    def validate(self, attrs):
        if attrs['new_password'] != attrs['confirm_password']:
            raise serializers.ValidationError({
                'confirm_password': 'Passwords do not match'
            })
        if attrs['current_password'] == attrs['new_password']:
            raise serializers.ValidationError({
                'new_password': 'New password must be different from current password'
            })
        return attrs
