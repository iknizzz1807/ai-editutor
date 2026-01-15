# Snapshot: Python Django Serializer

This document shows what gets sent to the LLM when a user asks a question in a Django REST Framework serializer.

## Input

### Source File
- **Path:** `tests/fixtures/python-django/myapp/serializers/user.py`
- **Filetype:** `python`
- **Total lines:** ~180

### Question Location
- **Line number:** 95
- **Q: Comment:** `# Q: How should we handle the case where email uniqueness check has a race condition?`

### Related Files (same project)
```
myapp/
├── serializers/
│   └── user.py             <- THIS FILE
├── models/
│   └── user.py             <- imported (User, UserProfile, etc.)
├── utils/
│   └── validators.py       <- imported
└── views/
    └── user.py             <- uses this serializer
```

## Context Extraction

### Imports Detected
```python
from rest_framework import serializers
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from ..models.user import User, UserProfile, UserAddress, UserPreferences, UserRole, UserStatus
from ..utils.validators import validate_username, validate_phone
```

### Current Function
`validate` (in `UserCreateSerializer` class)

### Code Context (±50 lines around question)
The `>>>` marker shows where the question line is located:

```python
     71: class UserCreateSerializer(serializers.ModelSerializer):
     72:     """Serializer for creating new users."""
     73:
     74:     password = serializers.CharField(write_only=True, min_length=8)
     75:     confirm_password = serializers.CharField(write_only=True)
     76:     profile = UserProfileSerializer(required=False)
     77:
     78:     class Meta:
     79:         model = User
     80:         fields = ['email', 'username', 'password', 'confirm_password', 'role', 'profile']
     81:
     82:     def validate_username(self, value):
     83:         errors = validate_username(value)
     84:         if errors:
     85:             raise serializers.ValidationError(errors)
     86:         return value
     87:
     88:     def validate_password(self, value):
     89:         try:
     90:             validate_password(value)
     91:         except DjangoValidationError as e:
     92:             raise serializers.ValidationError(list(e.messages))
     93:         return value
     94:
>>>  95:     # Q: How should we handle the case where email uniqueness check has a race condition?
     96:     def validate(self, attrs):
     97:         if attrs.get('password') != attrs.get('confirm_password'):
     98:             raise serializers.ValidationError({
     99:                 'confirm_password': 'Passwords do not match'
    100:             })
    101:         attrs.pop('confirm_password', None)
    102:         return attrs
    103:
    104:     def create(self, validated_data):
    105:         profile_data = validated_data.pop('profile', {})
    106:         password = validated_data.pop('password')
    107:
    108:         user = User.objects.create_user(
    109:             password=password,
    110:             **validated_data
    111:         )
    112:
    113:         # Create profile
    114:         UserProfile.objects.create(user=user, **profile_data)
    115:
    116:         # Create default preferences
    117:         UserPreferences.objects.create(user=user)
    118:
    119:         return user
```

## LLM Payload

### System Prompt

```
You are an expert coding mentor helping a developer learn and understand code.

Your role is to TEACH, not to do the work for them.

CRITICAL: Your response will be inserted as an INLINE COMMENT directly in the code file.
Keep responses CONCISE and well-structured. Avoid excessive length.

CORE PRINCIPLES:
1. EXPLAIN concepts clearly, don't just give solutions
2. Reference the actual code context provided
3. Always respond in English
4. Be concise - this will appear as code comments
5. Use plain text, avoid emoji headers

RESPONSE GUIDELINES:
- Keep explanations focused and to the point
- Include 1-2 short code examples when helpful
- Mention best practices briefly
- Warn about common mistakes in 1-2 sentences
- Suggest what to learn next in one line

DO NOT:
- Use emoji headers (no 📚, 💡, ✅, etc.)
- Write overly long responses
- Repeat information unnecessarily

QUESTION mode - Give direct, educational answer.

Structure:
1. Direct answer first (clear and concise)
2. Brief explanation of why/how
3. One code example if helpful
4. One common mistake to avoid
5. One thing to learn next
```

### User Prompt

```
Mode: Q

Context:
Language: python
File: user.py
Current function: validate

Imports:
​```python
from rest_framework import serializers
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from ..models.user import User, UserProfile, UserAddress, UserPreferences, UserRole, UserStatus
from ..utils.validators import validate_username, validate_phone
​```

Code context (>>> marks the question line):
​```python
     71: class UserCreateSerializer(serializers.ModelSerializer):
     72:     """Serializer for creating new users."""
     ...
     82:     def validate_username(self, value):
     ...
>>>  95:     # Q: How should we handle the case where email uniqueness check has a race condition?
     96:     def validate(self, attrs):
     97:         if attrs.get('password') != attrs.get('confirm_password'):
     ...
    104:     def create(self, validated_data):
    105:         profile_data = validated_data.pop('profile', {})
    106:         password = validated_data.pop('password')
    107:
    108:         user = User.objects.create_user(
     ...
​```

Question:
How should we handle the case where email uniqueness check has a race condition?
```

## Expected Response Location

The AI response will be inserted as a docstring directly after line 95:

```python
    # Q: How should we handle the case where email uniqueness check has a race condition?

    """
    A:
    Race conditions occur when two requests check email uniqueness simultaneously,
    both pass validation, then both try to create - one fails with IntegrityError.

    Solutions:
    1. Database-level constraint (recommended): Let DB enforce uniqueness, catch IntegrityError
    2. select_for_update(): Lock the row during check (adds latency)
    3. Transaction isolation: Use SERIALIZABLE level (performance impact)

    Best approach for Django:
    try:
        user = User.objects.create_user(...)
    except IntegrityError:
        raise serializers.ValidationError({'email': 'Email already exists'})

    Common mistake: Relying only on validate() check without handling DB exceptions.

    Learn next: Django database transactions and select_for_update().
    """
    def validate(self, attrs):
```
