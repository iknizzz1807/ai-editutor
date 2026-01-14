// src/main/java/com/myapp/service/EmailService.java - Email service

package com.myapp.service;

import com.myapp.config.AppConfig;
import com.myapp.model.User;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.thymeleaf.TemplateEngine;
import org.thymeleaf.context.Context;

import jakarta.mail.MessagingException;
import jakarta.mail.internet.MimeMessage;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Service
@RequiredArgsConstructor
@Slf4j
public class EmailService {

    private final JavaMailSender mailSender;
    private final TemplateEngine templateEngine;
    private final AppConfig appConfig;

    @Async
    public void sendVerificationEmail(User user) {
        String token = generateVerificationToken(user);
        String verificationUrl = appConfig.getBaseUrl() + "/verify-email?token=" + token;

        Map<String, Object> variables = new HashMap<>();
        variables.put("user", user);
        variables.put("verificationUrl", verificationUrl);
        variables.put("siteName", appConfig.getName());

        sendTemplateEmail(
            user.getEmail(),
            "Verify your email for " + appConfig.getName(),
            "email/verify-email",
            variables
        );
    }

    @Async
    public void sendPasswordResetEmail(User user, String token) {
        String resetUrl = appConfig.getBaseUrl() + "/reset-password?token=" + token;

        Map<String, Object> variables = new HashMap<>();
        variables.put("user", user);
        variables.put("resetUrl", resetUrl);
        variables.put("siteName", appConfig.getName());
        variables.put("expiresIn", "24 hours");

        sendTemplateEmail(
            user.getEmail(),
            "Reset your password for " + appConfig.getName(),
            "email/password-reset",
            variables
        );
    }

    @Async
    public void sendWelcomeEmail(User user) {
        Map<String, Object> variables = new HashMap<>();
        variables.put("user", user);
        variables.put("siteName", appConfig.getName());
        variables.put("loginUrl", appConfig.getBaseUrl() + "/login");

        sendTemplateEmail(
            user.getEmail(),
            "Welcome to " + appConfig.getName() + "!",
            "email/welcome",
            variables
        );
    }

    @Async
    public void sendSuspensionNotice(User user, String reason, Integer durationDays) {
        Map<String, Object> variables = new HashMap<>();
        variables.put("user", user);
        variables.put("reason", reason);
        variables.put("durationDays", durationDays);
        variables.put("siteName", appConfig.getName());
        variables.put("supportEmail", appConfig.getSupportEmail());

        sendTemplateEmail(
            user.getEmail(),
            "Your " + appConfig.getName() + " account has been suspended",
            "email/suspension-notice",
            variables
        );
    }

    // Q: How should we implement email delivery tracking and retry logic?
    public BulkEmailResult sendBulkEmail(List<User> users, String subject, String template, Map<String, Object> extraVariables) {
        BulkEmailResult result = new BulkEmailResult();

        for (User user : users) {
            try {
                Map<String, Object> variables = new HashMap<>(extraVariables);
                variables.put("user", user);
                variables.put("siteName", appConfig.getName());

                sendTemplateEmail(user.getEmail(), subject, template, variables);
                result.incrementSent();
            } catch (Exception e) {
                log.error("Failed to send email to {}: {}", user.getEmail(), e.getMessage());
                result.addError(user.getEmail(), e.getMessage());
            }
        }

        return result;
    }

    @Async
    public void sendNotificationEmail(User user, NotificationType type, Map<String, Object> data) {
        String subject;
        String template;

        switch (type) {
            case NEW_LOGIN:
                subject = "New login to your " + appConfig.getName() + " account";
                template = "email/new-login";
                break;
            case PASSWORD_CHANGED:
                subject = "Your " + appConfig.getName() + " password was changed";
                template = "email/password-changed";
                break;
            case PROFILE_UPDATED:
                subject = "Your " + appConfig.getName() + " profile was updated";
                template = "email/profile-updated";
                break;
            case SECURITY_ALERT:
                subject = "Security alert for your " + appConfig.getName() + " account";
                template = "email/security-alert";
                break;
            default:
                log.warn("Unknown notification type: {}", type);
                return;
        }

        Map<String, Object> variables = new HashMap<>(data);
        variables.put("user", user);
        variables.put("siteName", appConfig.getName());

        sendTemplateEmail(user.getEmail(), subject, template, variables);
    }

    private void sendTemplateEmail(String to, String subject, String template, Map<String, Object> variables) {
        try {
            Context context = new Context();
            context.setVariables(variables);

            String htmlContent = templateEngine.process(template, context);

            MimeMessage message = mailSender.createMimeMessage();
            MimeMessageHelper helper = new MimeMessageHelper(message, true, "UTF-8");
            helper.setFrom(appConfig.getFromEmail());
            helper.setTo(to);
            helper.setSubject(subject);
            helper.setText(htmlContent, true);

            mailSender.send(message);
            log.info("Email sent successfully to {}: {}", to, subject);
        } catch (MessagingException e) {
            log.error("Failed to send email to {}: {}", to, e.getMessage());
            throw new RuntimeException("Failed to send email", e);
        }
    }

    private String generateVerificationToken(User user) {
        // Would generate actual secure token
        return "verify_" + user.getId().toString();
    }

    public enum NotificationType {
        NEW_LOGIN,
        PASSWORD_CHANGED,
        PROFILE_UPDATED,
        SECURITY_ALERT
    }

    public static class BulkEmailResult {
        private int sent = 0;
        private int failed = 0;
        private Map<String, String> errors = new HashMap<>();

        public void incrementSent() {
            sent++;
        }

        public void addError(String email, String error) {
            failed++;
            errors.put(email, error);
        }

        public int getSent() { return sent; }
        public int getFailed() { return failed; }
        public Map<String, String> getErrors() { return errors; }
    }
}
