# myapp/middleware/auth.py - Authentication middleware

import logging
from typing import Optional, Callable
from django.http import HttpRequest, HttpResponse, JsonResponse
from django.utils import timezone
from django.conf import settings
from datetime import timedelta

logger = logging.getLogger(__name__)


class LastActivityMiddleware:
    """Update user's last activity timestamp."""

    def __init__(self, get_response: Callable):
        self.get_response = get_response
        self.update_interval = getattr(settings, 'LAST_ACTIVITY_INTERVAL', 300)  # 5 min

    def __call__(self, request: HttpRequest) -> HttpResponse:
        response = self.get_response(request)

        if request.user.is_authenticated:
            self._update_last_activity(request.user)

        return response

    def _update_last_activity(self, user) -> None:
        """Update last activity if interval has passed."""
        now = timezone.now()

        # Only update if enough time has passed
        if user.last_login_at:
            elapsed = (now - user.last_login_at).total_seconds()
            if elapsed < self.update_interval:
                return

        user.last_login_at = now
        user.save(update_fields=['last_login_at'])


class IPTrackingMiddleware:
    """Track user's IP address on requests."""

    def __init__(self, get_response: Callable):
        self.get_response = get_response

    def __call__(self, request: HttpRequest) -> HttpResponse:
        if request.user.is_authenticated:
            ip_address = self._get_client_ip(request)
            self._track_ip(request.user, ip_address)

        return self.get_response(request)

    def _get_client_ip(self, request: HttpRequest) -> str:
        """Extract client IP from request."""
        x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
        if x_forwarded_for:
            return x_forwarded_for.split(',')[0].strip()
        return request.META.get('REMOTE_ADDR', '')

    def _track_ip(self, user, ip_address: str) -> None:
        """Update user's last login IP if changed."""
        if user.last_login_ip != ip_address:
            user.last_login_ip = ip_address
            user.save(update_fields=['last_login_ip'])


# Q: What security considerations should we have for session management?
class SessionSecurityMiddleware:
    """Enhance session security."""

    def __init__(self, get_response: Callable):
        self.get_response = get_response
        self.session_timeout = getattr(settings, 'SESSION_TIMEOUT', 3600)  # 1 hour
        self.max_sessions = getattr(settings, 'MAX_USER_SESSIONS', 5)

    def __call__(self, request: HttpRequest) -> HttpResponse:
        if request.user.is_authenticated:
            # Check session timeout
            if self._is_session_expired(request):
                return self._handle_expired_session(request)

            # Update session timestamp
            self._refresh_session(request)

        return self.get_response(request)

    def _is_session_expired(self, request: HttpRequest) -> bool:
        """Check if session has expired."""
        last_activity = request.session.get('last_activity')
        if not last_activity:
            return False

        elapsed = timezone.now().timestamp() - last_activity
        return elapsed > self.session_timeout

    def _handle_expired_session(self, request: HttpRequest) -> JsonResponse:
        """Handle expired session."""
        request.session.flush()
        return JsonResponse(
            {'error': 'Session expired', 'code': 'SESSION_EXPIRED'},
            status=401
        )

    def _refresh_session(self, request: HttpRequest) -> None:
        """Refresh session timestamp."""
        request.session['last_activity'] = timezone.now().timestamp()


class RateLimitMiddleware:
    """Rate limit requests per user/IP."""

    def __init__(self, get_response: Callable):
        self.get_response = get_response
        self.rate_limit = getattr(settings, 'RATE_LIMIT', 100)  # requests per minute
        self.cache_prefix = 'rate_limit:'

    def __call__(self, request: HttpRequest) -> HttpResponse:
        identifier = self._get_identifier(request)

        if self._is_rate_limited(identifier):
            return JsonResponse(
                {'error': 'Rate limit exceeded', 'code': 'RATE_LIMITED'},
                status=429
            )

        self._increment_counter(identifier)
        return self.get_response(request)

    def _get_identifier(self, request: HttpRequest) -> str:
        """Get rate limit identifier (user ID or IP)."""
        if request.user.is_authenticated:
            return f"user:{request.user.id}"

        ip = request.META.get('HTTP_X_FORWARDED_FOR', '').split(',')[0].strip()
        if not ip:
            ip = request.META.get('REMOTE_ADDR', 'unknown')
        return f"ip:{ip}"

    def _is_rate_limited(self, identifier: str) -> bool:
        """Check if identifier has exceeded rate limit."""
        from django.core.cache import cache

        key = f"{self.cache_prefix}{identifier}"
        count = cache.get(key, 0)
        return count >= self.rate_limit

    def _increment_counter(self, identifier: str) -> None:
        """Increment request counter."""
        from django.core.cache import cache

        key = f"{self.cache_prefix}{identifier}"

        try:
            cache.incr(key)
        except ValueError:
            cache.set(key, 1, timeout=60)  # 1 minute window


class APIKeyMiddleware:
    """Authenticate requests using API keys."""

    def __init__(self, get_response: Callable):
        self.get_response = get_response
        self.header_name = getattr(settings, 'API_KEY_HEADER', 'X-API-Key')

    def __call__(self, request: HttpRequest) -> HttpResponse:
        # Skip if already authenticated
        if request.user.is_authenticated:
            return self.get_response(request)

        api_key = request.META.get(f'HTTP_{self.header_name.upper().replace("-", "_")}')

        if api_key:
            user = self._authenticate_api_key(api_key)
            if user:
                request.user = user
                request.api_key_auth = True

        return self.get_response(request)

    def _authenticate_api_key(self, api_key: str) -> Optional:
        """Authenticate user by API key."""
        from ..models.user import User

        try:
            # Would look up API key in database
            # For now, just return None
            return None
        except Exception as e:
            logger.error(f"API key auth error: {e}")
            return None
