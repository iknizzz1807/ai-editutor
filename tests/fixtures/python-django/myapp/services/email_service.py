# myapp/services/email_service.py - Email service

from typing import Optional, List, Dict, Any
from django.conf import settings
from django.core.mail import send_mail, EmailMultiAlternatives
from django.template.loader import render_to_string
from django.utils.html import strip_tags
import logging

logger = logging.getLogger(__name__)


class EmailService:
    """Service for sending emails."""

    def __init__(self):
        self.from_email = getattr(settings, 'DEFAULT_FROM_EMAIL', 'noreply@example.com')
        self.site_name = getattr(settings, 'SITE_NAME', 'MyApp')
        self.base_url = getattr(settings, 'BASE_URL', 'http://localhost:8000')

    def send_verification_email(self, user) -> bool:
        """Send email verification link to user."""
        token = self._generate_verification_token(user)
        verification_url = f"{self.base_url}/verify-email?token={token}"

        context = {
            'user': user,
            'verification_url': verification_url,
            'site_name': self.site_name,
        }

        return self._send_template_email(
            to_email=user.email,
            subject=f'Verify your email for {self.site_name}',
            template='emails/verify_email.html',
            context=context
        )

    def send_password_reset_email(self, user, token: str) -> bool:
        """Send password reset link to user."""
        reset_url = f"{self.base_url}/reset-password?token={token}"

        context = {
            'user': user,
            'reset_url': reset_url,
            'site_name': self.site_name,
            'expires_in': '24 hours',
        }

        return self._send_template_email(
            to_email=user.email,
            subject=f'Reset your password for {self.site_name}',
            template='emails/password_reset.html',
            context=context
        )

    def send_welcome_email(self, user) -> bool:
        """Send welcome email to new user."""
        context = {
            'user': user,
            'site_name': self.site_name,
            'login_url': f"{self.base_url}/login",
        }

        return self._send_template_email(
            to_email=user.email,
            subject=f'Welcome to {self.site_name}!',
            template='emails/welcome.html',
            context=context
        )

    def send_suspension_notice(
        self,
        user,
        reason: str,
        duration_days: Optional[int] = None
    ) -> bool:
        """Send account suspension notification."""
        context = {
            'user': user,
            'reason': reason,
            'duration_days': duration_days,
            'site_name': self.site_name,
            'support_email': getattr(settings, 'SUPPORT_EMAIL', 'support@example.com'),
        }

        return self._send_template_email(
            to_email=user.email,
            subject=f'Your {self.site_name} account has been suspended',
            template='emails/suspension_notice.html',
            context=context
        )

    # Q: What's the best approach for handling email delivery failures and retries?
    def send_bulk_email(
        self,
        users: List,
        subject: str,
        template: str,
        extra_context: Optional[Dict[str, Any]] = None
    ) -> Dict[str, int]:
        """Send email to multiple users."""
        results = {'sent': 0, 'failed': 0}

        for user in users:
            context = {
                'user': user,
                'site_name': self.site_name,
                **(extra_context or {})
            }

            success = self._send_template_email(
                to_email=user.email,
                subject=subject,
                template=template,
                context=context
            )

            if success:
                results['sent'] += 1
            else:
                results['failed'] += 1

        return results

    def send_notification_email(
        self,
        user,
        notification_type: str,
        data: Dict[str, Any]
    ) -> bool:
        """Send notification email based on type."""
        templates = {
            'new_login': 'emails/new_login.html',
            'password_changed': 'emails/password_changed.html',
            'profile_updated': 'emails/profile_updated.html',
            'security_alert': 'emails/security_alert.html',
        }

        template = templates.get(notification_type)
        if not template:
            logger.warning(f'Unknown notification type: {notification_type}')
            return False

        subjects = {
            'new_login': f'New login to your {self.site_name} account',
            'password_changed': f'Your {self.site_name} password was changed',
            'profile_updated': f'Your {self.site_name} profile was updated',
            'security_alert': f'Security alert for your {self.site_name} account',
        }

        context = {
            'user': user,
            'site_name': self.site_name,
            **data
        }

        return self._send_template_email(
            to_email=user.email,
            subject=subjects[notification_type],
            template=template,
            context=context
        )

    def _send_template_email(
        self,
        to_email: str,
        subject: str,
        template: str,
        context: Dict[str, Any]
    ) -> bool:
        """Send email using template."""
        try:
            html_content = render_to_string(template, context)
            text_content = strip_tags(html_content)

            email = EmailMultiAlternatives(
                subject=subject,
                body=text_content,
                from_email=self.from_email,
                to=[to_email]
            )
            email.attach_alternative(html_content, 'text/html')
            email.send()

            logger.info(f'Email sent successfully to {to_email}')
            return True

        except Exception as e:
            logger.error(f'Failed to send email to {to_email}: {str(e)}')
            return False

    def _generate_verification_token(self, user) -> str:
        """Generate email verification token."""
        from django.contrib.auth.tokens import default_token_generator
        return default_token_generator.make_token(user)

    def _send_simple_email(
        self,
        to_email: str,
        subject: str,
        message: str
    ) -> bool:
        """Send simple text email."""
        try:
            send_mail(
                subject=subject,
                message=message,
                from_email=self.from_email,
                recipient_list=[to_email],
                fail_silently=False
            )
            return True
        except Exception as e:
            logger.error(f'Failed to send simple email: {str(e)}')
            return False
